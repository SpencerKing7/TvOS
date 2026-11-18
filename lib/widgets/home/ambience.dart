/*
 * TvOS — a minimal home screen built on FLauncher / LTvLauncher.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// What the home screen tells the background: which app's colour to glow with,
/// and how far the user has scrolled into All Apps (0 = home rows, 1 = all apps).
class HomeAmbience extends ChangeNotifier {
  Color? _focusColor;
  Offset? _focusCenter;
  double _allApps = 0;
  String? _focusedPackage;

  Color? get focusColor => _focusColor;

  /// Screen position of the focused app's centre, where its glow radiates from.
  Offset? get focusCenter => _focusCenter;
  double get allApps => _allApps;

  final Map<String, Color?> _colorCache = {};

  /// Called when an app tile gains focus, with the artwork it is showing and where it is.
  Future<void> focus(String packageName, Uint8List artwork, Offset center) async {
    _focusedPackage = packageName;
    final color = _colorCache.containsKey(packageName)
        ? _colorCache[packageName]
        : _colorCache[packageName] = await _signatureColor(artwork);
    // Focus may have moved on (or the screen gone) while the colour was being worked out.
    if (_disposed || _focusedPackage != packageName || (color == _focusColor && center == _focusCenter)) return;
    _focusColor = color;
    _focusCenter = center;
    notifyListeners();
  }

  /// The focused app moved on screen (e.g. All Apps scrolled under it).
  void moveFocus(String packageName, Offset center) {
    if (_focusedPackage != packageName || center == _focusCenter) return;
    _focusCenter = center;
    notifyListeners();
  }

  bool _moving = false;

  /// An app is being moved: the move hint takes the bottom line, so the photo credit steps aside.
  bool get moving => _moving;

  set moving(bool value) {
    if (value == _moving) return;
    _moving = value;
    notifyListeners();
  }

  set allApps(double value) {
    final clamped = value.clamp(0.0, 1.0);
    if ((clamped - _allApps).abs() < 0.01) return;
    _allApps = clamped;
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

const Color _monochromeGlow = Color(0xFFB4BED6);

/// The app's brand colour: the most common saturated hue in a thumbnail of its banner,
/// ignoring near-white, near-black and grey pixels; silver for monochrome artwork.
Future<Color?> _signatureColor(Uint8List bytes) async {
  if (bytes.isEmpty) return null;
  try {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 32);
    final image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (data == null) return null;

    // Bucket by hue (12 buckets of 30°), weighting each pixel by its saturation.
    final weights = List<double>.filled(12, 0);
    final sums = List.generate(12, (_) => [0.0, 0.0, 0.0]);
    for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
      if (data.getUint8(i + 3) < 128) continue;
      final color = Color.fromARGB(255, data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
      final hsv = HSVColor.fromColor(color);
      if (hsv.saturation < 0.25 || hsv.value < 0.15) continue;
      final bucket = (hsv.hue / 30).floor() % 12;
      final weight = hsv.saturation * hsv.value;
      weights[bucket] += weight;
      sums[bucket][0] += color.red * weight;
      sums[bucket][1] += color.green * weight;
      sums[bucket][2] += color.blue * weight;
    }

    var best = 0;
    for (var b = 1; b < 12; b++) {
      if (weights[b] > weights[best]) best = b;
    }
    // Black-and-white artwork (Apple TV, FOX One) has no brand colour; a soft silver
    // glow still lifts it off the background. The threshold lets a small accent, like
    // YouTube's red button on white, count as the colour.
    if (weights[best] < 3) return _monochromeGlow;
    final w = weights[best];
    return Color.fromARGB(255, (sums[best][0] / w).round(), (sums[best][1] / w).round(), (sums[best][2] / w).round());
  } catch (_) {
    return null;
  }
}
