/*
 * TvOS — a minimal home screen built on FLauncher / LTvLauncher.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'dart:ui';

import 'package:flauncher/custom_traversal_policy.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/home/video_loops.dart';
import 'package:flauncher/widgets/dev_tag.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The TV's side of the quick panel: live inputs, switching to one, opening Settings pages.
class QuickPanelChannel {
  static const _channel = MethodChannel('tvos/quick_panel');

  static VoidCallback? _onOpened;
  static VoidCallback? _onHome;

  /// Runs when the remote's settings button asks for the panel.
  static set onOpened(VoidCallback? callback) {
    _onOpened = callback;
    _listen();
  }

  /// Runs when the remote's Home button is pressed while Home is already in front.
  static set onHome(VoidCallback? callback) {
    _onHome = callback;
    _listen();
  }

  static void _listen() => _channel.setMethodCallHandler(_onOpened == null && _onHome == null
      ? null
      : (call) async {
          if (call.method == 'opened') _onOpened?.call();
          if (call.method == 'home') _onHome?.call();
        });

  static Future<List<TvInput>> inputs() async {
    try {
      final list = await _channel.invokeListMethod<Map<dynamic, dynamic>>('inputs') ?? [];
      return [for (final m in list) TvInput(m['id'] as String, m['label'] as String, standby: m['standby'] == true)];
    } catch (e) {
      debugPrint('Quick panel: no inputs ($e)');
      return [];
    }
  }

  static Future<void> openInput(String id) => _call('openInput', id);
  static Future<void> openSettings(String action) => _call('openSettings', action);
  static Future<void> close() => _call('close');

  static Future<void> _call(String method, [Object? argument]) async {
    try {
      await _channel.invokeMethod(method, argument);
    } catch (e) {
      debugPrint('Quick panel: $method failed ($e)');
    }
  }
}

class TvInput {
  final String id;
  final String label;

  /// Connected but asleep: choosing it may wake the device over HDMI-CEC.
  final bool standby;

  const TvInput(this.id, this.label, {this.standby = false});
}

/// The cards under the inputs, each opening a Settings page by its action (all of Settings
/// when the TV lacks one). All of these resolve on the living-room Hisense.
const quickSettings = [
  (Icons.image_outlined, 'Picture', 'android.settings.DISPLAY_SETTINGS'),
  (Icons.volume_up_outlined, 'Sound', 'android.settings.SOUND_SETTINGS'),
  (Icons.wifi_rounded, 'Network', 'android.settings.WIFI_SETTINGS'),
  (Icons.bedtime_outlined, 'Sleep', 'android.settings.TIMER_SETTINGS'),
];

const allSettingsAction = 'android.settings.SETTINGS';

const backgrounds = [
  ('gradient', Icons.gradient_rounded, 'Gradient'),
  ('landscapes', Icons.landscape_rounded, 'Landscapes'),
  ('video', Icons.movie_filter_rounded, 'Video loops'),
];

enum _Page { main, inputs }

/// A floating glass card at the top right: a gear for all of Settings, the live inputs in one
/// row (⋯ lists every input, asleep ones too), then small cards for the main Settings pages
/// and the background chips. Back steps out of a list, then closes.
class QuickPanel extends StatefulWidget {
  static const double width = 400;

  /// The current background, and what to do when one is picked (no section until it can be set).
  final String? background;
  final ValueChanged<String>? onBackground;

  /// Asked to close (Back, or after opening something).
  final VoidCallback onClose;

  /// Whether what's behind can be blurred. Home can; another app's window can't be on this
  /// TV, so there the glass is a little more opaque instead.
  final bool blur;

  /// Lists the TV's inputs; replaced in tests.
  final Future<List<TvInput>> Function() loadInputs;

  const QuickPanel({
    super.key,
    required this.onClose,
    this.background,
    this.onBackground,
    this.blur = true,
    this.loadInputs = QuickPanelChannel.inputs,
  });

  @override
  State<QuickPanel> createState() => QuickPanelState();
}

class QuickPanelState extends State<QuickPanel> {
  List<TvInput>? _inputs;
  _Page _page = _Page.main;
  int _opened = 0;

  // Which background chip the remote is on, if any: the one in use folds to its icon then.
  String? _backgroundFocus;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Back to the top with fresh inputs, as if just opened.
  void reset() {
    setState(() {
      _page = _Page.main;
      _opened++;
    });
    _load();
  }

  Future<void> _load() async {
    final inputs = await widget.loadInputs();
    if (mounted) setState(() => _inputs = inputs);
  }

  void _back() {
    if (_page != _Page.main) {
      setState(() => _page = _Page.main);
    } else {
      widget.onClose();
    }
  }

  void _open(Future<void> Function() action) {
    action();
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(28));
    final glass = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: Colors.white.withOpacity(0.16)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: widget.blur
              ? [const Color(0x8C2A2A30), const Color(0x99141418)]
              : [const Color(0xD92A2A30), const Color(0xE6141418)],
        ),
      ),
      // A soft sheen from the top edge, like light on glass.
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.center,
            colors: [Colors.white.withOpacity(0.10), Colors.white.withOpacity(0)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: FocusTraversalGroup(
            // Row by row, like Home: Up and Down go to the nearest item in the row above or below.
          policy: RowByRowTraversalPolicy(),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: switch (_page) {
                _Page.main => _main(),
                _Page.inputs => _allInputs(),
              },
            ),
          ),
        ),
      ),
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Material(
            type: MaterialType.transparency,
            child: SizedBox(
              width: QuickPanel.width,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  borderRadius: radius,
                  boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 40, offset: Offset(0, 16))],
                ),
                child: ClipRRect(
                  borderRadius: radius,
                  child: widget.blur
                      ? BackdropFilter(filter: ImageFilter.blur(sigmaX: 32, sigmaY: 32), child: glass)
                      : glass,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _main() {
    final inputs = _inputs ?? const [];
    final live = inputs.where((i) => !i.standby).toList();
    final cards = <Widget>[
      for (final (i, (icon, label, action)) in quickSettings.indexed)
        PanelCard(
          icon: icon,
          label: label,
          // With nothing to switch to, the remote starts on the first card.
          autofocus: i == 0 && _inputs != null && inputs.isEmpty,
          onPressed: () => _open(() => QuickPanelChannel.openSettings(action)),
        ),
    ];
    return Column(
      key: ValueKey('main$_opened'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: _Heading('Inputs')),
            PanelChip(
              icon: Icons.settings_outlined,
              tooltip: 'All settings',
              onPressed: () => _open(() => QuickPanelChannel.openSettings(allSettingsAction)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final (i, input) in live.indexed)
              PanelChip(
                icon: Icons.settings_input_hdmi_rounded,
                label: input.label,
                autofocus: i == 0,
                onPressed: () => _open(() => QuickPanelChannel.openInput(input.id)),
              ),
            if (inputs.isNotEmpty)
              PanelChip(
                icon: Icons.more_horiz_rounded,
                tooltip: 'All inputs',
                autofocus: live.isEmpty,
                onPressed: () => setState(() => _page = _Page.inputs),
              ),
            if (_inputs != null && inputs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                child: Text('Nothing connected', style: TextStyle(color: Colors.white38, fontSize: 15)),
              ),
          ],
        ),
        // The background, one press each, staying open to flip between them.
        if (widget.onBackground != null) ...[
          const SizedBox(height: 22),
          const _Heading('Background'),
          const SizedBox(height: 8),
          // Only one chip is ever open, but wrap rather than overflow on a narrow screen.
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final (value, icon, label) in backgrounds)
                if (value != 'video' || videoLoopsAvailable)
                  BackgroundChip(
                    icon: icon,
                    label: label,
                    selected: widget.background == value,
                    showLabel: _backgroundFocus == value || (_backgroundFocus == null && widget.background == value),
                    onFocusChange: (focused) => setState(() {
                      if (focused) {
                        _backgroundFocus = value;
                      } else if (_backgroundFocus == value) {
                        _backgroundFocus = null;
                      }
                    }),
                    onPressed: () => widget.onBackground!(value),
                  ),
            ],
          ),
        ],
        const SizedBox(height: 22),
        const _Heading('Quick settings'),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.95,
          children: cards,
        ),
      ],
    );
  }

  Widget _allInputs() => Column(
        key: const ValueKey('inputs'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PanelRow(icon: Icons.chevron_left_rounded, label: 'Inputs', bold: true, onPressed: _back),
          const SizedBox(height: 6),
          for (final (i, input) in (_inputs ?? const <TvInput>[]).indexed)
            PanelRow(
              icon: Icons.settings_input_hdmi_rounded,
              label: input.label,
              trailing: input.standby ? 'Asleep' : null,
              dim: input.standby,
              autofocus: i == 0,
              onPressed: () => _open(() => QuickPanelChannel.openInput(input.id)),
            ),
        ],
      );
}

class _Heading extends StatelessWidget {
  final String text;

  const _Heading(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(text.toUpperCase(),
            style:
                const TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 1.4, fontWeight: FontWeight.w600)),
      );
}

ButtonStyle _focusStyle(
        {required BorderRadius radius, required EdgeInsets padding, bool dim = false, bool enabled = true}) =>
    ButtonStyle(
      padding: WidgetStatePropertyAll(padding),
      minimumSize: const WidgetStatePropertyAll(Size.zero),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      alignment: Alignment.centerLeft,
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: radius)),
      foregroundColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.focused) ? Colors.black : (!enabled || dim ? Colors.white38 : Colors.white)),
      backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.focused) ? Colors.white : Colors.white.withOpacity(0.08)),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    );

/// A pill: an input to switch to, ⋯ for all of them, or the gear.
class PanelChip extends StatelessWidget {
  final IconData icon;
  final String? label;
  final String? tooltip;
  final bool autofocus;
  final VoidCallback onPressed;

  const PanelChip(
      {super.key, required this.icon, required this.onPressed, this.label, this.tooltip, this.autofocus = false});

  @override
  Widget build(BuildContext context) => Semantics(
        label: tooltip,
        child: TextButton(
          autofocus: autofocus,
          onPressed: onPressed,
          style: _focusStyle(
            radius: BorderRadius.circular(22),
            padding: label == null ? const EdgeInsets.all(11) : const EdgeInsets.fromLTRB(14, 11, 18, 11),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20),
              if (label != null) ...[
                const SizedBox(width: 8),
                Text(label!, style: const TextStyle(fontSize: 15, letterSpacing: 0, fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
      );
}

/// One background: just its icon, opening out to its name while the remote is on it. The one
/// in use is white, and named unless the remote is on another.
class BackgroundChip extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool selected;

  /// Named: the one under the remote, or the one in use while the remote is elsewhere.
  final bool showLabel;
  final ValueChanged<bool> onFocusChange;
  final VoidCallback onPressed;

  const BackgroundChip({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.showLabel,
    required this.onFocusChange,
    required this.onPressed,
  });

  @override
  State<BackgroundChip> createState() => _BackgroundChipState();
}

class _BackgroundChipState extends State<BackgroundChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final open = widget.showLabel;
    return AnimatedScale(
      // The one under the remote lifts a little, so it stands apart from the one in use.
      scale: _focused ? 1.08 : 1,
      duration: const Duration(milliseconds: 160),
      child: TextButton(
        onPressed: widget.onPressed,
        onFocusChange: (focused) {
          setState(() => _focused = focused);
          widget.onFocusChange(focused);
        },
        style: _focusStyle(radius: BorderRadius.circular(22), padding: const EdgeInsets.all(11)).copyWith(
          // Here white means "on screen now": only the background in use is white. The one under
          // the remote is lighter glass with a thin white edge.
          foregroundColor: WidgetStatePropertyAll(widget.selected ? Colors.black : Colors.white),
          backgroundColor: WidgetStatePropertyAll(
              widget.selected ? Colors.white : Colors.white.withOpacity(_focused ? 0.24 : 0.08)),
          side: WidgetStatePropertyAll(
              _focused && !widget.selected ? const BorderSide(color: Colors.white70, width: 1.5) : BorderSide.none),
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 20),
              if (open) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(widget.label,
                      style: const TextStyle(fontSize: 15, letterSpacing: 0, fontWeight: FontWeight.w600)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A small square card: an icon, its name, and (for the background) what it is set to.
class PanelCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final bool autofocus;
  final VoidCallback onPressed;

  const PanelCard(
      {super.key,
      required this.icon,
      required this.label,
      required this.onPressed,
      this.value,
      this.autofocus = false});

  @override
  Widget build(BuildContext context) => TextButton(
        autofocus: autofocus,
        onPressed: onPressed,
        style: _focusStyle(radius: BorderRadius.circular(18), padding: const EdgeInsets.all(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(icon, size: 24),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, letterSpacing: 0, fontWeight: FontWeight.w600)),
                if (value != null)
                  Text(value!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, letterSpacing: 0, fontWeight: FontWeight.w400)),
              ],
            ),
          ],
        ),
      );
}

/// One line in a list (all inputs, backgrounds): white with dark text while the remote is on it.
class PanelRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? trailing;
  final bool selected;
  final bool dim;
  final bool bold;
  final bool enabled;
  final bool autofocus;
  final VoidCallback onPressed;

  const PanelRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.trailing,
    this.selected = false,
    this.dim = false,
    this.bold = false,
    this.enabled = true,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: TextButton(
          autofocus: autofocus,
          onPressed: enabled ? onPressed : null,
          style: _focusStyle(
            radius: BorderRadius.circular(14),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            dim: dim,
            enabled: enabled,
          ).copyWith(
            backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.focused) ? Colors.white : Colors.transparent),
          ),
          child: Row(
            children: [
              Icon(icon, size: 22),
              const SizedBox(width: 14),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 17, letterSpacing: 0, fontWeight: bold ? FontWeight.w600 : FontWeight.w500)),
              ),
              if (trailing != null)
                Text(trailing!, style: const TextStyle(fontSize: 14, letterSpacing: 0, fontWeight: FontWeight.w400)),
              if (selected) const Icon(Icons.check_rounded, size: 22),
            ],
          ),
        ),
      );
}

/// Slides the panel in from the right edge.
Widget slideFromRight(Animation<double> t, Widget child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: t, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic)),
      child: child,
    );

/// The panel on its own, over whatever app is on screen (the see-through QuickPanelActivity).
class QuickPanelApp extends StatefulWidget {
  const QuickPanelApp({super.key});

  @override
  State<QuickPanelApp> createState() => _QuickPanelAppState();
}

class _QuickPanelAppState extends State<QuickPanelApp> with SingleTickerProviderStateMixin {
  late final AnimationController _slide = AnimationController(vsync: this, duration: const Duration(milliseconds: 260))
    ..forward();
  final _panel = GlobalKey<QuickPanelState>();
  SharedPreferences? _prefs;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) setState(() => _prefs = prefs);
    });
    // The engine stays warm between opens: each open starts the panel fresh.
    QuickPanelChannel.onOpened = () async {
      _panel.currentState?.reset();
      _slide.forward(from: 0);
      // Home may have changed it since the last open.
      await _prefs?.reload();
      if (mounted) setState(() {});
    };
  }

  Future<void> _setBackground(String value) async {
    await _prefs?.setString(homeBackgroundKey, value);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    QuickPanelChannel.onOpened = null;
    _slide.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    await _slide.reverse();
    await QuickPanelChannel.close();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        color: Colors.transparent,
        builder: (context, child) => DevTag(child: child!),
        theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: Colors.transparent),
        home: Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              // The app behind stays in view, only very slightly dimmed.
              Positioned.fill(child: FadeTransition(opacity: _slide, child: const ColoredBox(color: Colors.black12))),
              slideFromRight(_slide, QuickPanel(
                  key: _panel,
                  blur: false,
                  background: _prefs?.getString(homeBackgroundKey) ?? 'video',
                  onBackground: _prefs == null ? null : _setBackground,
                  onClose: _close,
                )),
            ],
          ),
        ),
      );
}
