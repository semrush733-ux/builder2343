package com.bwpexperts.billing.nativeplugin;

import android.Manifest;
import android.app.Activity;
import android.content.ClipData;
import android.content.Intent;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.provider.MediaStore;
import android.util.Log;
import android.webkit.ValueCallback;
import android.webkit.WebView;

import androidx.activity.result.ActivityResult;
import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.content.ContextCompat;
import androidx.core.content.FileProvider;

import com.getcapacitor.Bridge;
import com.getcapacitor.BridgeWebChromeClient;

import java.io.File;
import java.util.Locale;

/**
 * File inputs on the billing website (proof / document uploads).
 *
 * Capacitor's own chooser offers the camera only when the input has a "capture" attribute.
 * This client shows ONE chooser with Camera + Gallery + Files for inputs that accept images,
 * and falls back to Capacitor's behaviour for everything else or if anything goes wrong.
 */
public class BwpChromeClient extends BridgeWebChromeClient {

    private static final String TAG = "BwpNative";

    private final AppCompatActivity activity;
    private final ActivityResultLauncher<Intent> launcher;
    private ValueCallback<Uri[]> pending;
    private File cameraFile;
    private Uri cameraUri;

    public BwpChromeClient(Bridge bridge) {
        super(bridge);
        this.activity = bridge.getActivity();
        this.launcher = activity.registerForActivityResult(new ActivityResultContracts.StartActivityForResult(), this::onChooserResult);
    }

    @Override
    public boolean onShowFileChooser(WebView webView, ValueCallback<Uri[]> filePathCallback, FileChooserParams params) {
        String[] accept = params == null ? null : params.getAcceptTypes();
        if (params == null || !acceptsImages(accept)) {
            return super.onShowFileChooser(webView, filePathCallback, params);
        }
        try {
            if (pending != null) {
                pending.onReceiveValue(null);
            }
            pending = filePathCallback;

            Intent camera = buildCameraIntent();

            Intent content = new Intent(Intent.ACTION_GET_CONTENT);
            content.addCategory(Intent.CATEGORY_OPENABLE);
            String[] mimeTypes = toMimeTypes(accept);
            if (mimeTypes.length == 1) {
                content.setType(mimeTypes[0]);
            } else {
                content.setType("*/*");
                if (mimeTypes.length > 1) {
                    content.putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes);
                }
            }
            if (params.getMode() == FileChooserParams.MODE_OPEN_MULTIPLE) {
                content.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);
            }

            Intent toLaunch;
            if (params.isCaptureEnabled() && camera != null) {
                // <input capture>: go straight to the camera.
                toLaunch = camera;
            } else {
                toLaunch = Intent.createChooser(content, "Choose file");
                if (camera != null) {
                    toLaunch.putExtra(Intent.EXTRA_INITIAL_INTENTS, new Intent[] { camera });
                }
            }
            launcher.launch(toLaunch);
            return true;
        } catch (Throwable t) {
            Log.w(TAG, "Custom file chooser failed, using the default one", t);
            pending = null;
            cameraFile = null;
            cameraUri = null;
            return super.onShowFileChooser(webView, filePathCallback, params);
        }
    }

    private void onChooserResult(ActivityResult result) {
        ValueCallback<Uri[]> callback = pending;
        pending = null;
        if (callback == null) {
            return;
        }
        Uri[] uris = null;
        try {
            if (result.getResultCode() == Activity.RESULT_OK) {
                Intent data = result.getData();
                if (data != null && data.getClipData() != null && data.getClipData().getItemCount() > 0) {
                    ClipData clip = data.getClipData();
                    uris = new Uri[clip.getItemCount()];
                    for (int i = 0; i < clip.getItemCount(); i++) {
                        uris[i] = clip.getItemAt(i).getUri();
                    }
                } else if (data != null && data.getData() != null) {
                    uris = new Uri[] { data.getData() };
                } else if (cameraFile != null && cameraUri != null && cameraFile.length() > 0) {
                    uris = new Uri[] { cameraUri };
                }
            }
        } catch (Throwable t) {
            Log.w(TAG, "Could not read the chosen file", t);
            uris = null;
        }
        cameraFile = null;
        cameraUri = null;
        callback.onReceiveValue(uris);
    }

    /** Photo with the phone's camera app, written into the app's private cache. */
    private Intent buildCameraIntent() {
        try {
            // If the app declares the CAMERA permission but it is not granted, Android refuses this intent.
            if (declaresCameraPermission() &&
                ContextCompat.checkSelfPermission(activity, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
                return null;
            }
            File dir = new File(activity.getCacheDir(), "bwp-camera");
            if (!dir.exists() && !dir.mkdirs()) {
                return null;
            }
            File[] old = dir.listFiles();
            if (old != null) {
                long cutoff = System.currentTimeMillis() - 24L * 60L * 60L * 1000L;
                for (File file : old) {
                    if (file.isFile() && file.lastModified() < cutoff) {
                        //noinspection ResultOfMethodCallIgnored
                        file.delete();
                    }
                }
            }
            cameraFile = new File(dir, "photo-" + System.currentTimeMillis() + ".jpg");
            cameraUri = FileProvider.getUriForFile(activity, activity.getPackageName() + ".bwpfiles", cameraFile);
            Intent camera = new Intent(MediaStore.ACTION_IMAGE_CAPTURE);
            camera.putExtra(MediaStore.EXTRA_OUTPUT, cameraUri);
            camera.setClipData(ClipData.newRawUri("photo", cameraUri));
            camera.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION | Intent.FLAG_GRANT_READ_URI_PERMISSION);
            return camera;
        } catch (Throwable t) {
            cameraFile = null;
            cameraUri = null;
            return null;
        }
    }

    private boolean declaresCameraPermission() {
        try {
            PackageInfo info = activity.getPackageManager().getPackageInfo(activity.getPackageName(), PackageManager.GET_PERMISSIONS);
            if (info.requestedPermissions != null) {
                for (String permission : info.requestedPermissions) {
                    if (Manifest.permission.CAMERA.equals(permission)) {
                        return true;
                    }
                }
            }
        } catch (Exception ignored) {
            // treat as not declared
        }
        return false;
    }

    /** True when the input accepts images (or anything), so offering the camera makes sense. */
    private static boolean acceptsImages(String[] accept) {
        if (accept == null || accept.length == 0) {
            return true;
        }
        boolean sawType = false;
        for (String raw : accept) {
            if (raw == null) {
                continue;
            }
            for (String part : raw.split(",")) {
                String type = part.trim().toLowerCase(Locale.ROOT);
                if (type.isEmpty()) {
                    continue;
                }
                sawType = true;
                if (type.equals("*/*") || type.startsWith("image/") ||
                    type.equals(".jpg") || type.equals(".jpeg") || type.equals(".png") || type.equals(".webp") || type.equals(".heic")) {
                    return true;
                }
            }
        }
        return !sawType;
    }

    /** Converts accept="image/*,.pdf" style values to MIME types for the system picker. */
    private static String[] toMimeTypes(String[] accept) {
        java.util.LinkedHashSet<String> types = new java.util.LinkedHashSet<>();
        if (accept != null) {
            for (String raw : accept) {
                if (raw == null) {
                    continue;
                }
                for (String part : raw.split(",")) {
                    String type = part.trim().toLowerCase(Locale.ROOT);
                    if (type.isEmpty()) {
                        continue;
                    }
                    if (type.startsWith(".")) {
                        String mime = android.webkit.MimeTypeMap.getSingleton().getMimeTypeFromExtension(type.substring(1));
                        if (mime != null) {
                            types.add(mime);
                        }
                    } else if (type.contains("/")) {
                        types.add(type);
                    }
                }
            }
        }
        if (types.isEmpty()) {
            types.add("*/*");
        }
        return types.toArray(new String[0]);
    }
}
