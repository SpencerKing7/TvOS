/*
 * TvOS — a minimal home screen built on FLauncher / LTvLauncher.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// City-level coordinates for ZIP 78728 (north Austin). Only these go to Open-Meteo.
const double _latitude = 30.45;
const double _longitude = -97.68;
const Duration _weatherRefresh = Duration(minutes: 30);

/// Two shadows: a tight one for edge definition, a wide one to lift text off bright sky.
const homeTextShadows = [
  Shadow(color: Colors.black54, blurRadius: 3, offset: Offset(0, 1)),
  Shadow(color: Colors.black45, blurRadius: 18),
];

/// Time · date · weather on one quiet line at the top of Home.
class TopInfo extends StatefulWidget {
  const TopInfo({super.key});

  @override
  State<TopInfo> createState() => _TopInfoState();
}

class _TopInfoState extends State<TopInfo> with WidgetsBindingObserver {
  // The last forecast outlives any one TopInfo, so a rebuilt one starts with the weather line
  // already there (no jump when it arrives) and only fetches once it's stale.
  static _Weather? _cachedWeather;
  static DateTime? _cachedAt;

  DateTime _now = DateTime.now();
  _Weather? _weather = _cachedWeather;
  Timer? _clockTimer;
  Timer? _weatherTimer;
  DateTime? _lastFetch = _cachedAt;

  bool get _stale => _lastFetch == null || DateTime.now().difference(_lastFetch!) > _weatherRefresh;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleClock();
    if (_stale) _fetchWeather();
    _weatherTimer = Timer.periodic(_weatherRefresh, (_) => _fetchWeather());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    _weatherTimer?.cancel();
    super.dispose();
  }

  // Timers pause while the TV is asleep or an app is in front; catch up on return.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    setState(() => _now = DateTime.now());
    _scheduleClock();
    if (_stale) _fetchWeather();
  }

  /// Ticks exactly on each minute boundary.
  void _scheduleClock() {
    _clockTimer?.cancel();
    final now = DateTime.now();
    _clockTimer = Timer(Duration(seconds: 60 - now.second, milliseconds: -now.millisecond), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _scheduleClock();
    });
  }

  Future<void> _fetchWeather() async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '$_latitude',
      'longitude': '$_longitude',
      'current': 'temperature_2m,weather_code,is_day',
      'temperature_unit': 'fahrenheit',
      'timezone': 'auto',
    });
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final response = await (await client.getUrl(uri)).close().timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return;
      final json = jsonDecode(await response.transform(utf8.decoder).join()) as Map<String, dynamic>;
      final weather = _Weather.fromJson(json);
      _lastFetch = _cachedAt = DateTime.now();
      _cachedWeather = weather;
      if (mounted) setState(() => _weather = weather);
    } catch (e) {
      // Offline or the service is down: keep showing the last reading (or none).
      debugPrint('TopInfo weather fetch failed: $e');
    } finally {
      client.close();
    }
  }

  /// Apple's short date, used everywhere on Home: "Tue Nov 17".
  static String _date(DateTime now) => DateFormat('EEE MMM d').format(now);

  @override
  Widget build(BuildContext context) {
    final weather = _weather;
    const quiet = TextStyle(color: Colors.white70, fontSize: 20, fontWeight: FontWeight.w400, shadows: homeTextShadows);
    Widget dot() => Container(
          margin: const EdgeInsets.symmetric(horizontal: 14),
          width: 4,
          height: 4,
          decoration: const BoxDecoration(color: Colors.white38, shape: BoxShape.circle),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          DateFormat('h:mm').format(_now),
          // The same size as the date and weather: one even line, only brighter.
          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w400, shadows: homeTextShadows),
        ),
        dot(),
        Text(_date(_now), style: quiet),
        if (weather != null) ...[
          dot(),
          Icon(weather.icon, color: Colors.white70, size: 20, shadows: homeTextShadows),
          const SizedBox(width: 6),
          Text('${weather.temperature}°', style: quiet),
        ],
      ],
    );
  }
}

class _Weather {
  final int temperature;
  final IconData icon;

  const _Weather(this.temperature, this.icon);

  factory _Weather.fromJson(Map<String, dynamic> json) {
    final current = json['current'] as Map<String, dynamic>;
    return _Weather(
      (current['temperature_2m'] as num).round(),
      _iconFor((current['weather_code'] as num).toInt(), current['is_day'] == 1),
    );
  }

  /// WMO weather codes, as Open-Meteo reports them.
  static IconData _iconFor(int code, bool isDay) => switch (code) {
        0 || 1 => isDay ? Icons.wb_sunny_outlined : Icons.nightlight_outlined,
        2 => isDay ? Icons.wb_cloudy_outlined : Icons.nights_stay_outlined,
        3 => Icons.cloud_outlined,
        45 || 48 => Icons.foggy,
        >= 51 && <= 67 || >= 80 && <= 82 => Icons.water_drop_outlined,
        >= 71 && <= 77 || 85 || 86 => Icons.ac_unit,
        >= 95 => Icons.thunderstorm_outlined,
        _ => Icons.cloud_outlined,
      };
}
