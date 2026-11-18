# video_player_android 2.7.16, patched for TvOS

Copied from pub.dev (BSD licence, see LICENSE) with two changes, in
`android/src/main/java/io/flutter/plugins/videoplayer/VideoPlayer.java`: ExoPlayer gets a
`DefaultLoadControl` that buffers 2–6 s (at most 24 MB) instead of the default 50 s / ~128 MB.
The background clips are local files, and the default buffer held in the Java heap ran the
app out of memory on high-bitrate clips.

Tests and the example app were left out. To update: copy the new version over this folder and
reapply the change.

A second change in the same file: when Flutter destroys the video surface (the TV going to
sleep), the player is detached from it with `clearVideoSurface()` instead of being released
and rebuilt. Releasing a decoder whose surface is already gone never finishes on this TV.
`dispose()` and the surface callbacks also ignore calls after dispose.
