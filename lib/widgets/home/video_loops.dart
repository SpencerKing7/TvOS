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

/// A Pexels clip at 1080p and 60 fps (Pexels licence: free to use, no credit required) and
/// its length in seconds (ffprobe). Most Pexels files are fragmented MP4s with no index, so
/// the player can't tell how long they are (or seek in them): without this it never sees
/// the end coming, and the last frame sits frozen until the safety timer moves on.
class VideoClip {
  final String file;
  final double seconds;

  const VideoClip(this.file, this.seconds);

  Duration get length => Duration(milliseconds: (seconds * 1000).round());

  String get name => file.split('/').last;
}

// Clips play at 1×, so a 60 fps file puts a new frame on every refresh of a 60 Hz TV, the
// way the macOS Aerials do. Slowing them down only holds each frame for 2–3 refreshes
// (judder) without making the motion any smaller per frame. Calm comes from the footage:
// open landscapes and slow, steady camera glides.

/// Played in this order, which rotates through themes (mountains, water, desert, clouds,
/// forest, light) so similar scenes never follow each other, wrap-around included; every
/// clip shows once before any repeats.
const videoClips = [
  VideoClip('36758608/15578481_1920_1080_60fps.mp4', 45.8), // water: channels and islands at sunset
  VideoClip('33197843/14148120_1920_1080_60fps.mp4', 30.1), // mountains: Fitz Roy over glacial lakes
  VideoClip('28879134/12502452_1920_1080_60fps.mp4', 30.5), // desert: Monument Valley buttes at dawn
  VideoClip('19460532/19460532-hd_1920_1080_60fps.mp4', 87.6), // clouds: a sea of cloud over the land
  VideoClip('33330010/14192475_1920_1080_60fps.mp4', 38.2), // water: a turquoise fjord between cliffs
  VideoClip('31332724/13373828_1920_1080_60fps.mp4', 34.2), // light: sun rays over hazy ranges
  VideoClip('29415859/12666746_1920_1080_60fps.mp4', 31.3), // mountains: snowfields under a blue sky
  VideoClip('18757530/18757530-hd_1920_1080_60fps.mp4', 88.0), // forest: pine-covered mountainsides
  VideoClip('34493786/14615403_1920_1080_60fps.mp4', 22.0), // desert: Wilson Arch near Moab, Utah
  VideoClip('38361089/16290220_1920_1080_60fps.mp4', 38.0), // water: islands in a mountain lake
  VideoClip('30791936/13170365_1920_1080_60fps.mp4', 37.8), // desert: white sand dunes
  VideoClip('34505194/14619922_1920_1080_60fps.mp4', 26.6), // mountains: snowy ridges above a cloud sea
  VideoClip('14862547/14862547-hd_1920_1080_60fps.mp4', 53.2), // clouds: cloud flowing through peaks
  VideoClip('29477418/12689287_1920_1080_60fps.mp4', 45.5), // water: ice on a black-sand shore at sunset
  VideoClip('38520557/16358890_1920_1080_60fps.mp4', 46.8), // light: the sun over a golden cloud valley
  VideoClip('38903112/16542886_1920_1080_60fps.mp4', 35.7), // forest: woodland at sunrise
  VideoClip('28811521/12483473_1920_1080_60fps.mp4', 28.0), // water: a windswept lake below cliffs
  VideoClip('37943267/16100580_1920_1080_60fps.mp4', 26.9), // desert: a lone cone on a salt flat
  VideoClip('36432324/15448230_1920_1080_60fps.mp4', 24.8), // light: sunset over snowy Utah canyon country
  VideoClip('34293610/14530597_1920_1080_60fps.mp4', 43.7), // mountains: a green valley below snowy peaks
  VideoClip('30700901/13135908_1920_1080_60fps.mp4', 40.0), // clouds: cloud spilling over a ridge at dusk
  VideoClip('16461789/16461789-hd_1920_1080_60fps.mp4', 32.8), // water: sun setting over a lake
  VideoClip('28647791/12442287_1920_1080_60fps.mp4', 48.7), // light: mist over a river plain at dawn
  VideoClip('35742725/15150739_1920_1080_60fps.mp4', 13.6), // water: a river through striped sandstone, Utah
  VideoClip('30859401/13196587_1920_1080_60fps.mp4', 30.1), // mountains: a snow-dusted summit
  VideoClip('38688892/16434219_1920_1080_60fps.mp4', 53.0), // forest: a forested limestone peak
  VideoClip('35410029/15003059_1920_1080_60fps.mp4', 31.5), // water: a braided river below snowy peaks
  VideoClip('36143048/15327633_1920_1080_60fps.mp4', 23.9), // clouds: cloud on the Wasatch, Utah
  VideoClip('36460250/15460732_1920_1080_60fps.mp4', 34.3), // desert: red cliffs under a blue sky
  VideoClip('31985994/13630845_1920_1080_60fps.mp4', 30.0), // clouds: the sun above a cloud sea
  VideoClip('29057836/12560425_1920_1080_60fps.mp4', 25.6), // water: mist on a still lake at sunrise
  VideoClip('33285408/14178165_1920_1080_60fps.mp4', 30.4), // mountains: Fitz Roy above a frozen lake
  VideoClip('17374934/17374934-hd_1920_1080_60fps.mp4', 37.2), // light: sunset clouds over a lake
];

/// True once a clip is on screen, so the background can stop drawing what it covers.
final ValueNotifier<bool> videoShowing = ValueNotifier(false);

/// Calm clips, each played once and dissolved into the next, so nothing
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

  // The player position can't be trusted (see [_played]), so clips are timed on a clock.
  Timer? _ticker;

  // Bumped whenever the players are let go; work started before then drops what it opens.
  int _run = 0;
  bool _stale(int run) => !mounted || run != _run;

  // The first clip fades in from black (a black cover fades off it, see [build]).
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Start somewhere different each time, then always continue in order.
    _index = DateTime.now().millisecondsSinceEpoch % videoClips.length;
    _start(_index);
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _onTick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fallback?.cancel();
    _ticker?.cancel();
    _current?.dispose();
    _incoming?.dispose();
    videoShowing.value = false;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (_current == null) {
          _run++;
          _start(_index + 1);
        } else {
          _current!.play();
          _played.start();
        }
      case AppLifecycleState.inactive:
        _current?.pause();
        _played.stop();
      // Home is off screen (an app in front, or the TV asleep): let the players go. Kept,
      // they hold decoders and memory, and the plugin rebuilds every one of them when the
      // screen comes back, restarting each clip. Home starts the next clip fresh instead.
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _release();
    }
  }

  void _release() {
    if (_current == null && _incoming == null) return;
    _run++;
    _fallback?.cancel();
    _played.stop();
    final gone = [_current, _incoming];
    _current = null;
    _incoming = null;
    _incomingVisible = false;
    _preparing = false;
    _fading = false;
    _revealed = false;
    videoShowing.value = false;
    if (mounted) setState(() {});
    for (final controller in gone) {
      controller?.dispose();
    }
  }

  bool get _onScreen => WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  /// How long each clip stays on screen (less if the footage runs out first).
  static const _showFor = Duration(seconds: 50);

  /// Where in its footage the current clip started (long clips start somewhere random).
  Duration _startedAt = Duration.zero;

  /// Whether the player knows clip [i]'s real length, and so can seek in it. Fragmented
  /// files report only their first fragment (a few seconds) and can't seek.
  static bool _seekable(VideoPlayerController controller, int i) =>
      (controller.value.duration - videoClips[i].length).abs() < const Duration(seconds: 1);

  /// How long the current clip has been on screen and playing. The player's own position
  /// can't be trusted: in a fragmented file it stops at the end of the first fragment while
  /// the picture plays on.
  Stopwatch _played = Stopwatch();

  /// Time left for the current clip.
  Duration? _remaining() {
    if (_current == null) return null;
    final footageLeft = videoClips[_index].length - _startedAt - _played.elapsed;
    final windowLeft = _showFor - _played.elapsed;
    return footageLeft < windowLeft ? footageLeft : windowLeft;
  }

  void _onTick() {
    final remaining = _remaining();
    if (remaining == null || !_onScreen) return;
    if (!_preparing && remaining <= _prepareAhead + _crossfade) _prepareNext();
    if (!_fading && _incoming != null && remaining <= _crossfade) _crossfadeIn();
  }

  /// First clip: open it and show it straight away.
  Future<void> _start(int index) async {
    final run = _run;
    final (controller, i) = await _open(index);
    if (controller == null || _stale(run)) return controller?.dispose();
    final from = controller.value.position;
    await controller.play();
    if (_stale(run)) return controller.dispose();
    _show(controller, i, from, Stopwatch()..start());
    setState(() => _current = controller);
    videoShowing.value = true;
    // Uncover it once it's really producing pictures.
    await _untilPlaying(controller);
    if (!_stale(run)) setState(() => _revealed = true);
  }

  /// Opens the following clip, paused on its first frame, ready to fade in.
  Future<void> _prepareNext() async {
    _preparing = true;
    final run = _run;
    final (controller, i) = await _open(_index + 1);
    if (controller == null || _stale(run)) {
      if (!_stale(run)) _preparing = false;
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
    final run = _run;
    // Timed from here: by the time the fade ends, a fragmented file's position may be stuck.
    final from = next.value.position;
    final clock = Stopwatch()..start();
    await next.play();
    // Don't start fading until the new clip is really producing pictures; a clip that
    // was opened partway in can take a moment, and fading in before then blends in a
    // black frame (a dark flash).
    await _untilPlaying(next);
    if (_stale(run)) return;
    setState(() => _incomingVisible = true);
    await Future.delayed(_crossfade);
    if (_stale(run)) return;

    final old = _current;
    _show(next, _incomingIndex, from, clock);
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
  void _show(VideoPlayerController controller, int i, Duration from, Stopwatch clock) {
    _index = i;
    _startedAt = from;
    _played = clock;
    debugPrint('Video: playing ${videoClips[i].name} from ${_startedAt.inSeconds}s');
    // Whatever happens to the player, the rotation moves on shortly after this clip should.
    final left = videoClips[i].length - _startedAt - clock.elapsed;
    _fallback?.cancel();
    _fallback = Timer((left < _showFor ? left : _showFor) + const Duration(seconds: 3), _forceNext);
    // Make sure the next clip is downloaded, then quietly fetch the rest.
    _fetch(videoClips[(i + 1) % videoClips.length]).then((_) => _fetchAllOnce());
  }

  void _forceNext() {
    if (_current == null) return;
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

  /// Opens clip [index] (or the next one that can be fetched and opened), muted, paused on
  /// its first frame.
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
        // Long clips show a different stretch each time, not always the opening (only where
        // the file lets the player seek; the rest always start at the top).
        final spare = videoClips[i].length - _showFor - const Duration(seconds: 4);
        if (spare > const Duration(seconds: 2) && _seekable(controller, i)) {
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
        // Black over the first clip until it's moving, then fading off it (the same
        // fade-out-on-top rule as above, so nothing pops).
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: _revealed ? 0 : 1,
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOut,
            child: const ColoredBox(color: Colors.black),
          ),
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
Future<File?> _fetch(VideoClip clip) => _inFlight.putIfAbsent(
    clip.file,
    () => _download(clip).whenComplete(() {
          _inFlight.remove(clip.file);
        }));

Future<File?> _download(VideoClip clip) async {
  final dir = Directory('${(await getApplicationSupportDirectory()).path}/videos');
  await dir.create(recursive: true);
  final file = File('${dir.path}/${clip.name}');
  if (await file.exists()) return file;

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final response = await (await client.getUrl(Uri.parse('$_pexelsFiles/${clip.file}')))
        .close()
        .timeout(const Duration(seconds: 30));
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
