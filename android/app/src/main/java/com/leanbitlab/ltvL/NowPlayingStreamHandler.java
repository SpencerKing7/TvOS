/*
 * TvOS — a minimal home screen built on FLauncher / LTvLauncher.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

package com.leanbitlab.ltvL;

import android.content.ComponentName;
import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.media.MediaMetadata;
import android.media.session.MediaController;
import android.media.session.MediaSessionManager;
import android.media.session.PlaybackState;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.plugin.common.EventChannel;

/**
 * Streams what any app is playing (its media session) to Dart: title, artist, album, art and
 * whether it is playing. Sends an empty map when nothing has a session.
 *
 * Reading other apps' sessions needs notification access for {@link LauncherNotificationListenerService}.
 * Until that is granted this sends nothing, and it retries whenever the listener service connects.
 */
class NowPlayingStreamHandler implements EventChannel.StreamHandler {
    private static final String TAG = "NowPlaying";
    // Twice the card's size on a 2x screen; keeps each event to a few tens of KB.
    private static final int ART_MAX_PX = 320;

    private final Context context;
    private final ComponentName listenerComponent;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService artExecutor = Executors.newSingleThreadExecutor();

    private EventChannel.EventSink sink;
    private MediaSessionManager sessionManager;
    private boolean sessionsListening = false;
    private final List<MediaController> controllers = new ArrayList<>();
    private final Map<MediaController, MediaController.Callback> callbacks = new HashMap<>();

    private String lastTrackKey;
    private byte[] lastArt;
    private String lastSentKey;
    private int generation = 0;

    private final MediaSessionManager.OnActiveSessionsChangedListener sessionsChanged = this::setControllers;
    private final LauncherNotificationListenerService.NotificationListener listenerChanged =
            () -> main.post(this::attach);

    NowPlayingStreamHandler(Context context) {
        this.context = context;
        this.listenerComponent = new ComponentName(context, LauncherNotificationListenerService.class);
    }

    @Override
    public void onListen(Object arguments, EventChannel.EventSink events) {
        sink = events;
        LauncherNotificationListenerService.registerListener(listenerChanged);
        attach();
    }

    @Override
    public void onCancel(Object arguments) {
        LauncherNotificationListenerService.unregisterListener(listenerChanged);
        if (sessionsListening && sessionManager != null) {
            sessionManager.removeOnActiveSessionsChangedListener(sessionsChanged);
        }
        sessionsListening = false;
        clearControllers();
        sink = null;
        lastSentKey = null;
    }

    /** Starts listening to sessions once notification access allows it; a no-op after that. */
    private void attach() {
        if (sink == null || sessionsListening) return;
        if (sessionManager == null) {
            sessionManager = (MediaSessionManager) context.getSystemService(Context.MEDIA_SESSION_SERVICE);
            if (sessionManager == null) return;
        }
        try {
            sessionManager.addOnActiveSessionsChangedListener(sessionsChanged, listenerComponent, main);
            sessionsListening = true;
            setControllers(sessionManager.getActiveSessions(listenerComponent));
        } catch (SecurityException e) {
            // No notification access yet; the listener service connecting will call attach() again.
            Log.i(TAG, "No notification access, so no media sessions");
        }
    }

    private void setControllers(List<MediaController> active) {
        clearControllers();
        if (active != null) {
            for (MediaController controller : active) {
                if (controller.getPackageName().equals(context.getPackageName())) continue;
                MediaController.Callback callback = new MediaController.Callback() {
                    @Override
                    public void onMetadataChanged(MediaMetadata metadata) {
                        publish();
                    }

                    @Override
                    public void onPlaybackStateChanged(PlaybackState state) {
                        publish();
                    }

                    @Override
                    public void onSessionDestroyed() {
                        publish();
                    }
                };
                controller.registerCallback(callback, main);
                controllers.add(controller);
                callbacks.put(controller, callback);
            }
        }
        publish();
    }

    private void clearControllers() {
        for (Map.Entry<MediaController, MediaController.Callback> entry : callbacks.entrySet()) {
            try {
                entry.getKey().unregisterCallback(entry.getValue());
            } catch (Exception ignored) {
            }
        }
        callbacks.clear();
        controllers.clear();
    }

    private static boolean isPlaying(PlaybackState state) {
        if (state == null) return false;
        switch (state.getState()) {
            case PlaybackState.STATE_PLAYING:
            case PlaybackState.STATE_BUFFERING:
            case PlaybackState.STATE_CONNECTING:
            case PlaybackState.STATE_FAST_FORWARDING:
            case PlaybackState.STATE_REWINDING:
            case PlaybackState.STATE_SKIPPING_TO_NEXT:
            case PlaybackState.STATE_SKIPPING_TO_PREVIOUS:
            case PlaybackState.STATE_SKIPPING_TO_QUEUE_ITEM:
                return true;
            default:
                return false;
        }
    }

    /** The session to show: the first one playing, else the first with a title. */
    private MediaController pick() {
        MediaController titled = null;
        for (MediaController controller : controllers) {
            MediaMetadata metadata = controller.getMetadata();
            if (metadata == null || text(metadata, MediaMetadata.METADATA_KEY_TITLE).isEmpty()) continue;
            if (isPlaying(controller.getPlaybackState())) return controller;
            if (titled == null) titled = controller;
        }
        return titled;
    }

    private static String text(MediaMetadata metadata, String key) {
        CharSequence value = metadata.getText(key);
        return value == null ? "" : value.toString().trim();
    }

    private void publish() {
        if (sink == null) return;
        MediaController controller = pick();
        if (controller == null) {
            send("none", new HashMap<>());
            return;
        }
        MediaMetadata metadata = controller.getMetadata();
        String packageName = controller.getPackageName();
        String title = text(metadata, MediaMetadata.METADATA_KEY_TITLE);
        String artist = text(metadata, MediaMetadata.METADATA_KEY_ARTIST);
        if (artist.isEmpty()) artist = text(metadata, MediaMetadata.METADATA_KEY_ALBUM_ARTIST);
        String album = text(metadata, MediaMetadata.METADATA_KEY_ALBUM);
        boolean playing = isPlaying(controller.getPlaybackState());

        Map<String, Object> event = new HashMap<>();
        event.put("packageName", packageName);
        event.put("title", title);
        event.put("artist", artist);
        event.put("album", album);
        event.put("playing", playing);

        String trackKey = packageName + "\n" + title + "\n" + artist + "\n" + album;
        String sendKey = trackKey + "\n" + playing;
        if (trackKey.equals(lastTrackKey)) {
            if (lastArt != null) event.put("art", lastArt);
            send(sendKey, event);
            return;
        }

        // A new track: encode its art off the main thread, then send. A newer event wins.
        final int mine = ++generation;
        final Bitmap bitmap = artBitmap(metadata);
        final String artUri = bitmap == null ? artUri(metadata) : null;
        artExecutor.execute(() -> {
            byte[] art = encode(bitmap != null ? bitmap : load(artUri));
            main.post(() -> {
                if (mine != generation) return;
                lastTrackKey = trackKey;
                lastArt = art;
                if (art != null) event.put("art", art);
                send(sendKey, event);
            });
        });
    }

    private void send(String key, Map<String, Object> event) {
        if (sink == null || Objects.equals(key, lastSentKey)) return;
        if (event.isEmpty()) {
            generation++;
            lastTrackKey = null;
            lastArt = null;
        }
        lastSentKey = key;
        try {
            sink.success(event);
        } catch (Exception e) {
            Log.w(TAG, "Failed to send now playing", e);
        }
    }

    private static Bitmap artBitmap(MediaMetadata metadata) {
        for (String key : new String[]{MediaMetadata.METADATA_KEY_ALBUM_ART, MediaMetadata.METADATA_KEY_ART, MediaMetadata.METADATA_KEY_DISPLAY_ICON}) {
            Bitmap bitmap = metadata.getBitmap(key);
            if (bitmap != null) return bitmap;
        }
        return null;
    }

    private static String artUri(MediaMetadata metadata) {
        for (String key : new String[]{MediaMetadata.METADATA_KEY_ALBUM_ART_URI, MediaMetadata.METADATA_KEY_ART_URI, MediaMetadata.METADATA_KEY_DISPLAY_ICON_URI}) {
            String uri = metadata.getString(key);
            if (uri != null && !uri.isEmpty()) return uri;
        }
        return null;
    }

    /** Art an app only gives as a URI; content:// usually works, anything else is skipped. */
    private Bitmap load(String uri) {
        if (uri == null) return null;
        try {
            Uri parsed = Uri.parse(uri);
            String scheme = parsed.getScheme();
            if (!"content".equals(scheme) && !"android.resource".equals(scheme) && !"file".equals(scheme)) return null;
            try (InputStream in = context.getContentResolver().openInputStream(parsed)) {
                return in == null ? null : BitmapFactory.decodeStream(in);
            }
        } catch (Exception e) {
            return null;
        }
    }

    private static byte[] encode(Bitmap bitmap) {
        if (bitmap == null || bitmap.getWidth() <= 0 || bitmap.getHeight() <= 0) return null;
        try {
            Bitmap scaled = bitmap;
            int largest = Math.max(bitmap.getWidth(), bitmap.getHeight());
            if (largest > ART_MAX_PX) {
                float scale = (float) ART_MAX_PX / largest;
                scaled = Bitmap.createScaledBitmap(bitmap,
                        Math.max(1, Math.round(bitmap.getWidth() * scale)),
                        Math.max(1, Math.round(bitmap.getHeight() * scale)), true);
            }
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            // JPEG: album art is opaque, and it comes out a fraction of the size of a PNG.
            scaled.compress(Bitmap.CompressFormat.JPEG, 90, out);
            return out.toByteArray();
        } catch (Exception e) {
            return null;
        }
    }
}
