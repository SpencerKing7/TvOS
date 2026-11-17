/*
 * TvOS — a minimal home screen built on FLauncher / LTvLauncher.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Keeps the TV's screensaver and sleep away while the home screen is showing, since the
/// home screen is its own ambient display. After [_idleLimit] with no remote presses it
/// lets go, so the TV's normal screensaver and sleep still happen overnight; any press
/// takes it back. Opening an app ends it automatically (the hold is per-window).
class KeepAwake extends StatefulWidget {
  final Widget child;

  const KeepAwake({super.key, required this.child});

  @override
  State<KeepAwake> createState() => _KeepAwakeState();
}

class _KeepAwakeState extends State<KeepAwake> {
  static const _idleLimit = Duration(hours: 2);
  static const _channel = MethodChannel('me.efesser.flauncher/method');

  Timer? _idle;
  bool _holding = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    _awake();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _idle?.cancel();
    _set(false);
    super.dispose();
  }

  // Only watches presses; never consumes them.
  bool _onKey(KeyEvent event) {
    _awake();
    return false;
  }

  void _awake() {
    _idle?.cancel();
    _idle = Timer(_idleLimit, () => _set(false));
    if (!_holding) _set(true);
  }

  void _set(bool on) {
    _holding = on;
    _channel.invokeMethod('setKeepScreenOn', on).catchError((Object e) => debugPrint('Keep awake failed: $e'));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
