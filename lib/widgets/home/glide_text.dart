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

/// One line of text that never ends in "…". When it doesn't fit, it fades out softly at the
/// right edge; while [gliding], it scrolls slowly to its end, rests, scrolls back, and repeats.
class GlideText extends StatefulWidget {
  /// Logical pixels a second: slow enough to read along.
  static const double speed = 32;
  static const Duration rest = Duration(milliseconds: 1600);
  static const double fade = 28;

  final String text;
  final TextStyle style;
  final bool gliding;

  const GlideText(this.text, {super.key, required this.style, this.gliding = false});

  @override
  State<GlideText> createState() => _GlideTextState();
}

class _GlideTextState extends State<GlideText> with SingleTickerProviderStateMixin {
  late final AnimationController _scroll;
  double _overflow = 0;
  int _run = 0;
  Timer? _wait;
  Completer<void>? _waiting;

  @override
  void initState() {
    super.initState();
    _scroll = AnimationController(vsync: this);
  }

  @override
  void didUpdateWidget(GlideText old) {
    super.didUpdateWidget(old);
    if (old.gliding != widget.gliding || old.text != widget.text) _restart();
  }

  @override
  void dispose() {
    _run++;
    _stopWaiting();
    _scroll.dispose();
    super.dispose();
  }

  void _stopWaiting() {
    _wait?.cancel();
    if (_waiting?.isCompleted == false) _waiting!.complete();
  }

  /// A rest that is cancelled with the widget, so no timer outlives it.
  Future<void> _rest() {
    _stopWaiting();
    final done = _waiting = Completer<void>();
    _wait = Timer(GlideText.rest, done.complete);
    return done.future;
  }

  void _restart() {
    final run = ++_run;
    _stopWaiting();
    _scroll.stop();
    _scroll.value = 0;
    if (widget.gliding && _overflow > 0) _glide(run);
  }

  Future<void> _glide(int run) async {
    final travel = Duration(milliseconds: (_overflow / GlideText.speed * 1000).round());
    while (mounted && run == _run) {
      await _rest();
      if (!mounted || run != _run) return;
      await _scroll.animateTo(1, duration: travel, curve: Curves.easeInOut).orCancel.catchError((_) {});
      if (!mounted || run != _run) return;
      await _rest();
      if (!mounted || run != _run) return;
      await _scroll.animateTo(0, duration: travel, curve: Curves.easeInOut).orCancel.catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final overflow = painter.width - constraints.maxWidth;
        final fits = overflow <= 0;
        final newOverflow = fits ? 0.0 : overflow + GlideText.fade;
        if (newOverflow != _overflow) {
          _overflow = newOverflow;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _restart();
          });
        }
        final line = Text(widget.text, style: widget.style, maxLines: 1, softWrap: false, overflow: TextOverflow.visible);
        if (fits) return line;

        return SizedBox(
          width: constraints.maxWidth,
          height: painter.height,
          child: AnimatedBuilder(
            animation: _scroll,
            builder: (context, child) {
              final shift = _scroll.value * _overflow;
              // Fade the right edge while more text lies past it; the left edge once some has scrolled off.
              final edge = GlideText.fade / constraints.maxWidth;
              return ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) => LinearGradient(
                  colors: [
                    shift > 0 ? Colors.transparent : Colors.white,
                    Colors.white,
                    Colors.white,
                    _scroll.value < 1 ? Colors.transparent : Colors.white,
                  ],
                  stops: [0, edge, 1 - edge, 1],
                ).createShader(rect),
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    maxWidth: double.infinity,
                    child: Transform.translate(offset: Offset(-shift, 0), child: child),
                  ),
                ),
              );
            },
            child: line,
          ),
        );
      });
}
