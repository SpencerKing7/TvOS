/*
 * TvOS — a minimal home screen built on FLauncher / LTvLauncher.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flauncher/widgets/home/ambience.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// A living background: soft colour fields that drift slowly and follow the time of day,
/// a wash of the focused app's colour, and a dark scrim so nothing busy sits behind the apps.
class AmbientBackground extends StatefulWidget {
  const AmbientBackground({super.key});

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground> with WidgetsBindingObserver {
  // ~15 fps is plenty for motion this slow, and keeps the TV's GPU mostly idle.
  static const _frame = Duration(milliseconds: 66);

  final ValueNotifier<double> _seconds = ValueNotifier(0);
  final Stopwatch _clock = Stopwatch()..start();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(_frame, (_) => _seconds.value = _clock.elapsedMilliseconds / 1000);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Nothing to animate while an app is in front or the TV is asleep.
    if (state == AppLifecycleState.resumed) {
      _start();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _seconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ambience = context.watch<HomeAmbience>();
    return RepaintBoundary(
      child: TweenAnimationBuilder<Color?>(
        // Glow colour eases from one app to the next instead of snapping...
        tween: ColorTween(end: ambience.focusColor ?? Colors.transparent),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOut,
        builder: (context, glow, _) => TweenAnimationBuilder<Offset?>(
          // ...and slides along with focus.
          tween: Tween<Offset?>(end: ambience.focusCenter),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          builder: (context, center, _) => CustomPaint(
            painter: _AmbientPainter(
              seconds: _seconds,
              glow: glow ?? Colors.transparent,
              glowCenter: center,
              allApps: ambience.allApps,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _AmbientPainter extends CustomPainter {
  final ValueNotifier<double> seconds;
  final Color glow;
  final Offset? glowCenter;
  final double allApps;

  _AmbientPainter({required this.seconds, required this.glow, required this.glowCenter, required this.allApps})
      : super(repaint: seconds);

  @override
  void paint(Canvas canvas, Size size) {
    final t = seconds.value;
    final palette = _Palette.at(DateTime.now());
    final rect = Offset.zero & size;

    canvas.drawRect(rect, Paint()..color = palette.base);

    // Three large, soft colour fields drifting on slow, different loops. They live in
    // the upper part of the screen, so the motion stays away from the app rows.
    final fields = [
      (palette.a, 0.30, 0.18, 97.0, 0.0),
      (palette.b, 0.72, 0.12, 131.0, 2.1),
      (palette.c, 0.50, 0.40, 163.0, 4.2),
    ];
    for (final (color, cx, cy, period, phase) in fields) {
      final angle = 2 * pi * t / period + phase;
      final center = Offset(
        size.width * (cx + 0.18 * sin(angle)),
        size.height * (cy + 0.10 * cos(angle * 0.8)),
      );
      final radius = size.width * 0.55;
      canvas.drawCircle(
        center,
        radius,
        Paint()..shader = ui.Gradient.radial(center, radius, [color.withOpacity(0.55), color.withOpacity(0)]),
      );
    }

    // Keep everything behind the app rows quiet: fade to dark from just above them.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, size.height * 0.30),
          Offset(0, size.height),
          [Colors.black.withOpacity(0), Colors.black.withOpacity(0.45), Colors.black.withOpacity(0.62)],
          [0, 0.45, 1],
        ),
    );

    // In All Apps the grid fills the screen, so dim the whole thing.
    if (allApps > 0) {
      canvas.drawRect(rect, Paint()..color = Colors.black.withOpacity(0.5 * allApps));
    }

    // The focused app's colour, radiating from behind it. Drawn over the dark wash so it
    // reads around the card; soft and wide so it frames the app rather than competing.
    final center = glowCenter;
    if (glow.alpha > 0 && center != null) {
      final radius = size.width * 0.38;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = ui.Gradient.radial(
            center,
            radius,
            [glow.withOpacity(0.42 * glow.opacity), glow.withOpacity(0.16 * glow.opacity), glow.withOpacity(0)],
            [0, 0.45, 1],
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_AmbientPainter old) =>
      old.glow != glow || old.glowCenter != glowCenter || old.allApps != allApps;
}

/// Colours for the time of day, blended smoothly between the keyframes below.
class _Palette {
  final Color base, a, b, c;

  const _Palette(this.base, this.a, this.b, this.c);

  // (hour, palette): muted and dark enough that white text and bright banners stay crisp.
  static const _keyframes = <(double, _Palette)>[
    (0, _night),
    (5, _night),
    (7, _Palette(Color(0xFF1A1226), Color(0xFF7A3B55), Color(0xFFA9604C), Color(0xFF3B2A5C))), // dawn
    (10, _Palette(Color(0xFF0B1E2E), Color(0xFF1F5F80), Color(0xFF2E7F86), Color(0xFF4A6A9A))), // morning
    (15, _Palette(Color(0xFF0C1C2B), Color(0xFF2A6A8A), Color(0xFF3C7A7A), Color(0xFF5A6F9E))), // afternoon
    (18, _Palette(Color(0xFF1A1028), Color(0xFF6E2E5A), Color(0xFFA8553F), Color(0xFF3C2C6E))), // dusk
    (20.5, _Palette(Color(0xFF0C0E22), Color(0xFF2B2660), Color(0xFF1E3E5E), Color(0xFF432A5A))), // evening
    (24, _night),
  ];

  static const _night = _Palette(Color(0xFF070B1A), Color(0xFF1B2350), Color(0xFF123A4A), Color(0xFF2A1F4F));

  static _Palette at(DateTime time) {
    final hour = time.hour + time.minute / 60;
    for (var i = 0; i < _keyframes.length - 1; i++) {
      final (h0, p0) = _keyframes[i];
      final (h1, p1) = _keyframes[i + 1];
      if (hour >= h0 && hour <= h1) {
        final f = (hour - h0) / (h1 - h0);
        return _Palette(
          Color.lerp(p0.base, p1.base, f)!,
          Color.lerp(p0.a, p1.a, f)!,
          Color.lerp(p0.b, p1.b, f)!,
          Color.lerp(p0.c, p1.c, f)!,
        );
      }
    }
    return _night;
  }
}
