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
import 'dart:developer';
import 'dart:io';

import 'package:flauncher/flauncher_channel.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One song (or anything else a media session plays).
@immutable
class Track {
  final String packageName;
  final String title;
  final String artist;
  final String album;
  final Uint8List? art;

  const Track({required this.packageName, required this.title, this.artist = '', this.album = '', this.art});

  /// Same song from the same app, whatever its art.
  String get key => '$packageName\n$title\n$artist\n$album';

  Track withArt(Uint8List? art) => Track(packageName: packageName, title: title, artist: artist, album: album, art: art);

  static Track? fromEvent(Map<dynamic, dynamic> event) {
    final title = (event['title'] as String?)?.trim() ?? '';
    if (title.isEmpty) return null;
    final art = event['art'];
    return Track(
      packageName: event['packageName'] as String? ?? '',
      title: title,
      artist: event['artist'] as String? ?? '',
      album: event['album'] as String? ?? '',
      art: art is Uint8List && art.isNotEmpty ? art : null,
    );
  }
}

/// What is playing on the TV right now, and the last song heard, which outlives a restart.
class NowPlayingService extends ChangeNotifier {
  static const _prefsKey = 'now_playing_last';

  final SharedPreferences _prefs;
  final Future<Directory> Function() _storage;
  final DateTime Function() _now;
  StreamSubscription<dynamic>? _subscription;

  Track? _playing;
  Track? _lastSong;
  DateTime? _lastSongAt;

  NowPlayingService(FLauncherChannel channel, this._prefs,
      {Future<Directory> Function()? storage, DateTime Function()? now})
      : _storage = storage ?? getApplicationSupportDirectory,
        _now = now ?? DateTime.now {
    _restore();
    try {
      _subscription = channel.nowPlayingEvents().listen(
        (event) => onEvent(event is Map ? event : const {}),
        onError: (Object e) => log('Now playing stream failed', name: 'NowPlayingService', error: e),
      );
    } catch (e) {
      log('Failed to listen to now playing', name: 'NowPlayingService', error: e);
    }
  }

  /// The track playing at this moment, if any.
  Track? get playing => _playing;

  /// The most recent track that played, including the one playing now.
  Track? get lastSong => _lastSong;

  /// When [lastSong] was last heard: now while it plays, otherwise when it stopped.
  DateTime? get lastSongAt => _playing != null ? _now() : _lastSongAt;

  @visibleForTesting
  void onEvent(Map<dynamic, dynamic> event) {
    final track = Track.fromEvent(event);
    final isPlaying = track != null && event['playing'] == true;

    if (isPlaying) {
      final changed = _lastSong?.key != track.key;
      final artArrived = !changed && track.art != null && _lastSong?.art == null;
      // Keep the art already held for this song: some apps send it a moment after the title,
      // and the same bytes keep the image from being decoded again on every event.
      final withArt = !changed && _lastSong?.art != null ? track.withArt(_lastSong!.art) : track;
      _playing = withArt;
      _lastSong = withArt;
      _lastSongAt = _now();
      if (changed || artArrived) _save(withArt);
      notifyListeners();
      return;
    }

    if (_playing != null) {
      // Just paused or stopped: it becomes the last song, as of now.
      _playing = null;
      _lastSongAt = _now();
      if (_lastSong != null) _saveTime();
      notifyListeners();
    }
  }

  Future<File> _artFile() async => File('${(await _storage()).path}/now_playing/last-art');

  Future<void> _restore() async {
    final raw = _prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      Uint8List? art;
      try {
        final file = await _artFile();
        if (await file.exists()) art = await file.readAsBytes();
      } catch (_) {}
      // A live event may have arrived while the art loaded; it is newer.
      if (_lastSong != null) return;
      _lastSong = Track(
        packageName: json['packageName'] as String? ?? '',
        title: json['title'] as String? ?? '',
        artist: json['artist'] as String? ?? '',
        album: json['album'] as String? ?? '',
        art: art,
      );
      _lastSongAt = DateTime.fromMillisecondsSinceEpoch(json['at'] as int? ?? 0);
      if (_lastSong!.title.isEmpty) _lastSong = null;
      notifyListeners();
    } catch (e) {
      log('Could not restore the last song', name: 'NowPlayingService', error: e);
    }
  }

  Future<void> _saveTime() => _writePrefs(_lastSong!);

  Future<void> _save(Track track) async {
    await _writePrefs(track);
    try {
      final file = await _artFile();
      if (track.art == null) {
        if (await file.exists()) await file.delete();
      } else {
        await file.parent.create(recursive: true);
        await file.writeAsBytes(track.art!, flush: true);
      }
    } catch (e) {
      log('Could not save the last song art', name: 'NowPlayingService', error: e);
    }
  }

  Future<void> _writePrefs(Track track) => _prefs.setString(
      _prefsKey,
      jsonEncode({
        'packageName': track.packageName,
        'title': track.title,
        'artist': track.artist,
        'album': track.album,
        'at': (_lastSongAt ?? _now()).millisecondsSinceEpoch,
      }));

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
