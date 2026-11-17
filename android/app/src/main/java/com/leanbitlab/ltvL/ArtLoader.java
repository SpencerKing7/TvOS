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
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.net.Uri;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;

/** Album art and posters other apps hand over as a bitmap or a local URI, made small for Dart. */
final class ArtLoader {
    private ArtLoader() {}

    /** content://, android.resource:// or file:// only; web images are loaded by Flutter itself. */
    static Bitmap decodeUri(Context context, String uri) {
        if (uri == null || uri.isEmpty()) return null;
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

    /** JPEG no larger than [maxPx] on its longer side; the art is opaque, and JPEG is a fraction of PNG's size. */
    static byte[] encode(Bitmap bitmap, int maxPx) {
        if (bitmap == null || bitmap.getWidth() <= 0 || bitmap.getHeight() <= 0) return null;
        try {
            Bitmap scaled = bitmap;
            int largest = Math.max(bitmap.getWidth(), bitmap.getHeight());
            if (largest > maxPx) {
                float scale = (float) maxPx / largest;
                scaled = Bitmap.createScaledBitmap(bitmap,
                        Math.max(1, Math.round(bitmap.getWidth() * scale)),
                        Math.max(1, Math.round(bitmap.getHeight() * scale)), true);
            }
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            scaled.compress(Bitmap.CompressFormat.JPEG, 90, out);
            return out.toByteArray();
        } catch (Exception e) {
            return null;
        }
    }
}
