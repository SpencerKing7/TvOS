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
  Landscape('49.jpg', 'Piedras Rojas, Chile', 'Diego Delso'),
  Landscape('45.jpg', 'Cogne Valley, Italy', 'Dominicus Johannes Bergsma'),
  Landscape('43.jpg', 'Machapuchare, Nepal', 'Bijay Chaurasia'),
  Landscape('37.jpg', 'Teide, Tenerife', 'H. Zell'),
  Landscape('39.jpg', 'Lake Saiful Muluk, Pakistan', 'Muzaffar Bukhari'),
  Landscape('38.jpg', 'Karula, Estonia', 'Amadvr'),
  Landscape('28.jpg', 'Ahaggar, Algeria', 'Hamza-sia'),
  Landscape('23.jpg', 'Reynisfjara, Iceland', 'Diego Delso'),
  Landscape('10.jpg', 'Cirque de Gavarnie, France', 'Benh Lieu Song'),
  Landscape('25.jpg', 'Planken Wambuis, Netherlands', 'Agnes Monkelbaan'),
  Landscape('50.jpg', 'Balanced Rock, Utah', 'Thomas Wolf'),
  Landscape('15.jpg', 'Tatra Mountains, Poland', 'Radek Kucharski'),
  Landscape('40.jpg', 'Paczków, Poland', 'Jacek Halicki'),
  Landscape('05.jpg', 'Beinn Dorain, Scotland', 'Michal Klajban'),
  Landscape('14.jpg', 'Watzmann, Germany', 'Jörg Braukmann'),
  Landscape('29.jpg', 'Petrified Forest, Arizona', 'Finetooth'),
  Landscape('44.jpg', 'Mount Shasta, California', 'Frank Schulenburg'),
  Landscape('20.jpg', 'Yedigöller, Turkey', 'A.Savin'),
  Landscape('17.jpg', 'Komargorod, Ukraine', 'George Chernilevsky'),
  Landscape('51.jpg', 'Buckskin Gulch, Utah', 'John Fowler'),
  Landscape('41.jpg', 'Lac de Cap-de-Long, France', 'Tournasol7'),
  Landscape('48.jpg', 'Psebaisky Reserve, Russia', 'HoroshilovAleksandr'),
  Landscape('26.jpg', 'Zhangjiajie, China', 'Chensiyuan'),
  Landscape('24.jpg', 'Dülmen, Germany', 'Dietmar Rabich'),
  Landscape('18.jpg', 'Salar de Uyuni, Bolivia', 'Diego Delso'),
  Landscape('03.jpg', 'Austnesfjorden, Lofoten', 'Ximonic (Simo Räsänen)'),
  Landscape('22.jpg', 'Stuor Dáhtá, Sweden', 'Benoit Brummer'),
  Landscape('09.jpg', 'Dzukou Valley, India', 'Samudra Bikash Hazarika'),
  Landscape('42.jpg', "Sanderson's Hope, Greenland", 'Kim Hansen'),
  Landscape('52.jpg', 'Landscape Arch, Utah', 'Thomas Wolf'),
  Landscape('06.jpg', 'Flatirons, Colorado', 'Tyler Cipriani'),
  Landscape('36.jpg', 'Grose Valley, Australia', 'Diliff'),
  Landscape('33.jpg', 'Strymba, Ukraine', 'Ryzhkov Sergey'),
  Landscape('13.jpg', 'Lake Mystery, New Zealand', 'Michal Klajban'),
  Landscape('11.jpg', 'Scuol, Switzerland', 'Agnes Monkelbaan'),
  Landscape('27.jpg', 'Deadvlei, Namibia', 'Daniel Kraft'),
  Landscape('31.jpg', 'Mount Petros, Ukraine', 'Михайло Пецкович'),
  Landscape('46.jpg', 'Lake Clearwater, New Zealand', 'Michal Klajban'),
  Landscape('54.jpg', 'Langtang, Nepal', 'Q-lieb-in'),
  Landscape('35.jpg', 'Gyeongju, South Korea', 'Basile Morin'),
  Landscape('53.jpg', 'Mesa Arch, Utah', 'Thomas Wolf'),
  Landscape('34.jpg', 'Blyznytsia, Ukraine', 'Estolyarov'),
  Landscape('47.jpg', 'Kaikoura, New Zealand', 'Michal Klajban'),
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
