package com.leanbitlab.ltvL;

import android.accessibilityservice.AccessibilityService;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.os.SystemClock;
import android.provider.Settings;
import android.view.KeyEvent;
import android.view.accessibility.AccessibilityEvent;

import java.util.HashSet;
import java.util.Set;

/**
 * Google TV can't change its default launcher, so this service puts TvOS in front instead: on the
 * remote's Home button, when the service starts after a reboot, and when the TV wakes from standby.
 * While Google TV's own home is disabled, it also sends the remote's settings button to TV Settings.
 */
public class LauncherAccessibilityService extends AccessibilityService {
    /** Google TV may raise its own home a moment after the screen turns on; win that race too. */
    private static final long WAKE_WINDOW_MS = 10_000;
    private static final long MIN_GAP_MS = 500;
    private static final String GOOGLE_TV_HOME = "com.google.android.apps.tv.launcherx";

    private final Set<String> stockLaunchers = new HashSet<>();
    private long wokeAt = -WAKE_WINDOW_MS;
    private long lastBroughtForward = -MIN_GAP_MS;

    private final BroadcastReceiver screenOn = new BroadcastReceiver() {
        @Override
        public void onReceive(Context context, Intent intent) {
            wokeAt = SystemClock.elapsedRealtime();
            bringForward();
        }
    };

    @Override
    protected void onServiceConnected() {
        super.onServiceConnected();
        findStockLaunchers();
        registerReceiver(screenOn, new IntentFilter(Intent.ACTION_SCREEN_ON));
        bringForward();
    }

    @Override
    public void onDestroy() {
        try {
            unregisterReceiver(screenOn);
        } catch (IllegalArgumentException ignored) {
            // Never registered: the service was destroyed before it connected.
        }
        super.onDestroy();
    }

    @Override
    public void onAccessibilityEvent(AccessibilityEvent event) {
        if (event.getEventType() != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return;
        if (SystemClock.elapsedRealtime() - wokeAt > WAKE_WINDOW_MS) return;
        CharSequence pkg = event.getPackageName();
        if (pkg != null && stockLaunchers.contains(pkg.toString())) bringForward();
    }

    @Override
    public void onInterrupt() {
        // Not used
    }

    @Override
    protected boolean onKeyEvent(KeyEvent event) {
        if (event.getKeyCode() == KeyEvent.KEYCODE_HOME) {
            if (event.getAction() == KeyEvent.ACTION_DOWN) bringForward();
            return true; // Consume Home key event
        }
        if (isSettingsKey(event.getKeyCode()) && !googleHomeEnabled()) {
            if (event.getAction() == KeyEvent.ACTION_DOWN) openSettings();
            return true;
        }
        return super.onKeyEvent(event);
    }

    /** The Google TV remote's gear sends NOTIFICATION; other remotes send SETTINGS. */
    private static boolean isSettingsKey(int keyCode) {
        return keyCode == KeyEvent.KEYCODE_SETTINGS || keyCode == KeyEvent.KEYCODE_NOTIFICATION;
    }

    /** Google TV's quick-settings panel lives in its home app; while that is enabled, the gear is left to it. */
    private boolean googleHomeEnabled() {
        try {
            return getPackageManager().getApplicationInfo(GOOGLE_TV_HOME, 0).enabled;
        } catch (PackageManager.NameNotFoundException e) {
            return false;
        }
    }

    private void openSettings() {
        startActivity(new Intent(Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
    }

    private void bringForward() {
        long now = SystemClock.elapsedRealtime();
        if (now - lastBroughtForward < MIN_GAP_MS) return;
        lastBroughtForward = now;
        Intent intent = new Intent(this, MainActivity.class);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
        startActivity(intent);
    }

    /** Every other home app; TV Settings' fallback home is left out so opening Settings is never undone. */
    private void findStockLaunchers() {
        Intent home = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME);
        for (ResolveInfo info : getPackageManager().queryIntentActivities(home, PackageManager.MATCH_ALL)) {
            String pkg = info.activityInfo.packageName;
            if (pkg.startsWith("com.spencerking.tvos") || pkg.contains("settings")) continue;
            stockLaunchers.add(pkg);
        }
    }
}
