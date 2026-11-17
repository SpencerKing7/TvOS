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

/// Shown in this order (from a random start), so similar scenes never follow each other.
const landscapes = [
  Landscape('01.jpg', 'Lake Louise, Canada', 'Chensiyuan'),
  Landscape('07.jpg', 'Dune du Pilat, France', 'Jörg Braukmann'),
  Landscape('03.jpg', 'Austnesfjorden, Lofoten', 'Ximonic (Simo Räsänen)'),
  Landscape('09.jpg', 'Dzukou Valley, India', 'Samudra Bikash Hazarika'),
  Landscape('04.jpg', 'Ai-Petri, Crimea', 'Dmytro Balkhovitin'),
  Landscape('08.jpg', 'Mekong, Laos', 'Basile Morin'),
  Landscape('05.jpg', 'Beinn Dorain, Scotland', 'Michal Klajban'),
  Landscape('02.jpg', 'Mount Shasta from Lake Siskiyou', 'Radomianin'),
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
