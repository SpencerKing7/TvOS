/*
 * TvOS — a minimal home screen built on FLauncher / LTvLauncher.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

bool get videoLoopsAvailable => videoClips.isNotEmpty;

const _pexelsFiles = 'https://videos.pexels.com/video-files';

/// A Pexels clip at 1080p (Pexels licence: free to use, no credit required) and the
/// speed it plays at.
class VideoClip {
  final String file;
  final double speed;

  const VideoClip(this.file, [this.speed = _calm]);

  String get name => file.split('/').last;
}

// Speeds: slow enough that a clip reads as a still picture until you watch it. These clips
// are 24–30 fps, so 0.4 leaves ~10–12 new frames a second; for slow scenes (fog, haze,
// drifting cloud) each step is too small to see. Clips whose motion steps visibly at this
// speed belong out of the list, not a faster speed. Timelapses move fast, so go slower.
const _calm = 0.4;
const _timelapse = 0.35;

/// Played in this order, which rotates through themes (clouds, mountains, water, forest,
/// desert, light) so similar scenes never follow each other; every clip shows once
/// before any repeats.
const videoClips = [
  VideoClip('12428587/12428587-hd_1920_1080_30fps.mp4'), // water: sunrise over a misty river
  VideoClip('6341893/6341893-hd_1920_1080_25fps.mp4'), // mountains: clouds rolling over ridges
  VideoClip('10979134/10979134-hd_1920_1080_30fps.mp4'), // water: bare trees reflected at dusk
  VideoClip('13180793/13180793-hd_1920_1080_30fps.mp4'), // mountains: dense fog over green mountains
  VideoClip('12742754/12742754-hd_1920_1080_30fps.mp4'), // light: sun through mountain haze
  VideoClip('35763506/15162498_1920_1080_30fps.mp4'), // mountains: snowy peaks
  VideoClip('13260160/13260160-hd_1920_1080_24fps.mp4'), // water: lily pads on a still lake
  VideoClip('34470558/14606043_1920_1080_30fps.mp4'), // clouds: sunrise over a sea of clouds
  VideoClip('30770305/13162097_1920_1080_30fps.mp4'), // forest: misty rainforest from above
  VideoClip('31579321/13458108_1920_1080_30fps.mp4'), // mountains: fog over Yangmingshan
  VideoClip('33354461/14202812_1920_1080_30fps.mp4'), // light: mountain sunrise
  VideoClip('14067717/14067717-hd_1920_1080_30fps.mp4'), // water: mist on a lake below trees
  VideoClip('1722697/1722697-hd_1920_1080_25fps.mp4'), // light: mountain silhouettes
  VideoClip('28042235/12290181_1920_1080_30fps.mp4'), // clouds: over the clouds
  VideoClip('12858363/12858363-hd_1920_1080_30fps.mp4'), // mountains: fog and white clouds over peaks
  VideoClip('10550175/10550175-hd_1920_1080_30fps.mp4'), // forest: fog over a forest
  VideoClip('31640623/13480278_1920_1080_30fps.mp4'), // water: branches on a blue lake
  VideoClip('28042090/12290191_1920_1080_30fps.mp4'), // clouds: above a cloud-covered mountain
  VideoClip('6965877/6965877-hd_1920_1080_30fps.mp4'), // mountains: mist on a mountainside
  VideoClip('12228649/12228649-hd_1920_1080_30fps.mp4'), // forest: clouds over a forest
  VideoClip('3926075/3926075-hd_1920_1080_24fps.mp4', _timelapse), // light: sunrise timelapse over hills
  VideoClip('14081267/14081267-hd_1920_1080_30fps.mp4'), // water: mist rising off a pond
  VideoClip('13141644/13141644-hd_1920_1080_30fps.mp4'), // clouds: over a mountain
  VideoClip('14386778/14386778-hd_1920_1080_24fps.mp4'), // forest: fog among tall trees
  VideoClip('6527107/6527107-hd_1920_1080_25fps.mp4'), // mountains: moon setting over snowy peaks
  VideoClip('2915385/2915385-hd_1920_1080_25fps.mp4'), // water: open sea to the horizon
  VideoClip('6341892/6341892-hd_1920_1080_25fps.mp4'), // mountains: low cloud on a wooded mountain
  VideoClip('9244200/9244200-hd_1920_1080_30fps.mp4'), // light: sun setting behind a ridge
  VideoClip('34742448/14728553_1920_1080_24fps.mp4'), // water: river at sunset
  VideoClip('12995004/12995004-hd_1920_1080_30fps.mp4'), // forest: fog drifting through a wooded valley
  VideoClip('13280337/13280337-hd_1920_1080_30fps.mp4'), // clouds: sun over a sea of clouds
  VideoClip('28647793/12442332_1920_1080_30fps.mp4'), // water: misty forest river at dawn
  VideoClip('39847965/16998539_1920_1080_30fps.mp4', _timelapse), // desert: sunset timelapse
  VideoClip('10221670/10221670-hd_1920_1080_30fps.mp4'), // light: sunset rays over a treeline
  VideoClip('17207185/17207185-hd_1920_1080_24fps.mp4'), // desert: badlands
];

/// True once a clip is on screen, so the background can stop drawing what it covers.
final ValueNotifier<bool> videoShowing = ValueNotifier(false);

/// Calm clips, each played once at a slowed pace and dissolved into the next, so nothing
/// visibly loops. Paused whenever the launcher isn't on screen. Shows nothing (whatever
/// is beneath shows) until the first clip is ready.
class VideoLoops extends StatefulWidget {
  const VideoLoops({super.key});

  @override
  State<VideoLoops> createState() => _VideoLoopsState();
}

class _VideoLoopsState extends State<VideoLoops> with WidgetsBindingObserver {
  static const _crossfade = Duration(milliseconds: 1600);

  /// The next clip is opened (paused on its first frame) this long before the crossfade,
  /// so the fade itself never waits on opening a file.
  static const _prepareAhead = Duration(seconds: 4);

  VideoPlayerController? _current;
  VideoPlayerController? _incoming;
  bool _incomingVisible = false;
  int _index = 0;
  bool _preparing = false;
  bool _fading = false;
  Timer? _fallback;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Start somewhere different each time, then always continue in order.
    _index = DateTime.now().millisecondsSinceEpoch % videoClips.length;
    _start(_index);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fallback?.cancel();
    _current?.removeListener(_onTick);
    _current?.dispose();
    _incoming?.dispose();
    videoShowing.value = false;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Decoding video while an app is in front would cost the TV for nothing.
    if (state == AppLifecycleState.resumed) {
      _current?.play();
    } else {
      _current?.pause();
    }
  }

  bool get _onScreen => WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  /// How long each clip stays on screen (less if the footage runs out first).
  static const _showFor = Duration(seconds: 50);

  /// Where in its footage the current clip started (long clips start somewhere random).
  Duration _startedAt = Duration.zero;

  /// Real time left for the current clip, or null while its length is unknown (some
  /// Pexels files report 0 at first; never judge "nearly over" from that).
  Duration? _remaining() {
    final value = _current?.value;
    if (value == null || value.duration < const Duration(seconds: 3)) return null;
    if (value.position < _startedAt + const Duration(seconds: 1)) return null;
    final speed = videoClips[_index].speed;
    final footageLeft = (value.duration - value.position) * (1 / speed);
    final windowLeft = _showFor - (value.position - _startedAt) * (1 / speed);
    return footageLeft < windowLeft ? footageLeft : windowLeft;
  }

  void _onTick() {
    final remaining = _remaining();
    if (remaining == null || !_onScreen) return;
    if (!_preparing && remaining <= _prepareAhead + _crossfade) _prepareNext();
    if (!_fading && _incoming != null && (remaining <= _crossfade || _current!.value.isCompleted)) _crossfadeIn();
  }

  /// First clip: open it and show it straight away.
  Future<void> _start(int index) async {
    final (controller, i) = await _open(index);
    if (controller == null || !mounted) return controller?.dispose();
    await controller.play();
    _show(controller, i);
    setState(() => _current = controller);
    videoShowing.value = true;
  }

  /// Opens the following clip, paused on its first frame, ready to fade in.
  Future<void> _prepareNext() async {
    _preparing = true;
    final (controller, i) = await _open(_index + 1);
    if (controller == null || !mounted) {
      _preparing = false;
      return controller?.dispose();
    }
    setState(() => _incoming = controller); // joins the screen invisibly, attached before its fade
    _incomingIndex = i;
    // If the current clip ran out while this one was opening, go now.
    if ((_remaining() ?? Duration.zero) <= _crossfade) _crossfadeIn();
  }

  int _incomingIndex = 0;

  /// Plays the prepared clip and dissolves it in over the current one, with no gap.
  Future<void> _crossfadeIn() async {
    final next = _incoming;
    if (next == null || _fading) return;
    _fading = true;
    await next.play();
    // Don't start fading until the new clip is really producing pictures; a clip that
    // was opened partway in can take a moment, and fading in before then blends in a
    // black frame (a dark flash).
    await _untilPlaying(next);
    if (!mounted) return;
    setState(() => _incomingVisible = true);
    await Future.delayed(_crossfade);
    if (!mounted) return;

    final old = _current;
    old?.removeListener(_onTick);
    _show(next, _incomingIndex);
    setState(() {
      _current = next;
      _incoming = null;
      _incomingVisible = false;
    });
    await old?.dispose();
    _preparing = false;
    _fading = false;
  }

  /// Waits until [controller]'s position is moving and it isn't buffering (so frames are
  /// on screen), giving up after a few seconds rather than stalling the rotation.
  Future<void> _untilPlaying(VideoPlayerController controller) async {
    final start = controller.value.position;
    for (var waited = 0; waited < 2500; waited += 50) {
      final value = controller.value;
      if (!value.isBuffering && value.position > start + const Duration(milliseconds: 120)) return;
      await Future.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;
    }
  }

  /// Bookkeeping when [controller] becomes the clip on screen.
  void _show(VideoPlayerController controller, int i) {
    _index = i;
    _startedAt = controller.value.position;
    controller.addListener(_onTick);
    debugPrint('Video: playing ${videoClips[i].name} at ${videoClips[i].speed}x from ${_startedAt.inSeconds}s');
    // Files that never report a length still move on, shortly after their window.
    _fallback?.cancel();
    _fallback = Timer(_showFor + const Duration(seconds: 10), _forceNext);
    // Make sure the next clip is downloaded, then quietly fetch the rest.
    _fetch(videoClips[(i + 1) % videoClips.length]).then((_) => _fetchAllOnce());
  }

  void _forceNext() {
    if (!_onScreen) {
      _fallback = Timer(const Duration(seconds: 30), _forceNext);
      return;
    }
    if (_incoming != null) {
      _crossfadeIn();
    } else if (!_preparing) {
      _prepareNext().then((_) => _crossfadeIn());
    }
  }

  /// Opens clip [index] (or the next one that can be fetched and opened), muted and at
  /// its speed, paused on its first frame.
  Future<(VideoPlayerController?, int)> _open(int index) async {
    for (var attempt = 0; attempt < videoClips.length; attempt++) {
      final i = (index + attempt) % videoClips.length;
      final file = await _fetch(videoClips[i]);
      if (!mounted) return (null, i);
      if (file == null) continue;
      final controller = VideoPlayerController.file(file, videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
      try {
        await controller.initialize();
        await controller.setVolume(0);
        await controller.setPlaybackSpeed(videoClips[i].speed);
        // Long clips show a different stretch each time, not always the opening.
        final needed = _showFor * videoClips[i].speed + const Duration(seconds: 4);
        final spare = controller.value.duration - needed;
        if (spare > const Duration(seconds: 2)) {
          await controller.seekTo(spare * Random().nextDouble());
        }
        return (controller, i);
      } catch (e) {
        debugPrint('Video ${videoClips[i].name} failed to open: $e');
        await controller.dispose();
      }
    }
    return (null, index);
  }

  Widget _player(VideoPlayerController controller) => SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: controller.value.size.width,
            height: controller.value.size.height,
            child: VideoPlayer(controller),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final incoming = _incoming;
    if (current == null) return const SizedBox.shrink();
    // The next clip waits fully opaque *underneath*, and the current clip fades *out* on
    // top. Fading a video layer in from invisible makes this TV's GPU draw it fully
    // opaque for one frame (a visible pop); fading one out can't show that.
    // Each clip keeps one layer, keyed to its controller, so the hand-off rebuilds nothing.
    return Stack(
      fit: StackFit.expand,
      children: [
        // Same widget type as the current layer (always fully opaque here), so when this
        // clip becomes current its layer carries over untouched.
        if (incoming != null)
          AnimatedOpacity(
            key: ObjectKey(incoming),
            opacity: 1,
            duration: _crossfade,
            child: _player(incoming),
          ),
        AnimatedOpacity(
          key: ObjectKey(current),
          opacity: _incomingVisible ? 0 : 1,
          duration: _crossfade,
          curve: Curves.easeInOut,
          child: _player(current),
        ),
      ],
    );
  }
}

bool _fetchingAll = false;

/// Downloads every clip not yet on the TV, one at a time, and deletes cached clips that
/// are no longer in [videoClips]. Runs once per launch.
Future<void> _fetchAllOnce() async {
  if (_fetchingAll) return;
  _fetchingAll = true;
  final dir = Directory('${(await getApplicationSupportDirectory()).path}/videos');
  if (await dir.exists()) {
    final wanted = videoClips.map((clip) => clip.name).toSet();
    await for (final entry in dir.list()) {
      // A ".part" of a wanted clip may be a download in progress; leave it alone.
      final name = entry.uri.pathSegments.last.replaceFirst(RegExp(r'\.part$'), '');
      if (entry is File && !wanted.contains(name)) await entry.delete();
    }
  }
  for (final clip in videoClips) {
    await _fetch(clip);
  }
  debugPrint('Video: all ${videoClips.length} clips on the TV');
}

/// Downloads in progress, so the prefetch and the player never fetch the same clip twice.
final Map<String, Future<File?>> _inFlight = {};

/// The clip's file on the TV, downloading it from Pexels the first time.
// The cleanup block must not return the removed future: whenComplete waits on any
// future its callback returns, and this one is itself, so it would never complete.
Future<File?> _fetch(VideoClip clip) => _inFlight.putIfAbsent(clip.file, () => _download(clip).whenComplete(() {
      _inFlight.remove(clip.file);
    }));

Future<File?> _download(VideoClip clip) async {
  final dir = Directory('${(await getApplicationSupportDirectory()).path}/videos');
  await dir.create(recursive: true);
  final file = File('${dir.path}/${clip.name}');
  if (await file.exists()) return file;

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final response =
        await (await client.getUrl(Uri.parse('$_pexelsFiles/${clip.file}'))).close().timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      debugPrint('Video ${clip.name}: HTTP ${response.statusCode}');
      return null;
    }
    // Stream to a temporary name, then rename, so a half-finished file is never played.
    final partial = File('${file.path}.part');
    await response.pipe(partial.openWrite()).timeout(const Duration(minutes: 5));
    await partial.rename(file.path);
    return file;
  } catch (e) {
    debugPrint('Video ${clip.name} failed: $e');
    return null;
  } finally {
    client.close();
  }
}
