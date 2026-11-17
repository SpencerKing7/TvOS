/*
 * TvOS — a minimal home screen built on FLauncher / LTvLauncher.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'dart:typed_data';

import 'package:flauncher/providers/now_playing_service.dart';
import 'package:flauncher/widgets/home/top_info.dart';
import 'package:flutter/material.dart';
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

/// The one space right of the time and weather: Now playing while music plays, otherwise
/// whatever happened last. Empty when there is nothing to show.
class HomeSlot extends StatelessWidget {
  static const double _minWidth = TrackCard.artSize + 18 + 80;

  const HomeSlot({super.key});

  @override
  Widget build(BuildContext context) {
    final music = context.watch<NowPlayingService>();
    final playing = music.playing;
    final Widget? card = pickSlot<Widget>(
      live: playing == null ? null : TrackCard(key: ValueKey('playing:${playing.key}'), track: playing, playing: true),
      recent: [
        (
          music.lastSongAt,
          music.lastSong == null ? null : TrackCard(key: ValueKey('last:${music.lastSong!.key}'), track: music.lastSong!, playing: false),
        ),
      ],
    );

    return LayoutBuilder(
      // Too narrow for the art and a few words: show nothing rather than a squashed card.
      builder: (context, constraints) => constraints.maxWidth < _minWidth
          ? const SizedBox.shrink()
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.centerLeft,
                children: [...previous, if (current != null) current],
              ),
              child: card ?? const SizedBox.shrink(key: ValueKey('empty')),
            ),
    );
  }
}

/// Album art beside the song and artist; dimmed once it is no longer playing.
class TrackCard extends StatelessWidget {
  static const double artSize = 88;

  final Track track;
  final bool playing;

  const TrackCard({super.key, required this.track, required this.playing});

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        opacity: playing ? 1 : 0.6,
        duration: const Duration(milliseconds: 600),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Art(track.art),
            const SizedBox(width: 18),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playing ? 'NOW PLAYING' : 'LAST PLAYED',
                      style: const TextStyle(
                          color: Colors.white60, fontSize: 12, letterSpacing: 1.4, fontWeight: FontWeight.w600, shadows: homeTextShadows),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w500, shadows: homeTextShadows),
                    ),
                    if (track.artist.isNotEmpty)
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 19, shadows: homeTextShadows),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class _Art extends StatelessWidget {
  final Uint8List? bytes;

  const _Art(this.bytes);

  @override
  Widget build(BuildContext context) => Container(
        width: TrackCard.artSize,
        height: TrackCard.artSize,
        decoration: BoxDecoration(
          color: const Color(0xFF2A2A2E),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 14, offset: Offset(0, 4))],
        ),
        clipBehavior: Clip.antiAlias,
        child: bytes == null
            ? const Icon(Icons.music_note_rounded, color: Colors.white54, size: 40)
            : Image.memory(
                bytes!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                // A broken image from an app is no worse than having none.
                errorBuilder: (_, __, ___) => const Icon(Icons.music_note_rounded, color: Colors.white54, size: 40),
              ),
      );
}
