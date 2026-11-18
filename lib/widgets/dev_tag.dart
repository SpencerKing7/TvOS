/*
 * TvOS — a minimal home screen built on FLauncher / LTvLauncher.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A small DEV tag at the top of every screen of the test builds (TvOS Dev runs beside the
/// real home), so the two are never mistaken for each other. Release builds show nothing.
class DevTag extends StatelessWidget {
  final Widget child;
  final bool show;

  const DevTag({super.key, required this.child, this.show = !kReleaseMode});

  @override
  Widget build(BuildContext context) {
    if (!show) return child;
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        child,
        // Top centre: the one spot clear of the clock, the gear and the content row.
        Positioned(
          top: 10,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xCCE65100),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'DEV',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
