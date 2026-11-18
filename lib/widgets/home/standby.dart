/*
 * TvOS — a minimal home screen built on FLauncher / LTvLauncher.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:flauncher/providers/now_playing_service.dart';
import 'package:flauncher/widgets/home/ambience.dart';
import 'package:flauncher/widgets/home/top_info.dart';

/// A calm screen "above" Home: after [idle] with no remote presses (or Up from the menu),
/// Home slides down out of view and only the background shows: the clock line stays at the
/// top, a touch smaller, and the song playing sits small in the bottom-left corner. The first press of any button
/// only brings Home back.
class Standby extends StatefulWidget {
  static const Duration idle = Duration(minutes: 10);
  static const Duration slide = Duration(milliseconds: 1100);

  final Widget child;

  const Standby({super.key, required this.child});

  /// Slides into standby now, from wherever [context] sits under it.
  static void enter(BuildContext context) => context.findAncestorStateOfType<StandbyState>()?.enter();

  @override
  State<Standby> createState() => StandbyState();
}

class StandbyState extends State<Standby> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _slide = AnimationController(vsync: this, duration: Standby.slide);
  late final Animation<double> _t = CurvedAnimation(parent: _slide, curve: Curves.easeInOutCubic);
  final FocusNode _standbyNode = FocusNode(debugLabel: 'standby');

  Timer? _idle;
  bool _standby = false;

  // The wake text shows for a while after entering, then fades away for good.
  static const _hintFor = Duration(seconds: 15);
  Timer? _hintTimer;
  bool _hintShort = false;

  // Where the remote was on Home, to put it back on waking.
  FocusNode? _returnTo;

  // The key that woke Home: its release (and repeats) still belong to standby, so holding
  // OK to wake can't also open the app under the focus.
  LogicalKeyboardKey? _wakeKey;

  bool get standby => _standby;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onAnyKey);
    // The background fades the focused app's glow as Home leaves.
    _t.addListener(() {
      if (mounted) context.read<HomeAmbience?>()?.standby = _t.value;
    });
    _restartIdle();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onAnyKey);
    _idle?.cancel();
    _hintTimer?.cancel();
    _slide.dispose();
    _standbyNode.dispose();
    super.dispose();
  }

  // The idle clock only runs while Home is on screen; an app in front owns the TV.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _restartIdle();
    } else {
      _idle?.cancel();
    }
  }

  // Watches every press to reset the idle clock; never consumes one.
  bool _onAnyKey(KeyEvent event) {
    if (!_standby) _restartIdle();
    return false;
  }

  void _restartIdle() {
    _idle?.cancel();
    _idle = Timer(Standby.idle, enter);
  }

  void enter() {
    if (!mounted || _standby) return;
    _idle?.cancel();
    _returnTo = FocusManager.instance.primaryFocus;
    _hintTimer?.cancel();
    _hintTimer = Timer(_hintFor, () {
      if (mounted) setState(() => _hintShort = true);
    });
    setState(() {
      _standby = true;
      _hintShort = false;
    });
    _standbyNode.requestFocus();
    _slide.forward();
  }

  void _wake() {
    if (!_standby) return;
    _hintTimer?.cancel();
    setState(() => _standby = false);
    _slide.reverse();
    final back = _returnTo;
    _returnTo = null;
    // Home lets focus in again only once it has rebuilt.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (back != null && back.context != null && back.canRequestFocus) {
        back.requestFocus();
      } else {
        FocusScope.of(context).nextFocus();
      }
    });
    _restartIdle();
  }

  KeyEventResult _onStandbyKey(FocusNode _, KeyEvent event) {
    if (event is KeyDownEvent && _wakeKey == null) {
      _wakeKey = event.logicalKey;
      return KeyEventResult.handled;
    }
    if (event is KeyUpEvent && event.logicalKey == _wakeKey) {
      _wakeKey = null;
      _wake();
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return Stack(
      // The whole screen, whatever size Home takes, so the corner always has its room.
      fit: StackFit.expand,
      children: [
        AnimatedBuilder(
          animation: _t,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, _t.value * height),
            child: Opacity(opacity: (1 - _t.value * 1.4).clamp(0.0, 1.0), child: child),
          ),
          // While in standby nothing on Home can take the remote.
          child: ExcludeFocus(excluding: _standby, child: widget.child),
        ),
        Positioned.fill(
          child: Focus(
            focusNode: _standbyNode,
            // Focusable at once (it takes focus in the same frame standby starts), but never
            // reached by moving around Home.
            skipTraversal: true,
            onKeyEvent: _onStandbyKey,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _t,
                // Not built at all while Home is fully up.
                builder: (context, _) => _t.value == 0
                    ? const SizedBox.shrink()
                    : Stack(
                        children: [
                          // The clock stays where Home had it (Home hides its own meanwhile).
                          Positioned(
                            left: 40,
                            top: 18,
                            // The whole line settles a touch smaller as Home slides away.
                            child: Transform.scale(
                              scale: 1 - 0.15 * _t.value,
                              alignment: Alignment.topLeft,
                              child: const TopInfo(),
                            ),
                          ),
                          // The song, small, fades in at the bottom once Home is mostly gone.
                          Positioned(
                            left: 40,
                            bottom: 24,
                            child: Opacity(
                              opacity: Curves.easeOut.transform(((_t.value - 0.45) / 0.55).clamp(0.0, 1.0)),
                              child: const _NowPlaying(),
                            ),
                          ),
                          // How to get back, quiet, where Home's "All Apps" hint sat (the photo
                          // credit keeps the bottom-right corner).
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 25,
                            child: Opacity(
                              opacity: Curves.easeOut.transform(((_t.value - 0.6) / 0.4).clamp(0.0, 1.0)),
                              child: Center(
                                child: AnimatedOpacity(
                                  opacity: _hintShort ? 0 : 1,
                                  duration: const Duration(milliseconds: 900),
                                  child: const Text(
                                    'Press any button to wake',
                                    style: TextStyle(
                                        color: Colors.white38, fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.4),
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
      ],
    );
  }
}

/// The song playing, small: square art, title and artist. Nothing when no music plays.
class _NowPlaying extends StatelessWidget {
  static const double artSize = 48;

  const _NowPlaying();

  @override
  Widget build(BuildContext context) {
    final track = context.watch<NowPlayingService>().playing;
    if (track == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: artSize,
          height: artSize,
          decoration: BoxDecoration(
            color: const Color(0xFF2A2A2E),
            borderRadius: BorderRadius.circular(6),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 12, offset: Offset(0, 3))],
          ),
          clipBehavior: Clip.antiAlias,
          child: track.art == null
              ? const Icon(Icons.music_note_rounded, color: Colors.white54, size: 22)
              : Image.memory(track.art!, fit: BoxFit.cover, gaplessPlayback: true, filterQuality: FilterQuality.medium),
        ),
        const SizedBox(width: 14),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(track.title,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w500, shadows: homeTextShadows)),
              if (track.artist.isNotEmpty)
                Text(track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: const TextStyle(color: Colors.white70, fontSize: 14, shadows: homeTextShadows)),
            ],
          ),
        ),
      ],
    );
  }
}
