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

/// The always-on top of the home screen: time, date and the current temperature.
class TopInfo extends StatefulWidget {
  const TopInfo({super.key});

  @override
  State<TopInfo> createState() => _TopInfoState();
}

class _TopInfoState extends State<TopInfo> with WidgetsBindingObserver {
  DateTime _now = DateTime.now();
  _Weather? _weather;
  Timer? _clockTimer;
  Timer? _weatherTimer;
  DateTime? _lastFetch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleClock();
    _fetchWeather();
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
    if (_lastFetch == null || DateTime.now().difference(_lastFetch!) > _weatherRefresh) _fetchWeather();
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
      'daily': 'temperature_2m_max,temperature_2m_min',
      'temperature_unit': 'fahrenheit',
      'timezone': 'auto',
      'forecast_days': '1',
    });
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final response = await (await client.getUrl(uri)).close().timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return;
      final json = jsonDecode(await response.transform(utf8.decoder).join()) as Map<String, dynamic>;
      final weather = _Weather.fromJson(json);
      _lastFetch = DateTime.now();
      if (mounted) setState(() => _weather = weather);
    } catch (e) {
      // Offline or the service is down: keep showing the last reading (or none).
      debugPrint('TopInfo weather fetch failed: $e');
    } finally {
      client.close();
    }
  }

  /// Large time | hairline | date over weather, the right side matching the time's height.
  @override
  Widget build(BuildContext context) {
    final weather = _weather;
    return IntrinsicHeight(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            DateFormat('h:mm').format(_now),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 102,
              height: 1.0,
              fontWeight: FontWeight.w200,
              letterSpacing: -2,
              shadows: homeTextShadows,
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            width: 1,
            color: Colors.white24,
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('EEE d').format(_now),
                style: const TextStyle(color: Colors.white, fontSize: 31, fontWeight: FontWeight.w500, shadows: homeTextShadows),
              ),
              if (weather != null) _weatherLine(weather),
            ],
          ),
        ],
      ),
    );
  }

  Widget _weatherLine(_Weather weather) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(weather.icon, color: Colors.white, size: 29, shadows: homeTextShadows),
          const SizedBox(width: 8),
          Text(
            '${weather.temperature}°',
            style: const TextStyle(color: Colors.white, fontSize: 31, fontWeight: FontWeight.w400, shadows: homeTextShadows),
          ),
          const SizedBox(width: 12),
          // Today's high over today's low, split by a hairline.
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('H ${weather.high}°', style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.1, shadows: homeTextShadows)),
              Container(margin: const EdgeInsets.symmetric(vertical: 2), width: 36, height: 1, color: Colors.white24),
              Text('L ${weather.low}°', style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.1, shadows: homeTextShadows)),
            ],
          ),
        ],
      );
}

class _Weather {
  final int temperature;
  final int high;
  final int low;
  final IconData icon;

  const _Weather(this.temperature, this.high, this.low, this.icon);

  factory _Weather.fromJson(Map<String, dynamic> json) {
    final current = json['current'] as Map<String, dynamic>;
    final daily = json['daily'] as Map<String, dynamic>;
    return _Weather(
      (current['temperature_2m'] as num).round(),
      ((daily['temperature_2m_max'] as List).first as num).round(),
      ((daily['temperature_2m_min'] as List).first as num).round(),
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
