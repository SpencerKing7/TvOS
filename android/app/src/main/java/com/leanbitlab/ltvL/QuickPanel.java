/*
 * TvOS — a minimal home screen built on FLauncher / LTvLauncher.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

package com.leanbitlab.ltvL;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
import android.media.tv.TvContract;
import android.media.tv.TvInputInfo;
import android.media.tv.TvInputManager;
import android.provider.Settings;
import android.util.Log;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;

/**
 * The quick settings panel's link to the TV: the live inputs, switching to one, and opening a
 * Settings page. Shared by Home (the panel inside it) and {@link QuickPanelActivity} (the panel
 * over any app).
 */
final class QuickPanel {
    static final String CHANNEL = "tvos/quick_panel";
    private static final String TAG = "QuickPanel";

    /** What a channel's ACTION_VIEW needs to resolve on this TV: the URI alone matches nothing. */
    private static final String CHANNEL_ITEM_TYPE = "vnd.android.cursor.item/channel";

    private QuickPanel() {}

    /**
     * Wires the channel. [onClose] runs when the panel asks to close (the overlay finishes;
     * Home has nothing to do).
     */
    static MethodChannel register(BinaryMessenger messenger, Activity activity, Runnable onClose) {
        MethodChannel channel = new MethodChannel(messenger, CHANNEL);
        channel.setMethodCallHandler((call, result) -> {
            switch (call.method) {
                case "inputs" -> result.success(inputs(activity));
                case "openInput" -> result.success(openInput(activity, call.arguments()));
                case "openSettings" -> result.success(openSettings(activity, call.arguments()));
                case "close" -> {
                    onClose.run();
                    result.success(true);
                }
                default -> result.notImplemented();
            }
        });
        return channel;
    }

    /**
     * Hardware inputs with something on them: connected first, then connected-but-asleep
     * (selecting one may wake the device over HDMI-CEC). Disconnected ones and the inputs
     * that streaming apps register are left out.
     */
    static List<Map<String, Object>> inputs(Context context) {
        List<Map<String, Object>> awake = new ArrayList<>();
        List<Map<String, Object>> asleep = new ArrayList<>();
        try {
            TvInputManager manager = (TvInputManager) context.getSystemService(Context.TV_INPUT_SERVICE);
            if (manager == null) return awake;
            for (TvInputInfo input : manager.getTvInputList()) {
                if (!input.isPassthroughInput()) continue;
                int state = manager.getInputState(input.getId());
                if (state == TvInputManager.INPUT_STATE_DISCONNECTED) continue;
                CharSequence custom = input.loadCustomLabel(context);
                CharSequence label = custom != null && custom.length() > 0 ? custom : input.loadLabel(context);
                Map<String, Object> map = new HashMap<>();
                map.put("id", input.getId());
                map.put("label", label != null ? label.toString() : input.getId());
                map.put("standby", state == TvInputManager.INPUT_STATE_CONNECTED_STANDBY);
                (state == TvInputManager.INPUT_STATE_CONNECTED ? awake : asleep).add(map);
            }
        } catch (Exception e) {
            Log.w(TAG, "Couldn't list TV inputs", e);
        }
        // Each group in name order (HDMI 1, 2, 3), not the order the TV happens to list them.
        java.util.Comparator<Map<String, Object>> byLabel =
                java.util.Comparator.comparing(m -> m.get("label").toString(), String.CASE_INSENSITIVE_ORDER);
        awake.sort(byLabel);
        asleep.sort(byLabel);
        awake.addAll(asleep);
        return awake;
    }

    static boolean openInput(Context context, String inputId) {
        Intent intent = new Intent(Intent.ACTION_VIEW)
                .setDataAndType(TvContract.buildChannelUriForPassthroughInput(inputId), CHANNEL_ITEM_TYPE)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        return start(context, intent);
    }

    /** A Settings page by its action, or all of Settings when this TV has no such page. */
    static boolean openSettings(Context context, String action) {
        Intent intent = new Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        if (start(context, intent)) return true;
        return start(context, new Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
    }

    private static boolean start(Context context, Intent intent) {
        try {
            context.startActivity(intent);
            return true;
        } catch (ActivityNotFoundException | SecurityException e) {
            Log.w(TAG, "Couldn't open " + intent, e);
            return false;
        }
    }
}
