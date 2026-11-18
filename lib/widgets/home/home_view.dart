/*
 * TvOS — a minimal home screen built on FLauncher / LTvLauncher.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flauncher/models/app.dart';
import 'package:flauncher/models/category.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/now_playing_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/watch_next_service.dart';
import 'package:flauncher/widgets/app_card_keys.dart';
import 'package:flauncher/widgets/focus_keyboard_listener.dart';
import 'package:flauncher/widgets/home/ambience.dart';
import 'package:flauncher/widgets/home/home_slot.dart';
import 'package:flauncher/widgets/home/top_info.dart';
import 'package:flauncher/widgets/home/video_loops.dart';
import 'package:flauncher/widgets/settings/settings_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

const int _homeColumns = 5;
// The Home column under the slot, where Down from it lands.
const int _slotColumn = 2;
const int _homeSlots = 10;
const int _allAppsColumns = 7;
// With the 16px body padding this keeps the outer cards inside the TV-safe edge.
const double _sidePadding = 40;
const String _favoritesName = 'Favorites';
const Color _cardColor = Color(0xFF2A2A2E);

/// First-run contents of the top rows, before the user arranges them.
const _defaultFavorites = [
  'com.spotify.tv.android',
  'com.netflix.ninja',
  'com.peacocktv.peacockandroid',
  'com.apple.atve.androidtv.appletv',
  'com.cbs.ott', // Paramount+
  'com.google.android.youtube.tv',
  'com.disney.disneyplus',
  'com.espn.score_center',
  'com.hulu.livingroomplus',
  'com.fox.foxone',
];

/// Utilities that rank high on screen time but aren't what anyone sits down to open.
const _neverSeeded = {'com.android.tv.settings'};

bool _isSelf(App app) =>
    app.packageName.startsWith('com.spencerking.tvos') || app.packageName.startsWith('com.leanbitlab.ltvL');

/// First-run Home rows: the pinned apps in order, then the most-watched of the rest.
@visibleForTesting
List<App> pickHomeApps(List<App> all, Map<String, int> usage) {
  final byName = {for (final app in all) app.packageName: app};
  final picks = <App>[
    for (final name in _defaultFavorites)
      if (byName[name] != null) byName[name]!,
  ];
  final byUsage = all
      .where((a) => (usage[a.packageName] ?? 0) > 0)
      .where((a) => !_neverSeeded.contains(a.packageName) && !_isSelf(a) && !picks.contains(a))
      .sorted((a, b) => usage[b.packageName]!.compareTo(usage[a.packageName]!));
  return [...picks, ...byUsage.take(_homeSlots - picks.length)];
}

Category? _favorites(AppsService service) =>
    service.launcherSections.whereType<Category>().firstWhereOrNull((c) => c.name == _favoritesName);

/// Every launchable app once, alphabetical, without this launcher itself.
List<App> _allApps(AppsService service) {
  final seen = <String>{};
  return [
    for (final category in service.launcherSections.whereType<Category>())
      for (final app in category.applications)
        if (!_isSelf(app) && seen.add(app.packageName)) app,
  ].sorted((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  @override
  void initState() {
    super.initState();
    _seedFavoritesOnce();
    WidgetsBinding.instance.addPostFrameCallback((_) => _askForWatchNextOnce());
    // Tell the background how far into All Apps we are, so it can dim behind the grid.
    _scroll.addListener(() {
      final height = MediaQuery.sizeOf(context).height;
      context.read<HomeAmbience>().allApps = _scroll.offset / (height * 0.7);
    });
  }

  /// Fills Favorites on first run: the pinned ten, then the most-watched apps for any that aren't installed.
  Future<void> _seedFavoritesOnce() async {
    final settings = context.read<SettingsService>();
    final service = context.read<AppsService>();
    if (settings.homeFavoritesSeeded) return;

    final favorites = _favorites(service);
    if (favorites == null || favorites.applications.where((a) => !_isSelf(a)).isEmpty) {
      await service.refreshForegroundTime();
      await service.addAllToFavorites(pickHomeApps(_allApps(service), service.foregroundTime));
    }
    await settings.setHomeFavoritesSeeded();
  }

  final ScrollController _scroll = ScrollController();
  final GlobalKey _allAppsHeader = GlobalKey();
  final FocusNode _menuNode = FocusNode(debugLabel: 'home menu');
  final FocusNode _slotNode = FocusNode(debugLabel: 'home slot');
  // The slot moves between two layouts as music starts and stops; the key carries it (and its focus) across.
  final GlobalKey _slotKey = GlobalKey();
  // The clock keeps its state (and weather) however the top half rebuilds.
  final GlobalKey _clockKey = GlobalKey();

  /// Continue watching needs the TV-listings permission; ask for it once, the first time Home opens.
  Future<void> _askForWatchNextOnce() async {
    if (!mounted) return;
    final settings = context.read<SettingsService>();
    final watch = context.read<WatchNextService>();
    if (settings.watchNextAsked) return;
    await settings.setWatchNextAsked();
    if (!await watch.checkPermission()) await watch.requestPermission();
  }

  /// OK on the slot: back into the song's app, or straight to where the show was left.
  void _openSlot(SlotEntry entry) {
    switch (entry) {
      case SlotTrack(:final track):
        final apps = context.read<AppsService>();
        final app = apps.applications.firstWhereOrNull((a) => a.packageName == track.packageName);
        if (app != null) apps.launchApp(app);
      case SlotWatch(:final program):
        context.read<WatchNextService>().launch(program);
    }
  }

  Future<void> _showHomeMenu() async {
    final settings = context.read<SettingsService>();
    final choice = await showDialog<String>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _HomeMenu(background: settings.homeBackground),
    );
    if (!mounted || choice == null) return;
    if (choice == 'settings') {
      await showDialog(context: context, builder: (_) => const SettingsPanel());
    } else {
      await settings.setHomeBackground(choice);
    }
    _menuNode.requestFocus();
  }

  /// One focus node per home app, so focus can be put back on a specific slot.
  final Map<String, FocusNode> _homeNodes = {};

  /// Package of the home app being moved, if any.
  String? _moving;

  FocusNode _nodeFor(String packageName) => _homeNodes.putIfAbsent(packageName, FocusNode.new);

  @override
  void dispose() {
    _scroll.dispose();
    _menuNode.dispose();
    _slotNode.dispose();
    for (final node in _homeNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _scrollTo(double offset) =>
      _scroll.animateTo(offset, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);

  void _revealAllAppsHeader() {
    final header = _allAppsHeader.currentContext;
    if (header != null) {
      Scrollable.ensureVisible(header,
          // Leaves the "⌃ Home" hint near the top with clear space above the heading.
          alignment: 0.15, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    }
  }

  List<App> _home(AppsService service) =>
      _favorites(service)?.applications.where((a) => !_isSelf(a)).take(_homeSlots).toList() ?? [];

  /// Focuses a Home slot after the next frame (so a just-removed app's slot is rebuilt).
  void _focusHomeSlot(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final home = _home(context.read<AppsService>());
      if (home.isEmpty) return;
      _nodeFor(home[index.clamp(0, home.length - 1)].packageName).requestFocus();
    });
    // A post-frame callback only runs if something draws a frame; Back alone doesn't.
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<AppsService>();
    final home = _home(service);
    final everything = _allApps(service);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final slots = currentSlot(context.watch<NowPlayingService>(), context.watch<WatchNextService>(),
        apps: {for (final app in home) app.packageName});
    // The slot emptied under focus (nothing left to show): drop back to the apps below it.
    if (slots.isEmpty && _slotNode.hasFocus) _focusHomeSlot(_slotColumn);
    final slot = HomeSlot(
      key: _slotKey,
      entries: slots,
      focusNode: _slotNode,
      onSelect: _openSlot,
      onControl: (action) => context.read<NowPlayingService>().control(action),
      onDown: () => _focusHomeSlot(_slotColumn),
      onRight: _menuNode.requestFocus,
    );

    return SingleChildScrollView(
      controller: _scroll,
      physics: const ClampingScrollPhysics(),
      clipBehavior: Clip.none,
      padding: const EdgeInsets.symmetric(horizontal: _sidePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // First screen: the top ~third kept for future "top content" (for now just the
          // time), your apps in the remaining ~two-thirds, and a hint that more is below.
          SizedBox(
            height: screenHeight - 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: screenHeight * 0.44,
                  // Time/date/weather sit small in the corner; the rest is free for more content.
                  child: Stack(
                    children: [
                      Align(
                        alignment: Alignment.topLeft,
                        // Left edge on the app tiles' left edge, so the whole screen hangs off one line.
                        child: Padding(
                            // The menu button sits out past the content margin, so a little room is enough.
                            padding: const EdgeInsets.only(top: 18, right: 24),
                            // The one-line clock over the hero spot, always; with nothing to show,
                            // the rest of the top half is left to the background.
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Align(alignment: Alignment.centerLeft, child: TopInfo(key: _clockKey)),
                                // Centred between the clock line and the app tiles, the same room above and below.
                                Expanded(child: Align(alignment: Alignment.centerLeft, child: slot)),
                              ],
                            ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.topRight,
                        // Out past the content margins, into the screen's own corner (about 20
                        // from the top and right edges); it's a quiet utility, not a destination.
                        child: Transform.translate(
                          offset: const Offset(_sidePadding - 4, 4),
                          child: _MenuButton(
                            focusNode: _menuNode,
                            onPressed: _showHomeMenu,
                            onDown: () => _focusHomeSlot(_homeColumns - 1),
                            onLeft: slots.isEmpty ? null : _slotNode.requestFocus,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _TileGrid(
                  columns: _homeColumns,
                  children: [
                    for (var i = 0; i < home.length; i++)
                      HomeTile(
                        key: ValueKey(home[i].packageName),
                        app: home[i],
                        focusNode: _nodeFor(home[i].packageName),
                        autofocus: i == 0,
                        // Up reaches the slot from under it and to its left, the menu from the last column.
                        onUp: i < _homeColumns
                            ? (slots.isNotEmpty && i < _homeColumns - 1 ? _slotNode.requestFocus : _menuNode.requestFocus)
                            : null,
                        onFocus: () => _scrollTo(0),
                        onHold: () => setState(() => _moving = home[i].packageName),
                        moving: _moving == home[i].packageName,
                        moveArrows: _moving == home[i].packageName ? _arrowsAt(i, home.length) : const {},
                        onMoveKey: (direction) => _move(service, home[i], home.length, direction),
                        onMoveDone: (commit) => _endMove(service, commit),
                        onRemove: () => _removeFromHome(service, home, i),
                      ),
                  ],
                ),
                const Spacer(),
                _BottomHint(moving: _moving != null),
                const SizedBox(height: 22),
              ],
            ),
          ),
          // Everything else, reached by pressing down past your apps.
          Padding(
            key: _allAppsHeader,
            padding: const EdgeInsets.only(top: 40, bottom: 36),
            child: const Text(
              'All Apps',
              style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w600),
            ),
          ),
          _TileGrid(
            columns: _allAppsColumns,
            gap: 24,
            children: [
              for (var i = 0; i < everything.length; i++)
                HomeTile(
                  key: ValueKey('all:${everything[i].packageName}'),
                  app: everything[i],
                  autofocus: home.isEmpty && i == 0,
                  onFocus: i < _allAppsColumns ? _revealAllAppsHeader : null,
                  onUp: i < _allAppsColumns ? () => _focusHomeSlot(_homeColumns + (i * (_homeColumns - 1) / (_allAppsColumns - 1)).round()) : null,
                  onBack: () => _focusHomeSlot(0),
                  onHold: () => _addToHome(service, home, everything[i]),
                ),
            ],
          ),
          SizedBox(height: screenHeight * 0.3),
        ],
      ),
    );
  }

  /// Directions a home app at [index] can still move within [count] slots.
  Set<AxisDirection> _arrowsAt(int index, int count) => {
        if (index > 0) AxisDirection.left,
        if (index + 1 < count) AxisDirection.right,
        if (index - _homeColumns >= 0) AxisDirection.up,
        if (index + _homeColumns < count) AxisDirection.down,
      };

  /// Moves an app one step: left/right by one slot, up/down by a row.
  void _move(AppsService service, App app, int count, AxisDirection direction) {
    final favorites = _favorites(service);
    if (favorites == null) return;
    final index = favorites.applications.indexWhere((a) => a.packageName == app.packageName);
    if (index < 0 || !_arrowsAt(index, count).contains(direction)) return;
    final target = switch (direction) {
      AxisDirection.left => index - 1,
      AxisDirection.right => index + 1,
      AxisDirection.up => index - _homeColumns,
      AxisDirection.down => index + _homeColumns,
    };
    service.reorderApplication(favorites, index, target);
  }

  void _endMove(AppsService service, bool commit) {
    final favorites = _favorites(service);
    if (favorites != null) {
      commit ? service.saveApplicationOrderInCategory(favorites) : service.cancelReorderApplication(favorites);
    }
    setState(() => _moving = null);
  }

  /// Hold OK while moving: take the app off Home (it stays in All Apps).
  Future<void> _removeFromHome(AppsService service, List<App> home, int index) async {
    final app = home[index];
    _endMove(service, true);
    await service.removeFromFavorites(app);
    _focusHomeSlot(index);
    _toast('${app.name} removed from Home');
  }

  /// Hold OK in All Apps: put the app on Home, in the next free slot.
  Future<void> _addToHome(AppsService service, List<App> home, App app) async {
    if (home.any((a) => a.packageName == app.packageName)) {
      _toast('${app.name} is already on Home');
    } else if (home.length >= _homeSlots) {
      _toast('Home is full — hold OK on a Home app to remove one');
    } else {
      await service.addToFavorites(app);
      _toast('${app.name} added to Home');
    }
  }

  OverlayEntry? _toastEntry;

  /// A brief, quiet confirmation pill near the bottom of the screen.
  void _toast(String message) {
    _toastEntry?.remove();
    final entry = OverlayEntry(builder: (_) => _Toast(message: message));
    _toastEntry = entry;
    Overlay.of(context).insert(entry);
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (_toastEntry == entry) {
        entry.remove();
        _toastEntry = null;
      }
    });
  }
}

class _Toast extends StatelessWidget {
  final String message;

  const _Toast({required this.message});

  @override
  Widget build(BuildContext context) => Positioned(
        left: 0,
        right: 0,
        bottom: 64,
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 200),
            builder: (_, t, child) => Opacity(opacity: t, child: child),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xE61E1E22),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w500, decoration: TextDecoration.none),
              ),
            ),
          ),
        ),
      );
}

/// A faint control in the top-right corner, reached by pressing Up from the top row.
class _MenuButton extends StatefulWidget {
  final FocusNode focusNode;
  final VoidCallback onPressed;
  final VoidCallback onDown;
  final VoidCallback? onLeft;

  const _MenuButton({required this.focusNode, required this.onPressed, required this.onDown, this.onLeft});

  @override
  State<_MenuButton> createState() => _MenuButtonState();
}

class _MenuButtonState extends State<_MenuButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => Focus(
        focusNode: widget.focusNode,
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (AppCardKeys.validationKeys.contains(event.logicalKey)) {
            widget.onPressed();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            widget.onDown();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft && widget.onLeft != null) {
            widget.onLeft!();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // A faint dark disc and soft shadow keep it visible over bright sky.
            color: _focused ? Colors.white : Colors.black.withOpacity(0.22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(_focused ? 0.45 : 0.3),
                blurRadius: _focused ? 18 : 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(
            Icons.tune_rounded,
            size: 14,
            color: _focused ? Colors.black : Colors.white60,
            shadows: _focused ? null : const [Shadow(color: Colors.black54, blurRadius: 4)],
          ),
        ),
      );
}

/// Background choice plus a way into the full launcher settings.
class _HomeMenu extends StatelessWidget {
  final String background;

  const _HomeMenu({required this.background});

  @override
  Widget build(BuildContext context) {
    Widget option(String value, IconData icon, String label, {bool enabled = true, bool first = false}) {
      final selected = background == value;
      return TextButton(
        autofocus: first,
        onPressed: enabled ? () => Navigator.of(context).pop(value) : null,
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
          alignment: Alignment.centerLeft,
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.focused) ? Colors.black : (enabled ? Colors.white : Colors.white38)),
          backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.focused) ? Colors.white : Colors.transparent),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500))),
            if (selected) const Icon(Icons.check_rounded, size: 22),
          ],
        ),
      );
    }

    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.only(top: 64, right: 20),
        child: Material(
          color: const Color(0xF21E1E22),
          borderRadius: BorderRadius.circular(20),
          child: SizedBox(
            width: 340,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(18, 8, 18, 8),
                    child: Text('Background', style: TextStyle(color: Colors.white54, fontSize: 15)),
                  ),
                  option('gradient', Icons.gradient_rounded, 'Gradient', first: true),
                  option('landscapes', Icons.landscape_rounded, 'Landscapes'),
                  option('video', Icons.movie_filter_rounded, videoLoopsAvailable ? 'Video loops' : 'Video loops (needs setup)',
                      enabled: videoLoopsAvailable),
                  const Divider(color: Colors.white12, height: 20),
                  option('settings', Icons.settings_rounded, 'Launcher settings'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

bool _okHeld() => HardwareKeyboard.instance.logicalKeysPressed.any(AppCardKeys.validationKeys.contains);

class _TileGrid extends StatelessWidget {
  final int columns;
  final List<Widget> children;
  final double gap;

  // 40 leaves room for a focused card's 1.12× lift without touching its neighbours.
  const _TileGrid({required this.columns, required this.children, this.gap = 40});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          clipBehavior: Clip.none,
          // The wrapper carries the child's key so a tile keeps its state (and focus)
          // when reordering shifts it to another slot.
          children: [for (final child in children) SizedBox(key: child.key, width: width, child: child)],
        );
      });
}

/// A quiet cue between Home and All Apps: "All Apps ⌄" below your rows, "⌃ Home" once
/// you've scrolled down (it then sits at the top of the screen), or how to finish a move.
class _BottomHint extends StatelessWidget {
  final bool moving;

  const _BottomHint({required this.moving});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(color: Colors.white38, fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.4);
    final inAllApps = context.select<HomeAmbience, bool>((ambience) => ambience.allApps > 0.5);
    final Widget hint;
    if (moving) {
      hint = const Center(
        key: ValueKey('moving'),
        child: Text('OK to place   ·   Back to cancel   ·   Hold OK to remove from Home', style: style),
      );
    } else if (inAllApps) {
      hint = const Row(
        key: ValueKey('home'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.keyboard_arrow_up_rounded, color: Colors.white38, size: 20),
          SizedBox(width: 4),
          Text('Home', style: style),
        ],
      );
    } else {
      hint = const Row(
        key: ValueKey('more'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('All Apps', style: style),
          SizedBox(width: 4),
          Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white38, size: 20),
        ],
      );
    }
    return SizedBox(
      height: 24,
      child: AnimatedSwitcher(duration: const Duration(milliseconds: 220), child: hint),
    );
  }
}

/// Scrolls only as far as needed to show the focused slot, so a screen that already
/// fits (the home rows) never moves.
void _ensureVisible(BuildContext context) {
  final position = Scrollable.maybeOf(context)?.position;
  final box = context.findRenderObject();
  if (position == null || box is! RenderBox || !box.attached) return;
  final viewport = RenderAbstractViewport.maybeOf(box);
  if (viewport == null) return;

  final top = viewport.getOffsetToReveal(box, 0.0).offset;
  final bottom = viewport.getOffsetToReveal(box, 1.0).offset;
  final target = position.pixels.clamp(bottom, top);
  if (target != position.pixels) {
    position.animateTo(target, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
  }
}

/// An app in a slot. OK opens it; holding OK hands the app to the parent ([onHold]).
/// While [moving], arrows move it instead of focus, OK places it and Back cancels.
class HomeTile extends StatefulWidget {
  final App app;
  final bool autofocus;
  final FocusNode? focusNode;

  /// Pressing Up (top row only): where focus goes instead of the row above.
  final VoidCallback? onUp;

  /// Replaces the default "scroll just enough to show me" when this tile gains focus.
  final VoidCallback? onFocus;
  final VoidCallback? onBack;
  final VoidCallback? onHold;

  /// Holding OK while [moving].
  final VoidCallback? onRemove;

  final bool moving;
  final Set<AxisDirection> moveArrows;
  final void Function(AxisDirection)? onMoveKey;

  /// Called with true to keep the new position, false to put it back.
  final void Function(bool commit)? onMoveDone;

  const HomeTile({
    super.key,
    required this.app,
    this.autofocus = false,
    this.onUp,
    this.focusNode,
    this.onFocus,
    this.onBack,
    this.onHold,
    this.onRemove,
    this.moving = false,
    this.moveArrows = const {},
    this.onMoveKey,
    this.onMoveDone,
  });

  @override
  State<HomeTile> createState() => _HomeTileState();
}

class _HomeTileState extends State<HomeTile> with SingleTickerProviderStateMixin {
  late final FocusNode _focusNode = widget.focusNode ?? FocusNode();
  late Future<(bool, Uint8List)> _image;
  bool _focused = false;
  bool _pressed = false;

  /// Set when a move starts while OK is still held, so that press's release doesn't place it.
  bool _ignoreHeldOk = false;

  /// Breathing glow around an app being moved.
  late final AnimationController _glow =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    _image = _loadImage();
  }

  @override
  void didUpdateWidget(HomeTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app.packageName != widget.app.packageName) _image = _loadImage();
    if (widget.moving && !oldWidget.moving) {
      _ignoreHeldOk = _okHeld();
      _glow.repeat(reverse: true);
    } else if (!widget.moving && oldWidget.moving) {
      _glow.stop();
      _glow.value = 0;
    }
  }

  @override
  void dispose() {
    _glow.dispose();
    if (widget.focusNode == null) _focusNode.dispose();
    super.dispose();
  }

  /// (isBanner, bytes) — TV apps ship a 16:9 banner; others only have an icon.
  Future<(bool, Uint8List)> _loadImage() async {
    final service = context.read<AppsService>();
    final banner = await service.getAppBanner(widget.app.packageName);
    if (banner.isNotEmpty) return (true, banner);
    return (false, await service.getAppIcon(widget.app.packageName));
  }

  @override
  Widget build(BuildContext context) {
    final lifted = _focused || widget.moving;
    return FocusKeyboardListener(
      onPressed: _onPressed,
      onLongPress: _onLongPress,
      builder: (context) => Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedScale(
            scale: _pressed ? 0.96 : (lifted ? 1.12 : 1.0),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: AnimatedBuilder(
              animation: _glow,
              builder: (context, child) => DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(lifted ? 0.6 : 0.25),
                      blurRadius: lifted ? 40 : 10,
                      offset: Offset(0, lifted ? 22 : 4),
                    ),
                    if (widget.moving)
                      BoxShadow(
                        color: Colors.white.withOpacity(0.25 + 0.35 * Curves.easeInOut.transform(_glow.value)),
                        blurRadius: 30,
                        spreadRadius: 2,
                      ),
                  ],
                ),
                child: child,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Focus(
                    focusNode: _focusNode,
                    autofocus: widget.autofocus,
                    onFocusChange: _onFocusChange,
                    onKeyEvent: _swallowHeldOk,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _artwork(),
                        // A soft light across the top-left of the focused card.
                        IgnorePointer(
                          child: AnimatedOpacity(
                            opacity: lifted ? 1 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment(0.3, 0.6),
                                  colors: [Color(0x40FFFFFF), Color(0x00FFFFFF)],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          for (final direction in widget.moveArrows) _arrow(direction),
        ],
      ),
    );
  }

  /// A chevron centred in the gap between the lifted card and its neighbour,
  /// pointing where the app can go. Offsets are for the 34px icon in a 40px gap.
  Widget _arrow(AxisDirection direction) {
    const side = -46.0;
    const vertical = -44.0;
    final (icon, left, top, right, bottom) = switch (direction) {
      AxisDirection.left => (Icons.chevron_left_rounded, side, 0.0, null, 0.0),
      AxisDirection.right => (Icons.chevron_right_rounded, null, 0.0, side, 0.0),
      AxisDirection.up => (Icons.expand_less_rounded, 0.0, vertical, 0.0, null),
      AxisDirection.down => (Icons.expand_more_rounded, 0.0, null, 0.0, vertical),
    };
    return Positioned(
      left: left,
      top: top,
      right: right,
      bottom: bottom,
      child: IgnorePointer(
        child: Center(
          child: Icon(icon, color: Colors.white, size: 34, shadows: const [Shadow(color: Colors.black87, blurRadius: 10)]),
        ),
      ),
    );
  }

  Widget _artwork() => FutureBuilder<(bool, Uint8List)>(
        future: _image,
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null || data.$2.isEmpty) return Container(color: _cardColor);
          final (isBanner, bytes) = data;
          if (isBanner) {
            // Some banners (Spotify's) are a logo on transparency; the card colour backs them.
            return Container(
              color: _cardColor,
              child: Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true),
            );
          }
          // Phone-style apps have only a square icon: show it with the name, banner-shaped.
          return Container(
            color: _cardColor,
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
            child: Column(
              children: [
                Expanded(child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true)),
                const SizedBox(height: 6),
                Text(
                  widget.app.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          );
        },
      );

  KeyEventResult _swallowHeldOk(FocusNode _, KeyEvent event) {
    if (!_ignoreHeldOk || !AppCardKeys.validationKeys.contains(event.logicalKey)) return KeyEventResult.ignored;
    if (event is KeyUpEvent) _ignoreHeldOk = false;
    return KeyEventResult.handled;
  }

  Offset? _screenCenter() {
    if (!mounted) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached) return null;
    return box.localToGlobal(box.size.center(Offset.zero));
  }

  void _onFocusChange(bool focused) {
    setState(() => _focused = focused);
    if (focused) {
      final ambience = context.read<HomeAmbience>();
      _image.then((image) {
        final center = _screenCenter();
        if (_focused && center != null) ambience.focus(widget.app.packageName, image.$2, center);
      });
      // If focusing scrolled the page, report where the tile settled.
      Future.delayed(const Duration(milliseconds: 340), () {
        final center = _screenCenter();
        if (_focused && center != null) ambience.moveFocus(widget.app.packageName, center);
      });
    }
    // Leaving the tile mid-move (e.g. pressing Home) keeps the new position.
    if (!focused && widget.moving) widget.onMoveDone?.call(true);
    if (focused) (widget.onFocus ?? () => _ensureVisible(context))();
  }

  KeyEventResult _onPressed(LogicalKeyboardKey key) {
    if (widget.moving) {
      final direction = switch (key) {
        LogicalKeyboardKey.arrowLeft => AxisDirection.left,
        LogicalKeyboardKey.arrowRight => AxisDirection.right,
        LogicalKeyboardKey.arrowUp => AxisDirection.up,
        LogicalKeyboardKey.arrowDown => AxisDirection.down,
        _ => null,
      };
      if (direction != null) {
        widget.onMoveKey?.call(direction);
      } else if (AppCardKeys.validationKeys.contains(key)) {
        widget.onMoveDone?.call(true);
      } else if (AppCardKeys.cancelKeys.contains(key)) {
        widget.onMoveDone?.call(false);
      }
      return KeyEventResult.handled;
    }

    if (AppCardKeys.cancelKeys.contains(key) && widget.onBack != null) {
      widget.onBack!();
      return KeyEventResult.handled;
    }
    if (AppCardKeys.validationKeys.contains(key)) {
      _launch();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp && widget.onUp != null) {
      widget.onUp!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onLongPress(LogicalKeyboardKey key) {
    final action = widget.moving ? widget.onRemove : widget.onHold;
    if (action == null || !AppCardKeys.longPressableKeys.contains(key)) return KeyEventResult.ignored;
    action();
    return KeyEventResult.handled;
  }

  void _launch() {
    if (_pressed) return;
    setState(() => _pressed = true);
    Future.delayed(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      context.read<AppsService>().launchApp(widget.app);
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) setState(() => _pressed = false);
      });
    });
  }
}
