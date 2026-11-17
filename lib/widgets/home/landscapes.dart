/*
 * TvOS — a minimal home screen built on FLauncher / LTvLauncher.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A landscape photo bundled in assets/landscapes/, from Wikimedia Commons' Featured
/// Pictures at 1920px. Each licence requires its credit on screen while it shows;
/// assets/landscapes/CREDITS.md lists the source pages.
class Landscape {
  final String file;
  final String place;
  final String author;

  const Landscape(this.file, this.place, this.author);
}

const landscapes = [
  Landscape('05.jpg', 'Beinn Dorain, Scotland', 'Michal Klajban'),
  Landscape('06.jpg', 'Flatirons, Colorado', 'Tyler Cipriani'),
];

/// Decodes a bundled landscape. Null if it can't be read, so the slideshow skips it.
Future<ui.Image?> loadLandscape(Landscape landscape) async {
  try {
    final data = await rootBundle.load('assets/landscapes/${landscape.file}');
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: 1920);
    return (await codec.getNextFrame()).image;
  } catch (e) {
    debugPrint('Landscape ${landscape.place} failed: $e');
    return null;
  }
}
