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

  @override
  String get key => '${playing ? 'playing' : 'last'}:${track.key}';
}

/// One thing to continue watching.
class SlotWatch extends SlotEntry {
  final WatchNextProgram program;

  const SlotWatch(this.program);

  @override
  String get key => 'watch:${program.id}:${program.posterArtUri}';
}

/// How many cards the slot stacks.
const int slotPlaces = 2;

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
    if (playing == null && last != null && lastAt != null) (lastAt, SlotTrack(last, playing: false)),
  ]..sort((a, b) => b.$1.compareTo(a.$1));
  return [
    if (playing != null) SlotTrack(playing, playing: true, progress: music.progress),
    for (final (_, entry) in recent) entry,
  ].take(slotPlaces).toList();
}

/// The space right of the time and weather: up to [slotPlaces] cards stacked. Empty when there
/// is nothing to show; it can be focused (Up from the top row), Up / Down move between the
/// cards, and OK opens the focused one.
class HomeSlot extends StatefulWidget {
  static const double _minWidth = WatchCard.posterWidth + 18 + 80;

  final List<SlotEntry> entries;

  /// Lay the playing song out large across the width, the rest small at the bottom right.
  final bool hero;
  final FocusNode? focusNode;
  final ValueChanged<SlotEntry>? onSelect;
  final VoidCallback? onDown;
  final VoidCallback? onRight;

  const HomeSlot(
      {super.key, required this.entries, this.hero = false, this.focusNode, this.onSelect, this.onDown, this.onRight});

  /// Whether [entries] lead with a song playing right now, the one case that takes the hero layout.
  static bool leadsWithMusic(List<SlotEntry> entries) =>
      entries.isNotEmpty && entries.first is SlotTrack && (entries.first as SlotTrack).playing;

  @override
  State<HomeSlot> createState() => _HomeSlotState();
}

class _HomeSlotState extends State<HomeSlot> {
  bool _focused = false;
  int _index = 0;

  int get _count => widget.entries.length;

  @override
  void didUpdateWidget(HomeSlot old) {
    super.didUpdateWidget(old);
    if (_index >= _count) _index = _count == 0 ? 0 : _count - 1;
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (AppCardKeys.validationKeys.contains(key)) {
      if (_index < _count) widget.onSelect?.call(widget.entries[_index]);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      if (_index < _count - 1) {
        setState(() => _index++);
      } else {
        widget.onDown?.call();
      }
    } else if (key == LogicalKeyboardKey.arrowUp) {
      // Up leads nowhere from the top card.
      if (_index > 0) setState(() => _index--);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      widget.onRight?.call();
    } else if (key != LogicalKeyboardKey.arrowLeft) {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // Beside the hero there is less room, so the side card's words stay narrow.
  Widget _sideCard(SlotEntry entry, bool focused) => switch (entry) {
        SlotTrack(:final track, :final playing, :final progress) => TrackCard(
            key: ValueKey(entry.key), track: track, playing: playing, progress: progress, focused: focused, textWidth: 206),
        SlotWatch(:final program) => WatchCard(key: ValueKey(entry.key), program: program, focused: focused, textWidth: 206),
      };

  Widget _card(SlotEntry entry, bool focused) => switch (entry) {
        SlotTrack(:final track, :final playing, :final progress) =>
          TrackCard(key: ValueKey(entry.key), track: track, playing: playing, progress: progress, focused: focused),
        SlotWatch(:final program) => WatchCard(key: ValueKey(entry.key), program: program, focused: focused),
      };

  Widget _place(int i, Widget Function(SlotEntry entry, bool focused) card) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 600),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.centerLeft,
          children: [...previous, if (current != null) current],
        ),
        child: i < widget.entries.length
            ? card(widget.entries[i], _focused && i == _index)
            : SizedBox.shrink(key: ValueKey('empty$i')),
      );

  Widget _stack() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Each place crossfades on its own, so music starting only changes what moves.
          for (var i = 0; i < slotPlaces; i++) ...[
            if (i > 0 && i < widget.entries.length) const SizedBox(height: 20),
            _place(i, _card),
          ],
        ],
      );

  /// The playing song large, then whatever else there is, small, after a hairline; all flowing left.
  Widget _heroLayout() {
    final top = widget.entries.first as SlotTrack;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(
          child: NowPlayingHero(
            key: ValueKey(top.key),
            track: top.track,
            progress: top.progress,
            focused: _focused && _index == 0,
          ),
        ),
        for (var i = 1; i < slotPlaces; i++)
          if (i < widget.entries.length) ...[
            const SizedBox(width: 28),
            const SlotDivider(height: NowPlayingHero.artSize * 0.75),
            const SizedBox(width: 28),
            _place(i, _sideCard),
          ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    final hero = widget.hero && HomeSlot.leadsWithMusic(entries);
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
                if (!focused) _index = 0;
              }),
              onKeyEvent: _onKey,
              child: hero ? _heroLayout() : _stack(),
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

/// Now playing as the main attraction: large art, title, artist and progress.
class NowPlayingHero extends StatelessWidget {
  static const double artSize = 120;

  final Track track;
  final TrackProgress? progress;
  final bool focused;

  const NowPlayingHero({super.key, required this.track, this.progress, this.focused = false});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedScale(
            scale: focused ? 1.04 : 1,
            duration: const Duration(milliseconds: 160),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: artSize,
              height: artSize,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: focused ? Colors.white : Colors.transparent, width: 2),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(focused ? 0.55 : 0.45), blurRadius: focused ? 30 : 24, offset: const Offset(0, 8)),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: track.art == null
                  ? const _Glyph(Icons.music_note_rounded)
                  : Image.memory(
                      track.art!,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (_, __, ___) => const _Glyph(Icons.music_note_rounded),
                    ),
            ),
          ),
          const SizedBox(width: 28),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'NOW PLAYING',
                    style: TextStyle(color: Colors.white60, fontSize: 13, letterSpacing: 2, fontWeight: FontWeight.w600, shadows: homeTextShadows),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w500, height: 1.15, shadows: homeTextShadows),
                  ),
                  if (track.artist.isNotEmpty)
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 20, shadows: homeTextShadows),
                    ),
                  if (progress != null) ...[
                    const SizedBox(height: 6),
                    TrackProgressBar(progress!, width: 300),
                  ],
                ],
              ),
            ),
          ),
        ],
      );
}

/// Album art beside the song and artist; dimmed once it is no longer playing.
class TrackCard extends StatelessWidget {
  static const double artSize = 88;

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
        dim: !playing,
        focused: focused,
        textWidth: textWidth,
      );
}

/// A thin bar with elapsed and total time, moved forward locally each second.
class TrackProgressBar extends StatefulWidget {
  static const double defaultWidth = 240;

  final TrackProgress progress;
  final double width;
  final DateTime Function() now;

  const TrackProgressBar(this.progress, {super.key, this.width = TrackProgressBar.defaultWidth, this.now = DateTime.now});

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text(_clock(at), style: style), Text(_clock(p.duration), style: style)],
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
      dim: false,
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
  final bool dim;
  final bool focused;
  final double textWidth;

  const _SlotCard({
    this.textWidth = 300,
    required this.image,
    required this.caption,
    required this.title,
    required this.subtitle,
    this.footer,
    required this.dim,
    required this.focused,
  });

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        opacity: dim && !focused ? 0.6 : 1,
        duration: const Duration(milliseconds: 400),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: focused ? 1.06 : 1,
              duration: const Duration(milliseconds: 160),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A2E),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: focused ? Colors.white : Colors.transparent, width: 2),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(focused ? 0.5 : 0.38), blurRadius: focused ? 20 : 14, offset: const Offset(0, 4)),
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
                    const SizedBox(height: 6),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w500, shadows: homeTextShadows),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 19, shadows: homeTextShadows),
                      ),
                    if (footer != null) footer!,
                  ],
                ),
              ),
            ),
          ],
        ),
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
