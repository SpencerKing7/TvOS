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
  Landscape('23.jpg', 'Reynisfjara, Iceland', 'Diego Delso'),
  Landscape('25.jpg', 'Planken Wambuis, Netherlands', 'Agnes Monkelbaan'),
  Landscape('17.jpg', 'Komargorod, Ukraine', 'George Chernilevsky'),
  Landscape('10.jpg', 'Cirque de Gavarnie, France', 'Benh Lieu Song'),
  Landscape('20.jpg', 'Yedigöller, Turkey', 'A.Savin'),
  Landscape('14.jpg', 'Watzmann, Germany', 'Jörg Braukmann'),
  Landscape('22.jpg', 'Stuor Dáhtá, Sweden', 'Benoit Brummer'),
  Landscape('24.jpg', 'Dülmen, Germany', 'Dietmar Rabich'),
  Landscape('05.jpg', 'Beinn Dorain, Scotland', 'Michal Klajban'),
  Landscape('26.jpg', 'Zhangjiajie, China', 'Chensiyuan'),
  Landscape('28.jpg', 'Ahaggar, Algeria', 'Hamza-sia'),
  Landscape('15.jpg', 'Tatra Mountains, Poland', 'Radek Kucharski'),
  Landscape('19.jpg', 'Étang de Thau, France', 'Christian Ferrer'),
  Landscape('29.jpg', 'Petrified Forest, Arizona', 'Finetooth'),
  Landscape('06.jpg', 'Flatirons, Colorado', 'Tyler Cipriani'),
  Landscape('33.jpg', 'Strymba, Ukraine', 'Ryzhkov Sergey'),
  Landscape('18.jpg', 'Salar de Uyuni, Bolivia', 'Diego Delso'),
  Landscape('09.jpg', 'Dzukou Valley, India', 'Samudra Bikash Hazarika'),
  Landscape('36.jpg', 'Grose Valley, Australia', 'Diliff'),
  Landscape('03.jpg', 'Austnesfjorden, Lofoten', 'Ximonic (Simo Räsänen)'),
  Landscape('35.jpg', 'Gyeongju, South Korea', 'Basile Morin'),
  Landscape('31.jpg', 'Mount Petros, Ukraine', 'Михайло Пецкович'),
  Landscape('11.jpg', 'Scuol, Switzerland', 'Agnes Monkelbaan'),
  Landscape('13.jpg', 'Lake Mystery, New Zealand', 'Michal Klajban'),
  Landscape('34.jpg', 'Blyznytsia, Ukraine', 'Estolyarov'),
  Landscape('27.jpg', 'Deadvlei, Namibia', 'Daniel Kraft'),
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
