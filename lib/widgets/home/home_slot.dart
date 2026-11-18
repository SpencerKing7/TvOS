/*
 * TvOS — a minimal home screen built on FLauncher / LTvLauncher.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:collection/collection.dart';
import 'package:flauncher/models/watch_next_program.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/now_playing_service.dart';
import 'package:flauncher/providers/watch_next_service.dart';
import 'package:flauncher/widgets/app_card_keys.dart';
import 'package:flauncher/widgets/home/glide_text.dart';
import 'package:flauncher/widgets/home/top_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// One card the slot can show.
sealed class SlotEntry {
  const SlotEntry();

  /// Changes whenever the card should crossfade to a new one.
  String get key;
}

class SlotTrack extends SlotEntry {
  final Track track;
  final bool playing;
  final TrackProgress? progress;

  const SlotTrack(this.track, {required this.playing, this.progress});

  // Not keyed on [playing]: pausing changes the caption in place instead of crossfading the card.
  @override
  String get key => 'track:${track.key}';
}

/// One thing to continue watching.
class SlotWatch extends SlotEntry {
  final WatchNextProgram program;

  const SlotWatch(this.program);

  @override
  String get key => 'watch:${program.id}:${program.posterArtUri}';
}

/// How many cards the slot stacks, and the space between them.
const int slotPlaces = 2;
const double slotGap = 14;

// TvContract.WatchNextPrograms.WATCH_NEXT_TYPE_WATCHLIST: saved for later, not something left part-way.
const _watchlist = 3;

/// The Watch Next items worth continuing, newest first, at most [count]; only from [apps] when given.
List<WatchNextProgram> latestWatches(List<WatchNextProgram> programs, {Set<String>? apps, int count = slotPlaces}) =>
    (programs
            .where((p) =>
                p.title.isNotEmpty &&
                p.watchNextType != _watchlist &&
                watchedAt(p) != null &&
                (apps == null || apps.contains(p.packageName)))
            .toList()
          ..sort((a, b) => watchedAt(b)!.compareTo(watchedAt(a)!)))
        .take(count)
        .toList();

/// The most recent Watch Next item worth continuing, if any.
WatchNextProgram? latestWatch(List<WatchNextProgram> programs, {Set<String>? apps}) =>
    latestWatches(programs, apps: apps, count: 1).firstOrNull;

/// When [program] was last watched; Watch Next times arrive in seconds from some apps.
DateTime? watchedAt(WatchNextProgram program) {
  var at = program.lastEngagementTime;
  if (at <= 0) return null;
  if (at < 10000000000) at *= 1000;
  return DateTime.fromMillisecondsSinceEpoch(at);
}

/// What the slot stacks, top first, up to [slotPlaces] cards: Now playing while music plays,
/// then the most recent of the last song and the shows to continue (only from [apps], the
/// pinned ones, when given), newest first.
List<SlotEntry> currentSlot(NowPlayingService music, WatchNextService watch, {Set<String>? apps}) {
  final playing = music.playing;
  final watched = watch.hasPermission ? latestWatches(watch.programs, apps: apps) : const <WatchNextProgram>[];
  final last = music.lastSong;
  final lastAt = music.lastSongAt;
  final recent = <(DateTime, SlotEntry)>[
    for (final program in watched) (watchedAt(program)!, SlotWatch(program)),
    if (playing == null && last != null && lastAt != null)
      (lastAt, SlotTrack(last, playing: false, progress: music.pausedProgress)),
  ]..sort((a, b) => b.$1.compareTo(a.$1));
  return [
    if (playing != null) SlotTrack(playing, playing: true, progress: music.progress),
    for (final (_, entry) in recent) entry,
  ].take(slotPlaces).toList();
}

/// The big spot and the card beside it, under the clock line. It can be focused (Up from the
/// top row); Left / Right move along a song's player controls and between the cards, OK presses
/// the control or opens the card, and Down goes back to the apps.
class HomeSlot extends StatefulWidget {
  static const double _minWidth = WatchCard.posterWidth + 18 + 80;

  final List<SlotEntry> entries;

  final FocusNode? focusNode;
  final ValueChanged<SlotEntry>? onSelect;

  /// A player control pressed on the song in the big spot: `play`, `pause`, `next` or `previous`.
  final ValueChanged<String>? onControl;
  /// Down, with the screen x of what was focused, so the tile straight below it can take over.
  final ValueChanged<double>? onDown;
  final VoidCallback? onUp;

  const HomeSlot(
      {super.key, required this.entries, this.focusNode, this.onSelect, this.onControl, this.onDown, this.onUp});

  @override
  State<HomeSlot> createState() => HomeSlotState();
}

class HomeSlotState extends State<HomeSlot> {
  bool _focused = false;
  int _index = 0;

  // On the song in the first place, which player control the remote is on; -1 is the card
  // itself (OK opens the app). The row runs card → previous → play/pause → next → next card.
  int _control = -1;

  final _placeKeys = [for (var i = 0; i < slotPlaces; i++) GlobalKey()];

  /// Focuses the card nearest the screen position [x] (from a tile below), so Up lands on
  /// the card above where the remote was.
  void focusNearest(double x) {
    var best = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < _count && i < slotPlaces; i++) {
      final box = _placeKeys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final left = box.localToGlobal(Offset.zero).dx;
      final right = left + box.size.width;
      final distance = x < left ? left - x : (x > right ? x - right : 0.0);
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    setState(() {
      _index = best;
      _control = -1;
    });
    widget.focusNode?.requestFocus();
  }

  int get _count => widget.entries.length;

  /// A song playing, or paused with its progress still held: the ones the controls can act on.
  bool get _hasControls {
    final first = widget.entries.firstOrNull;
    return _index == 0 && first is SlotTrack && (first.playing || first.progress != null);
  }

  bool get _onControl => _hasControls && _control >= 0;

  final _controlsKey = GlobalKey();

  /// The screen x of the middle of what the remote is on: a control, or the card's art.
  double _focusedX() {
    if (_onControl) {
      final box = _controlsKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        return box.localToGlobal(Offset(PlayerControls.centerOf(_control), box.size.height / 2)).dx;
      }
    }
    final box = _placeKeys[_index.clamp(0, slotPlaces - 1)].currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return 0;
    final entry = widget.entries[_index];
    final artWidth = _index > 0
        ? WatchCard.posterWidth
        : (entry is SlotTrack ? HeroCard.height : HeroCard.height * 16 / 9);
    return box.localToGlobal(Offset(artWidth / 2, 0)).dx;
  }

  @override
  void didUpdateWidget(HomeSlot old) {
    super.didUpdateWidget(old);
    if (_index >= _count) _index = _count == 0 ? 0 : _count - 1;
  }

  void _press() {
    final first = widget.entries.first as SlotTrack;
    widget.onControl?.call(switch (PlayerControls.actions[_control]) {
      'playPause' => first.playing ? 'pause' : 'play',
      final action => action,
    });
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (AppCardKeys.validationKeys.contains(key)) {
      if (_onControl) {
        _press();
      } else if (_index < _count) {
        widget.onSelect?.call(widget.entries[_index]);
      }
    } else if (key == LogicalKeyboardKey.arrowRight) {
      // From the song's card along its controls, then on to the card beside; the row ends there.
      if (_hasControls && _control < PlayerControls.actions.length - 1) {
        setState(() => _control++);
      } else if (_index < _count - 1) {
        setState(() {
          _index++;
          _control = -1;
        });
      }
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      if (_hasControls && _control >= 0) {
        setState(() => _control--);
      } else if (_index > 0) {
        setState(() {
          _index--;
          // Back from the card beside lands on the nearest control, or the card if it has none.
          _control = PlayerControls.actions.length - 1;
        });
      }
    } else if (key == LogicalKeyboardKey.arrowDown) {
      widget.onDown?.call(_focusedX());
    } else if (key == LogicalKeyboardKey.arrowUp) {
      widget.onUp?.call();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // Beside the hero there is less room, so the side card's words stay narrow.
  Widget _sideCard(SlotEntry entry, bool focused) => switch (entry) {
        SlotTrack(:final track, :final playing, :final progress) => TrackCard(
            key: ValueKey(entry.key), track: track, playing: playing, progress: progress, focused: focused, textWidth: 180),
        SlotWatch(:final program) => WatchCard(key: ValueKey(entry.key), program: program, focused: focused, textWidth: 180),
      };

  Widget _place(int i, Widget Function(SlotEntry entry, bool focused) card) => KeyedSubtree(
        key: _placeKeys[i],
        child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 600),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        layoutBuilder: sizedToCurrent,
        child: i < widget.entries.length
            ? card(widget.entries[i], _focused && i == _index)
            : SizedBox.shrink(key: ValueKey('empty$i')),
        ),
      );

  /// The most current thing large, then the next, small, after a hairline; all flowing left.
  // Top-aligned, so both cards' art, captions and titles sit level; a song's bar hangs below.
  Widget _heroLayout() => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(child: _place(0, _heroCard)),
          for (var i = 1; i < slotPlaces; i++)
            if (i < widget.entries.length) ...[
              const SizedBox(width: 28),
              const SlotDivider(height: HeroCard.height),
              const SizedBox(width: 28),
              _place(i, _sideCard),
            ],
        ],
      );

  Widget _heroCard(SlotEntry entry, bool focused) => switch (entry) {
        SlotTrack(:final track, :final playing, :final progress) => HeroCard.track(
            key: ValueKey(entry.key),
            track: track,
            playing: playing,
            progress: progress,
            focused: focused,
            control: _control,
            controlsKey: _controlsKey),
        SlotWatch(:final program) => HeroCard.watch(key: ValueKey(entry.key), program: program, focused: focused),
      };

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    return LayoutBuilder(
      // Too narrow for the art and a few words: show nothing (and take no focus) rather than a squashed card.
      builder: (context, constraints) => constraints.maxWidth < HomeSlot._minWidth
          ? const SizedBox.shrink()
          : Focus(
              focusNode: widget.focusNode,
              canRequestFocus: entries.isNotEmpty,
              // Coming back into the slot always starts on the top card.
              onFocusChange: (focused) => setState(() {
                _focused = focused;
                if (!focused) {
                  _index = 0;
                  _control = -1;
                }
              }),
              onKeyEvent: _onKey,
              child: _heroLayout(),
            ),
    );
  }
}

/// The thin vertical rule between sections of the top half.
class SlotDivider extends StatelessWidget {
  final double height;

  const SlotDivider({super.key, required this.height});

  @override
  Widget build(BuildContext context) => Container(width: 1, height: height, color: Colors.white24);
}

/// The first card of the top half: art (square for music, 16:9 for a show), a
/// caption, the title, a second line, and progress.
class HeroCard extends StatelessWidget {
  // The same height as the card beside it, so the two sit level.
  static const double height = TrackCard.artSize;
  static const double textWidth = 260;

  /// A song's bar with its times row: the tallest footer.
  static const double footerHeight = 10 + 3 + 5 + 26;

  final Widget image;
  final double imageWidth;
  final String caption;
  final String title;
  final String subtitle;
  final Widget? footer;
  final bool focused;

  /// Whether the art shows the focus ring: not when a player control has the focus instead.
  final bool imageFocused;

  /// Changes when the art itself changes, so new art fades in rather than popping.
  final Object? imageKey;

  const HeroCard({
    super.key,
    this.imageFocused = true,
    this.imageKey,
    required this.image,
    required this.imageWidth,
    required this.caption,
    required this.title,
    required this.subtitle,
    this.footer,
    this.focused = false,
  });

  factory HeroCard.track(
          {Key? key,
          required Track track,
          required bool playing,
          TrackProgress? progress,
          bool focused = false,
          int? control,
          Key? controlsKey}) =>
      HeroCard(
        key: key,
        imageWidth: height,
        // With controls on screen the remote is on one of them, so only that one lights up.
        imageFocused: control == null || control < 0 || !(playing || progress != null),
        imageKey: track.art == null ? 'none' : identityHashCode(track.art),
        image: track.art == null
            ? const _Glyph(Icons.music_note_rounded)
            : Image.memory(
                track.art!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) => const _Glyph(Icons.music_note_rounded),
              ),
        // Paused (progress still known) keeps the bar where it stopped; only the caption changes.
        caption: playing ? 'NOW PLAYING' : (progress != null ? 'PAUSED' : 'LAST PLAYED'),
        title: track.title,
        subtitle: track.artist,
        footer: progress != null
            ? TrackProgressBar(
                progress,
                width: textWidth,
                center: focused && control != null ? PlayerControls(key: controlsKey, playing: playing, selected: control) : null,
              )
            : null,
        focused: focused,
      );

  factory HeroCard.watch({Key? key, required WatchNextProgram program, bool focused = false}) {
    final progress = program.safeProgress;
    final left = program.duration > 0 && program.playbackPosition > 0
        ? Duration(milliseconds: program.duration - program.playbackPosition)
        : null;
    return HeroCard(
      key: key,
      imageWidth: height * 16 / 9,
      image: _Poster(program),
      caption: 'CONTINUE WATCHING',
      title: program.title,
      subtitle: program.description,
      footer: progress > 0 ? WatchProgressBar(progress: progress, left: left) : null,
      focused: focused,
    );
  }

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedScale(
            scale: focused && imageFocused ? 1.06 : 1,
            duration: const Duration(milliseconds: 160),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: imageWidth,
              height: height,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2E),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(focused && imageFocused ? 0.5 : 0.38),
                      blurRadius: focused && imageFocused ? 20 : 14,
                      offset: const Offset(0, 4)),
                  // Focus is a soft white glow, as on the app tiles: no outline.
                  if (focused && imageFocused)
                    BoxShadow(color: Colors.white.withOpacity(0.28), blurRadius: 32, spreadRadius: 1),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                // The frame's size is fixed, so old and new art simply fill it.
                layoutBuilder: (current, previous) =>
                    Stack(fit: StackFit.expand, children: [...previous, if (current != null) current]),
                child: KeyedSubtree(key: ValueKey(imageKey), child: SizedBox.expand(child: image)),
              ),
            ),
          ),
          const SizedBox(width: 18),
          // A set width, whatever the title or whether a bar shows, so nothing beside it shifts;
          // it gives way only when a wide poster leaves less room.
          Flexible(
            child: SizedBox(
            width: textWidth,
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    caption,
                    style: const TextStyle(color: Colors.white60, fontSize: 12, letterSpacing: 1.4, fontWeight: FontWeight.w600, shadows: homeTextShadows),
                  ),
                  const SizedBox(height: 4),
                  GlideText(
                    title,
                    gliding: true,
                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w500, shadows: homeTextShadows),
                  ),
                  if (subtitle.isNotEmpty)
                    GlideText(
                      subtitle,
                      gliding: true,
                      style: const TextStyle(color: Colors.white70, fontSize: 17, shadows: homeTextShadows),
                    ),
                  // The bar's room is kept with or without a bar, so the card is always one
                  // height and the row can sit centred without moving when the bar comes or goes.
                  const SizedBox(height: 2),
                  SizedBox(height: footerHeight, child: footer),
                ],
              ),
            ),
          ),
        ],
      );
}

/// Previous, play or pause, next: shown under a song's bar while its card is focused.
class PlayerControls extends StatelessWidget {
  static const actions = ['previous', 'playPause', 'next'];

  final bool playing;

  /// Which of [actions] the remote is on.
  final int selected;

  const PlayerControls({super.key, required this.playing, required this.selected});

  static const double _button = 26;
  static const double _gap = 3;

  /// The x of control [i]'s middle, from the row's left edge.
  static double centerOf(int i) => _gap + i * (_button + 2 * _gap) + _button / 2;

  @override
  Widget build(BuildContext context) {
    final icons = [Icons.skip_previous_rounded, playing ? Icons.pause_rounded : Icons.play_arrow_rounded, Icons.skip_next_rounded];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < icons.length; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            margin: const EdgeInsets.symmetric(horizontal: _gap),
            width: _button,
            height: _button,
            decoration: BoxDecoration(color: i == selected ? Colors.white : Colors.transparent, shape: BoxShape.circle),
            child: Icon(icons[i], size: 20, color: i == selected ? Colors.black87 : Colors.white70),
          ),
      ],
    );
  }
}

/// How far into a show: the same thin bar as a song's, with the time left.
class WatchProgressBar extends StatelessWidget {
  final double progress;
  final Duration? left;

  const WatchProgressBar({super.key, required this.progress, this.left});

  static String _left(Duration d) {
    final m = (d.inSeconds / 60).ceil();
    return m >= 60 ? '${m ~/ 60} h ${m % 60} min left' : '$m min left';
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: HeroCard.textWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation(Colors.white),
              ),
            ),
            if (left != null) ...[
              const SizedBox(height: 5),
              Text(_left(left!),
                  style: const TextStyle(color: Colors.white60, fontSize: 13, shadows: homeTextShadows)),
            ],
          ],
        ),
      );
}

/// Album art beside the song and artist.
class TrackCard extends StatelessWidget {
  static const double artSize = 76;

  final Track track;
  final bool playing;
  final TrackProgress? progress;
  final bool focused;

  final double textWidth;

  const TrackCard(
      {super.key, required this.track, required this.playing, this.progress, this.focused = false, this.textWidth = 300});

  @override
  Widget build(BuildContext context) => _SlotCard(
        // The same 16:9 frame as a show's poster, so stacked cards line up: the square art in
        // the middle, a blurred, darkened copy of it filling the sides.
        image: SizedBox(
          width: WatchCard.posterWidth,
          height: artSize,
          child: track.art == null
              ? const _Glyph(Icons.music_note_rounded)
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      child: Image.memory(track.art!, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, __, ___) => const SizedBox()),
                    ),
                    const ColoredBox(color: Colors.black38),
                    Center(
                      child: SizedBox.square(
                        dimension: artSize,
                        child: Image.memory(
                          track.art!,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.medium,
                          // A broken image from an app is no worse than having none.
                          errorBuilder: (_, __, ___) => const _Glyph(Icons.music_note_rounded),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        caption: playing ? 'NOW PLAYING' : 'LAST PLAYED',
        title: track.title,
        subtitle: track.artist,
        footer: playing && progress != null ? TrackProgressBar(progress!) : null,
        focused: focused,
        textWidth: textWidth,
      );
}

/// A thin bar with elapsed and total time, moved forward locally each second.
class TrackProgressBar extends StatefulWidget {
  static const double defaultWidth = 240;

  final TrackProgress progress;
  final double width;

  /// Sits between the elapsed and total times: the player controls, while focused.
  final Widget? center;
  final DateTime Function() now;

  const TrackProgressBar(this.progress,
      {super.key, this.width = TrackProgressBar.defaultWidth, this.center, this.now = DateTime.now});

  @override
  State<TrackProgressBar> createState() => _TrackProgressBarState();
}

class _TrackProgressBarState extends State<TrackProgressBar> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  static String _clock(Duration d) {
    final s = d.inSeconds;
    final h = s ~/ 3600;
    final mm = (s % 3600 ~/ 60).toString();
    final ss = (s % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${mm.padLeft(2, '0')}:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.progress;
    final at = p.at(widget.now());
    final total = p.duration.inMilliseconds;
    const style = TextStyle(color: Colors.white60, fontSize: 13, fontFeatures: [FontFeature.tabularFigures()], shadows: homeTextShadows);
    return SizedBox(
      width: widget.width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : at.inMilliseconds / total,
              minHeight: 3,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
          const SizedBox(height: 5),
          // As tall as the controls whether or not they show, so focusing the card moves nothing.
          SizedBox(
            height: 26,
            child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_clock(at), style: style),
              if (widget.center != null) widget.center!,
              Text(_clock(p.duration), style: style),
            ],
          ),
          ),
        ],
      ),
    );
  }
}

/// A landscape poster (or the app's banner) with progress, beside the title.
class WatchCard extends StatelessWidget {
  static const double posterWidth = TrackCard.artSize * 16 / 9;

  final WatchNextProgram program;
  final bool focused;

  final double textWidth;

  const WatchCard({super.key, required this.program, this.focused = false, this.textWidth = 300});

  @override
  Widget build(BuildContext context) {
    final progress = program.safeProgress;
    return _SlotCard(
      image: SizedBox(
        width: posterWidth,
        height: TrackCard.artSize,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _Poster(program),
            if (progress > 0)
              Align(
                alignment: Alignment.bottomCenter,
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: Colors.black45,
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                ),
              ),
          ],
        ),
      ),
      caption: 'CONTINUE WATCHING',
      title: program.title,
      subtitle: program.description,
      focused: focused,
      textWidth: textWidth,
    );
  }
}

class _SlotCard extends StatelessWidget {
  final Widget image;
  final String caption;
  final String title;
  final String subtitle;
  final Widget? footer;
  final bool focused;
  final double textWidth;

  const _SlotCard({
    this.textWidth = 300,
    required this.image,
    required this.caption,
    required this.title,
    required this.subtitle,
    this.footer,
    required this.focused,
  });

  @override
  Widget build(BuildContext context) => Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedScale(
              scale: focused ? 1.06 : 1,
              duration: const Duration(milliseconds: 160),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2E),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(focused ? 0.5 : 0.38), blurRadius: focused ? 20 : 14, offset: const Offset(0, 4)),
                    // Focus is a soft white glow, as on the app tiles: no outline.
                    if (focused) BoxShadow(color: Colors.white.withOpacity(0.28), blurRadius: 32, spreadRadius: 1),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: image,
              ),
            ),
            const SizedBox(width: 18),
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: textWidth),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      caption,
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 12, letterSpacing: 1.4, fontWeight: FontWeight.w600, shadows: homeTextShadows),
                    ),
                    const SizedBox(height: 4),
                    GlideText(
                      title,
                      gliding: true,
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w500, shadows: homeTextShadows),
                    ),
                    if (subtitle.isNotEmpty)
                      GlideText(
                        subtitle,
                        gliding: true,
                        style: const TextStyle(color: Colors.white70, fontSize: 17, shadows: homeTextShadows),
                      ),
                    if (footer != null) footer!,
                  ],
                ),
              ),
            ),
          ],
      );
}

class _Glyph extends StatelessWidget {
  final IconData icon;

  const _Glyph(this.icon);

  @override
  Widget build(BuildContext context) => Center(child: Icon(icon, color: Colors.white54, size: 40));
}

/// The program's poster: from the web, from the app's content provider, or failing both the app's banner.
class _Poster extends StatefulWidget {
  final WatchNextProgram program;

  const _Poster(this.program);

  @override
  State<_Poster> createState() => _PosterState();
}

class _PosterState extends State<_Poster> {
  late Future<Uint8List?> _bytes;

  bool get _isWeb => widget.program.posterArtUri.startsWith('http');

  @override
  void initState() {
    super.initState();
    _bytes = _isWeb ? _banner() : _local();
  }

  Future<Uint8List?> _local() async {
    final uri = widget.program.posterArtUri;
    final poster = uri.isEmpty ? null : await context.read<WatchNextService>().loadPoster(uri);
    return poster ?? await _banner();
  }

  Future<Uint8List?> _banner() async {
    try {
      final bytes = await context.read<AppsService>().getAppBanner(widget.program.packageName);
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  Widget _memory(Uint8List? bytes) => bytes == null
      ? const _Glyph(Icons.play_arrow_rounded)
      : Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true, filterQuality: FilterQuality.medium);

  @override
  Widget build(BuildContext context) {
    final fallback = FutureBuilder<Uint8List?>(future: _bytes, builder: (_, snapshot) => _memory(snapshot.data));
    if (!_isWeb) return fallback;
    return Image.network(
      widget.program.posterArtUri,
      fit: BoxFit.cover,
      // Decoded at about twice the card size, not the poster's full size.
      cacheWidth: 320,
      filterQuality: FilterQuality.medium,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}

/// An AnimatedSwitcher layout that takes only the incoming child's size: the outgoing one fades
/// out on top without holding the old size open, so nothing around it shifts when the fade ends.
Widget sizedToCurrent(Widget? current, List<Widget> previous) => Stack(
      clipBehavior: Clip.none,
      children: [
        for (final child in previous) Positioned(left: 0, top: 0, child: child),
        if (current != null) current,
      ],
    );
