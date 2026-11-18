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
import 'package:flauncher/models/watch_next_program.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/now_playing_service.dart';
import 'package:flauncher/providers/watch_next_service.dart';
import 'package:flauncher/widgets/app_card_keys.dart';
import 'package:flauncher/widgets/home/top_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Picks what the shared slot shows: whatever is [live] right now wins; otherwise the most
/// recent of [recent] (each with when it last happened); otherwise nothing.
T? pickSlot<T extends Object>({T? live, Iterable<(DateTime?, T?)> recent = const []}) {
  if (live != null) return live;
  T? best;
  DateTime? bestAt;
  for (final (at, item) in recent) {
    if (item == null || at == null) continue;
    if (bestAt == null || at.isAfter(bestAt)) {
      best = item;
      bestAt = at;
    }
  }
  return best;
}

/// One thing the slot can show.
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

/// Up to [maxWatches] things to continue watching, newest first, stacked.
class SlotWatch extends SlotEntry {
  final List<WatchNextProgram> programs;

  const SlotWatch(this.programs);

  @override
  String get key => 'watch:${programs.map((p) => '${p.id}:${p.posterArtUri}').join(',')}';
}

const int maxWatches = 2;

// TvContract.WatchNextPrograms.WATCH_NEXT_TYPE_WATCHLIST: saved for later, not something left part-way.
const _watchlist = 3;

/// The Watch Next items worth continuing, newest first, at most [count]; only from [apps] when given.
List<WatchNextProgram> latestWatches(List<WatchNextProgram> programs, {Set<String>? apps, int count = maxWatches}) =>
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

/// What the slot shows now: Now playing while music plays, otherwise whichever happened last,
/// the last song or the last things watched (only from [apps], the pinned ones, when given).
SlotEntry? currentSlot(NowPlayingService music, WatchNextService watch, {Set<String>? apps}) {
  final playing = music.playing;
  final last = music.lastSong;
  final watched = watch.hasPermission ? latestWatches(watch.programs, apps: apps) : const <WatchNextProgram>[];
  return pickSlot<SlotEntry>(
    live: playing == null ? null : SlotTrack(playing, playing: true, progress: music.progress),
    recent: [
      (music.lastSongAt, last == null ? null : SlotTrack(last, playing: false)),
      (watched.isEmpty ? null : watchedAt(watched.first), watched.isEmpty ? null : SlotWatch(watched)),
    ],
  );
}

/// The one space right of the time and weather. Empty when there is nothing to show; it can
/// be focused (Up from the top row), Up / Down move between stacked cards, and OK opens the
/// focused one (its index goes to [onSelect]).
class HomeSlot extends StatefulWidget {
  static const double _minWidth = TrackCard.artSize + 18 + 80;

  final SlotEntry? entry;
  final FocusNode? focusNode;
  final ValueChanged<int>? onSelect;
  final VoidCallback? onDown;
  final VoidCallback? onRight;

  const HomeSlot({super.key, required this.entry, this.focusNode, this.onSelect, this.onDown, this.onRight});

  @override
  State<HomeSlot> createState() => _HomeSlotState();
}

class _HomeSlotState extends State<HomeSlot> {
  bool _focused = false;
  int _index = 0;

  int get _count => switch (widget.entry) { SlotWatch(:final programs) => programs.length, null => 0, _ => 1 };

  @override
  void didUpdateWidget(HomeSlot old) {
    super.didUpdateWidget(old);
    if (_index >= _count) _index = _count == 0 ? 0 : _count - 1;
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (AppCardKeys.validationKeys.contains(key)) {
      widget.onSelect?.call(_index);
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

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final Widget card = switch (entry) {
      null => const SizedBox.shrink(key: ValueKey('empty')),
      SlotTrack(:final track, :final playing, :final progress) =>
        TrackCard(key: ValueKey(entry.key), track: track, playing: playing, progress: progress, focused: _focused),
      SlotWatch(:final programs) => Column(
          key: ValueKey(entry.key),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < programs.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              WatchCard(program: programs[i], focused: _focused && i == _index),
            ],
          ],
        ),
    };

    return LayoutBuilder(
      // Too narrow for the art and a few words: show nothing (and take no focus) rather than a squashed card.
      builder: (context, constraints) => constraints.maxWidth < HomeSlot._minWidth
          ? const SizedBox.shrink()
          : Focus(
              focusNode: widget.focusNode,
              canRequestFocus: entry != null,
              // Coming back into the slot always starts on the top card.
              onFocusChange: (focused) => setState(() {
                _focused = focused;
                if (!focused) _index = 0;
              }),
              onKeyEvent: _onKey,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 600),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [...previous, if (current != null) current],
                ),
                child: card,
              ),
            ),
    );
  }
}

/// Album art beside the song and artist; dimmed once it is no longer playing.
class TrackCard extends StatelessWidget {
  static const double artSize = 88;

  final Track track;
  final bool playing;
  final TrackProgress? progress;
  final bool focused;

  const TrackCard({super.key, required this.track, required this.playing, this.progress, this.focused = false});

  @override
  Widget build(BuildContext context) => _SlotCard(
        image: SizedBox.square(
          dimension: artSize,
          child: track.art == null
              ? const _Glyph(Icons.music_note_rounded)
              : Image.memory(
                  track.art!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                  // A broken image from an app is no worse than having none.
                  errorBuilder: (_, __, ___) => const _Glyph(Icons.music_note_rounded),
                ),
        ),
        caption: playing ? 'NOW PLAYING' : 'LAST PLAYED',
        title: track.title,
        subtitle: track.artist,
        footer: playing && progress != null ? TrackProgressBar(progress!) : null,
        dim: !playing,
        focused: focused,
      );
}

/// A thin bar with elapsed and total time, moved forward locally each second.
class TrackProgressBar extends StatefulWidget {
  static const double width = 240;

  final TrackProgress progress;
  final DateTime Function() now;

  const TrackProgressBar(this.progress, {super.key, this.now = DateTime.now});

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
      width: TrackProgressBar.width,
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

  const WatchCard({super.key, required this.program, this.focused = false});

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

  const _SlotCard({
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
                constraints: const BoxConstraints(maxWidth: 300),
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
