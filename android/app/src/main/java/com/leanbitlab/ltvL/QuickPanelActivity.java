/*
 * TvOS — a minimal home screen built on FLauncher / LTvLauncher.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

package com.leanbitlab.ltvL;

import android.content.Context;
import android.content.Intent;

import androidx.annotation.NonNull;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.android.FlutterActivityLaunchConfigs.BackgroundMode;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.FlutterEngineCache;
import io.flutter.embedding.engine.dart.DartExecutor;
import io.flutter.FlutterInjector;
import io.flutter.plugin.common.MethodChannel;

/**
 * The quick settings panel over whatever app is on screen, opened by the remote's settings
 * button. A see-through window running only the panel (Dart entry point `quickPanelMain`) on
 * an engine kept warm after the first open, so later opens are quick.
 */
public class QuickPanelActivity extends FlutterActivity {
    private static final String ENGINE = "quick_panel";

    private MethodChannel channel;

    static void open(Context context) {
        context.startActivity(new Intent(context, QuickPanelActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP));
    }

    @Override
    public FlutterEngine provideFlutterEngine(@NonNull Context context) {
        FlutterEngine engine = FlutterEngineCache.getInstance().get(ENGINE);
        if (engine == null) {
            engine = new FlutterEngine(context.getApplicationContext());
            String bundle = FlutterInjector.instance().flutterLoader().findAppBundlePath();
            engine.getDartExecutor().executeDartEntrypoint(new DartExecutor.DartEntrypoint(bundle, "quickPanelMain"));
            FlutterEngineCache.getInstance().put(ENGINE, engine);
        }
        return engine;
    }

    // The warm engine outlives this window: keep it when the window closes.
    @Override
    public boolean shouldDestroyEngineWithHost() {
        return false;
    }

    @NonNull
    @Override
    protected BackgroundMode getBackgroundMode() {
        return BackgroundMode.transparent;
    }

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        channel = QuickPanel.register(flutterEngine.getDartExecutor().getBinaryMessenger(), this, this::close);
    }

    @Override
    protected void onResume() {
        super.onResume();
        // A warm engine still shows the last panel: start it fresh, sliding in.
        if (channel != null) channel.invokeMethod("opened", null);
    }

    private void close() {
        finish();
        overridePendingTransition(0, 0);
    }
}
