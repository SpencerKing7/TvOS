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

import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/home/ambience.dart';
import 'package:flauncher/widgets/home/landscapes.dart';
import 'package:flauncher/widgets/home/video_loops.dart';
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

  // How long each landscape stays before crossfading to the next.
  static const _photoDuration = Duration(minutes: 3);

  final ValueNotifier<double> _seconds = ValueNotifier(0);
  final Stopwatch _clock = Stopwatch()..start();
  Timer? _timer;

  String _mode = 'gradient';
  _Slides? _slides;
  Timer? _rotateTimer;

  double get _now => _clock.elapsedMilliseconds / 1000;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(_frame, (_) => _seconds.value = _now);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final mode = context.watch<SettingsService>().homeBackground;
    if (mode == _mode) return;
    _mode = mode;
    if (mode == 'landscapes') {
      _startSlideshow();
    } else {
      _stopSlideshow();
    }
  }

  Future<void> _startSlideshow() async {
    _stopSlideshow();
    final slides = _Slides(index: Random().nextInt(landscapes.length));
    _slides = slides;
    final image = await loadLandscape(landscapes[slides.index]);
    if (!mounted || _slides != slides) return image?.dispose();
    if (image == null) {
      // Offline or turned away: show the gradient meanwhile and try again shortly.
      _rotateTimer = Timer(const Duration(seconds: 20), _startSlideshow);
      return;
    }
    setState(() => slides.show(image, _now));
    _rotateTimer = Timer.periodic(_photoDuration, (_) => _nextPhoto(slides));
  }

  /// Loads the next photo in the background, then crossfades to it. Photos that fail
  /// to download are skipped; the current one stays up meanwhile.
  Future<void> _nextPhoto(_Slides slides) async {
    for (var attempt = 0; attempt < landscapes.length; attempt++) {
      final index = (slides.index + 1 + attempt) % landscapes.length;
      final image = await loadLandscape(landscapes[index]);
      if (!mounted || _slides != slides) return image?.dispose();
      if (image == null) continue;
      setState(() {
        slides.index = index;
        slides.show(image, _now);
      });
      return;
    }
  }

  void _stopSlideshow() {
    _rotateTimer?.cancel();
    _slides?.dispose();
    _slides = null;
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
    _stopSlideshow();
    _seconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ambience = context.watch<HomeAmbience>();
    final slides = _slides;
    final video = _mode == 'video' && videoLoopsAvailable;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (!video)
          _painted(ambience, slides)
        else ...[
          // A still gradient shows until the first clip is ready; once a clip covers the
          // screen it isn't drawn at all (one less full-screen layer per video frame).
          ValueListenableBuilder<bool>(
            valueListenable: videoShowing,
            builder: (context, showing, _) =>
                showing ? const SizedBox.shrink() : _painted(ambience, null, layer: _Layer.base, animate: false),
          ),
          const VideoLoops(),
          _painted(ambience, null, layer: _Layer.overlays, animate: false),
        ],
        if (slides?.photo != null) _caption(landscapes[slides!.index], ambience.allApps, ambience.moving),
      ],
    );
  }

  /// Where the photo was taken and who took it (the licences require the photographer's
  /// name; the full licence for each is in assets/landscapes/CREDITS.md). Sized and placed
  /// to sit on the same line as the "All Apps" hint.
  Widget _caption(Landscape landscape, double allApps, bool moving) => Positioned(
        right: 56,
        bottom: 25,
        child: AnimatedOpacity(
          // Out of the way of All Apps, and of the move hint on the same line.
          opacity: allApps > 0.2 || moving ? 0 : 1,
          duration: const Duration(milliseconds: 300),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 800),
            // The background sits outside the Scaffold, so it has no text theme of its own.
            child: Material(
              key: ValueKey(landscape.file),
              type: MaterialType.transparency,
              child: Text(
                '${landscape.place}  ·  ${landscape.author}',
                style: const TextStyle(color: Colors.white38, fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.4),
              ),
            ),
          ),
        ),
      );

  Widget _painted(HomeAmbience ambience, _Slides? slides, {_Layer layer = _Layer.all, bool animate = true}) {
    return RepaintBoundary(
      child: TweenAnimationBuilder<Color?>(
        // Glow colour eases from one app to the next instead of snapping...
        tween: ColorTween(end: ambience.focusColor ?? Colors.transparent),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOut,
        builder: (context, glow, _) => TweenAnimationBuilder<Offset?>(
          // ...and slides along with focus.
          // (Before anything is focused there is no glow, so the centre doesn't matter.)
          tween: Tween<Offset?>(end: ambience.focusCenter ?? Offset.zero),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          builder: (context, center, _) => CustomPaint(
            painter: _AmbientPainter(
              seconds: animate ? _seconds : _still,
              glow: glow ?? Colors.transparent,
              glowCenter: center,
              allApps: ambience.allApps,
              slides: slides,
              layer: layer,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

/// Never ticks: for layers that don't animate (under and over a playing video).
final ValueNotifier<double> _still = ValueNotifier(0);

enum _Layer { all, base, overlays }

/// The landscape on screen and the one it is fading in over.
class _Slides {
  int index;
  ui.Image? photo;
  double shownAt = 0;
  ui.Image? previous;
  double previousShownAt = 0;

  _Slides({required this.index});

  void show(ui.Image? image, double now) {
    if (image == null) return;
    previous?.dispose();
    previous = photo;
    previousShownAt = shownAt;
    photo = image;
    shownAt = now;
  }

  void dispose() {
    photo?.dispose();
    previous?.dispose();
  }
}

class _AmbientPainter extends CustomPainter {
  static const _fadeSeconds = 2.5;
  static const _photoSeconds = 180.0;

  final ValueNotifier<double> seconds;
  final Color glow;
  final Offset? glowCenter;
  final double allApps;
  final _Slides? slides;
  final _Layer layer;

  _AmbientPainter({
    required this.seconds,
    required this.glow,
    required this.glowCenter,
    required this.allApps,
    required this.slides,
    required this.layer,
  }) : super(repaint: seconds);

  @override
  void paint(Canvas canvas, Size size) {
    final t = seconds.value;
    final photo = slides?.photo;

    if (layer != _Layer.overlays) {
      if (photo != null) {
        _paintLandscapes(canvas, size, t);
      } else {
        _paintGradient(canvas, size, t);
      }
    }
    // Over a video (overlays-only layer) treat it like a photo: heavier wash, no glow.
    if (layer != _Layer.base) _paintOverlays(canvas, size, darker: photo != null || layer == _Layer.overlays);
  }

  /// Photos fill the screen, slowly zooming and drifting (each one a different way),
  /// and crossfade into the next. Dimmed a little overall so they stay in the background.
  void _paintLandscapes(Canvas canvas, Size size, double t) {
    final s = slides!;
    final fade = ((t - s.shownAt) / _fadeSeconds).clamp(0.0, 1.0);
    if (s.previous != null && fade < 1) {
      _paintPhoto(canvas, size, s.previous!, t - s.previousShownAt, s.index - 1, 1);
    }
    _paintPhoto(canvas, size, s.photo!, t - s.shownAt, s.index, s.previous == null ? 1 : fade);
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black.withOpacity(0.18));
  }

  void _paintPhoto(Canvas canvas, Size size, ui.Image image, double age, int seed, double opacity) {
    final progress = (age / (_photoSeconds + _fadeSeconds)).clamp(0.0, 1.0);
    final zoom = 1.04 + 0.06 * progress;
    final direction = seed.isEven ? 1 : -1;

    // Crop the image to the screen's shape ("cover"), then narrow it for the zoom and pan.
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    final cover = applyBoxFit(BoxFit.cover, imageSize, size).source;
    final crop = Size(cover.width / zoom, cover.height / zoom);
    final pan = direction * (progress - 0.5) * (cover.width - crop.width);
    final source = Rect.fromCenter(
      center: Offset(imageSize.width / 2 + pan, imageSize.height / 2),
      width: crop.width,
      height: crop.height,
    );
    canvas.drawImageRect(
      image,
      source,
      Offset.zero & size,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Colors.white.withOpacity(opacity),
    );
  }

  void _paintGradient(Canvas canvas, Size size, double t) {
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
  }

  /// Shared by every background: the quiet zone behind the apps, the All Apps dim,
  /// and the focused app's glow on top.
  void _paintOverlays(Canvas canvas, Size size, {required bool darker}) {
    final rect = Offset.zero & size;

    // Keep everything behind the app rows quiet: fade to dark from just above them.
    // Photos have more detail than the gradient, so they get a heavier wash.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, size.height * 0.30),
          Offset(0, size.height),
          [
            Colors.black.withOpacity(0),
            Colors.black.withOpacity(darker ? 0.6 : 0.45),
            Colors.black.withOpacity(darker ? 0.75 : 0.62),
          ],
          [0, 0.45, 1],
        ),
    );

    // Photos and video can have bright sky right where the time and weather sit; a soft
    // dark pool behind that corner keeps them readable without a visible box.
    if (darker) {
      final corner = Offset(size.width * 0.18, size.height * 0.16);
      final radius = size.width * 0.42;
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.radial(
            corner,
            radius,
            [Colors.black.withOpacity(0.5), Colors.black.withOpacity(0.25), Colors.black.withOpacity(0)],
            [0, 0.5, 1],
          ),
      );
    }

    // In All Apps the grid fills the screen, so dim the whole thing.
    if (allApps > 0) {
      canvas.drawRect(rect, Paint()..color = Colors.black.withOpacity((darker ? 0.6 : 0.5) * allApps));
    }

    // The focused app's colour, radiating from behind it. Drawn over the dark wash so it
    // reads around the card; soft and wide so it frames the app rather than competing.
    // Not over photos: tinting a landscape muddies it.
    final center = glowCenter;
    if (!darker && glow.alpha > 0 && center != null) {
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

  // Slides change in place (same object, new photo), so a new painter always repaints;
  // the ticking clock repaints between those.
  @override
  bool shouldRepaint(_AmbientPainter old) => true;
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
