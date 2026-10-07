package com.bwpexperts.billing.nativeplugin;

import android.content.ActivityNotFoundException;
import android.content.ClipData;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.print.PrintAttributes;
import android.print.PrintManager;
import android.provider.MediaStore;
import android.util.Base64;
import android.util.Log;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowManager;
import android.webkit.CookieManager;
import android.webkit.JavascriptInterface;
import android.webkit.MimeTypeMap;
import android.webkit.URLUtil;
import android.webkit.WebBackForwardList;
import android.webkit.WebView;
import android.widget.FrameLayout;
import android.widget.Toast;

import androidx.activity.OnBackPressedCallback;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.content.FileProvider;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.core.view.WindowInsetsControllerCompat;
import androidx.swiperefreshlayout.widget.SwipeRefreshLayout;
import androidx.webkit.JavaScriptReplyProxy;
import androidx.webkit.WebViewCompat;
import androidx.webkit.WebViewFeature;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.WebViewListener;
import com.getcapacitor.annotation.CapacitorPlugin;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Native features for Android (BWP app shell).
 *
 * Everything that makes the app more than a plain web view lives in this plugin, so the
 * generated Capacitor project (MainActivity etc.) stays untouched:
 *
 *  - injects src/bwp-bridge.js into the billing website and answers its requests through an
 *    origin-restricted message channel ("bwpNative")
 *  - Android Back button: go back in history, "press back again to exit" on the first page
 *  - pull-to-refresh
 *  - safe areas (status bar, cut-out, navigation bar, keyboard) and status-bar colour
 *  - downloads: save to Downloads, then Open / Share
 *  - print (native print dialog, also "Save as PDF")
 *  - share sheet
 *  - file inputs: camera OR gallery/files chooser
 *  - deep links (https://bill.bwpexperts.com/...)
 *  - optional screenshot protection per screen (off by default)
 */
@CapacitorPlugin(name = "BwpNative")
public class BwpNativePlugin extends Plugin {

    private static final String TAG = "BwpNative";
    private static final String DOWNLOAD_DIR = "bwp-downloads";
    private static final long EXIT_WINDOW_MS = 2000L;
    private static final long REFRESH_TIMEOUT_MS = 12000L;
    private static final long DOWNLOAD_MAX_AGE_MS = 24L * 60L * 60L * 1000L;

    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService worker = Executors.newSingleThreadExecutor();

    // Configuration (capacitor.config.ts -> plugins.BwpNative)
    private String appName = "";
    private String homeUrl = "https://bill.bwpexperts.com/login";
    private final Set<String> allowedHosts = new HashSet<>();
    private int brandColor = Color.parseColor("#014F4A");
    private int shellColor = Color.WHITE;
    private boolean pullToRefresh = true;
    private String exitMessage = "Press back again to exit";

    // State
    private SwipeRefreshLayout swipe;
    private SystemBarsDrawable barsDrawable;
    private BwpChromeClient chromeClient;
    private String bridgeScript = "";
    private volatile boolean refreshAllowedByPage = true;
    private volatile String lastUrl = null;
    private long lastBackPress = 0L;
    private int topColor = Color.WHITE;
    private int bottomColor = Color.WHITE;

    private final Runnable stopRefreshing = () -> {
        if (swipe != null) {
            swipe.setRefreshing(false);
        }
    };

    // ------------------------------------------------------------------ lifecycle

    @Override
    public void load() {
        readConfig();
        final AppCompatActivity activity = getActivity();
        final WebView webView = getBridge().getWebView();

        // The keyboard must resize the page, never cover the focused field.
        activity.getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);

        step("native channel", () -> installNativeChannel(webView));
        step("bridge script", () -> installBridgeScript(webView));
        step("pull to refresh", () -> installContainer(activity, webView));
        step("safe areas", () -> installInsetsHandling(activity));
        step("back button", () -> installBackHandler(activity));
        step("downloads", () -> installDownloadListener(webView));
        step("file chooser", () -> installFileChooser(webView));
        step("page listener", this::installPageListener);
        step("theme", () -> applyTheme(shellColor, shellColor));
        step("deep link", () -> openDeepLink(activity.getIntent(), true));
    }

    /** One feature failing must never stop the app from starting. */
    private void step(String name, Runnable action) {
        try {
            action.run();
        } catch (Throwable t) {
            Log.e(TAG, "Could not set up: " + name, t);
        }
    }

    @Override
    protected void handleOnPause() {
        super.handleOnPause();
        // Write the login cookies to disk so the session survives the app being closed.
        try {
            CookieManager.getInstance().flush();
        } catch (Throwable ignored) {
            // not critical
        }
    }

    @Override
    protected void handleOnNewIntent(Intent intent) {
        super.handleOnNewIntent(intent);
        openDeepLink(intent, false);
    }

    private void readConfig() {
        homeUrl = getConfig().getString("homeUrl", homeUrl);
        String[] hosts = getConfig().getArray("allowedHosts");
        if (hosts != null) {
            for (String host : hosts) {
                if (host != null && !host.trim().isEmpty()) {
                    allowedHosts.add(host.trim().toLowerCase(Locale.ROOT));
                }
            }
        }
        if (allowedHosts.isEmpty()) {
            Uri home = Uri.parse(homeUrl);
            if (home.getHost() != null) {
                allowedHosts.add(home.getHost().toLowerCase(Locale.ROOT));
            }
        }
        brandColor = parseColor(getConfig().getString("brandColor", null), brandColor);
        shellColor = parseColor(getConfig().getString("backgroundColor", null), shellColor);
        pullToRefresh = getConfig().getBoolean("pullToRefresh", true);
        exitMessage = getConfig().getString("exitMessage", exitMessage);
        appName = getConfig().getString("appName", "");
        if (appName == null || appName.trim().isEmpty()) {
            // Fall back to the name shown under the launcher icon.
            try {
                appName = getContext().getApplicationInfo().loadLabel(getContext().getPackageManager()).toString();
            } catch (Exception e) {
                appName = "App";
            }
        }
        topColor = shellColor;
        bottomColor = shellColor;
    }

    // ------------------------------------------------------------------ channel between the website and this plugin

    /** Answers one message of the channel with a JSON string. */
    private interface ReplySink {
        void send(String json);
    }

    private Set<String> allowedOrigins() {
        Set<String> origins = new HashSet<>();
        for (String host : allowedHosts) {
            origins.add("https://" + host);
        }
        return origins;
    }

    /**
     * Capacitor only injects its own JavaScript bridge into the local pages, not into remote
     * websites. The billing website therefore talks to this plugin through its own channel,
     * which Android exposes ONLY to the allowed https origins (window.bwpNative).
     */
    private void installNativeChannel(final WebView webView) {
        if (WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) {
            WebViewCompat.addWebMessageListener(webView, "bwpNative", allowedOrigins(), (view, message, sourceOrigin, isMainFrame, replyProxy) -> {
                if (!isMainFrame) {
                    return;
                }
                final JavaScriptReplyProxy proxy = replyProxy;
                handleMessage(message.getData(), json -> main.post(() -> {
                    try {
                        proxy.postMessage(json);
                    } catch (Throwable t) {
                        Log.w(TAG, "Could not answer the page", t);
                    }
                }));
            });
        } else {
            // Very old WebView: classic interface, with the page origin checked on every message.
            webView.addJavascriptInterface(new LegacyChannel(), "bwpNativeLegacy");
        }
    }

    private class LegacyChannel {

        @JavascriptInterface
        public void postMessage(final String data) {
            main.post(() -> {
                final WebView webView = getBridge().getWebView();
                if (!isAllowedUrl(webView.getUrl())) {
                    return;
                }
                handleMessage(data, json -> main.post(() ->
                    webView.evaluateJavascript("window.__bwpNativeReply && window.__bwpNativeReply(" + JSONObject.quote(json) + ");", null)
                ));
            });
        }
    }

    private void handleMessage(String data, final ReplySink sink) {
        final String id;
        final String method;
        final JSONObject args;
        try {
            JSONObject message = new JSONObject(data == null ? "{}" : data);
            id = message.optString("id", "");
            method = message.optString("method", "");
            JSONObject given = message.optJSONObject("args");
            args = given != null ? given : new JSONObject();
        } catch (Exception e) {
            return;
        }
        dispatch(method, new NativeCall() {
            private boolean answered = false;

            private synchronized void answer(boolean ok, JSONObject result, String error) {
                if (answered) {
                    return;
                }
                answered = true;
                try {
                    JSONObject reply = new JSONObject();
                    reply.put("id", id);
                    reply.put("ok", ok);
                    if (result != null) {
                        reply.put("result", result);
                    }
                    if (error != null) {
                        reply.put("error", error);
                    }
                    sink.send(reply.toString());
                } catch (Exception ignored) {
                    // nothing to answer with
                }
            }

            @Override
            public String getString(String key) {
                return args.isNull(key) ? null : args.optString(key, null);
            }

            @Override
            public String getString(String key, String fallback) {
                return args.isNull(key) ? fallback : args.optString(key, fallback);
            }

            @Override
            public boolean getBoolean(String key, boolean fallback) {
                return args.optBoolean(key, fallback);
            }

            @Override
            public void resolve() {
                answer(true, new JSONObject(), null);
            }

            @Override
            public void resolve(JSObject result) {
                answer(true, result, null);
            }

            @Override
            public void reject(String message) {
                answer(false, null, message);
            }

            @Override
            public void reject(String message, Exception cause) {
                answer(false, null, message);
            }
        });
    }

    private void dispatch(String method, final NativeCall call) {
        try {
            switch (method == null ? "" : method) {
                case "saveFile":
                    worker.execute(() -> doSaveFile(call));
                    break;
                case "printPage":
                    doPrintPage(call);
                    break;
                case "share":
                    doShare(call);
                    break;
                case "setTheme":
                    doSetTheme(call);
                    break;
                case "setRefreshAllowed":
                    doSetRefreshAllowed(call);
                    break;
                case "pageReady":
                    doPageReady(call);
                    break;
                case "setScreenSecure":
                    doSetScreenSecure(call);
                    break;
                case "openExternal":
                    doOpenExternal(call);
                    break;
                case "getLastUrl":
                    doGetLastUrl(call);
                    break;
                default:
                    call.reject("Unknown method: " + method);
            }
        } catch (Throwable t) {
            Log.e(TAG, "Native call failed: " + method, t);
            call.reject("Native call failed");
        }
    }

    /** The same methods through the Capacitor bridge (used by the local launch / error screens). */
    private void fromCapacitor(String method, final PluginCall call) {
        dispatch(method, new NativeCall() {
            @Override
            public String getString(String key) {
                return call.getString(key);
            }

            @Override
            public String getString(String key, String fallback) {
                return call.getString(key, fallback);
            }

            @Override
            public boolean getBoolean(String key, boolean fallback) {
                Boolean value = call.getBoolean(key, fallback);
                return value != null ? value : fallback;
            }

            @Override
            public void resolve() {
                call.resolve();
            }

            @Override
            public void resolve(JSObject result) {
                call.resolve(result);
            }

            @Override
            public void reject(String message) {
                call.reject(message);
            }

            @Override
            public void reject(String message, Exception cause) {
                call.reject(message, cause);
            }
        });
    }

    @PluginMethod
    public void saveFile(PluginCall call) {
        fromCapacitor("saveFile", call);
    }

    @PluginMethod
    public void printPage(PluginCall call) {
        fromCapacitor("printPage", call);
    }

    @PluginMethod
    public void share(PluginCall call) {
        fromCapacitor("share", call);
    }

    @PluginMethod
    public void setTheme(PluginCall call) {
        fromCapacitor("setTheme", call);
    }

    @PluginMethod
    public void setRefreshAllowed(PluginCall call) {
        fromCapacitor("setRefreshAllowed", call);
    }

    @PluginMethod
    public void pageReady(PluginCall call) {
        fromCapacitor("pageReady", call);
    }

    @PluginMethod
    public void setScreenSecure(PluginCall call) {
        fromCapacitor("setScreenSecure", call);
    }

    @PluginMethod
    public void openExternal(PluginCall call) {
        fromCapacitor("openExternal", call);
    }

    @PluginMethod
    public void getLastUrl(PluginCall call) {
        fromCapacitor("getLastUrl", call);
    }

    // ------------------------------------------------------------------ bridge script

    private void installBridgeScript(WebView webView) {
        String source = readAsset("public/bwp-bridge.js");
        if (source.isEmpty()) {
            Log.w(TAG, "public/bwp-bridge.js not found in the app assets. Run: npx cap sync android");
            return;
        }
        bridgeScript = "window.__BWP_CONFIG__ = " + buildScriptConfig() + ";\n" + source;

        // Preferred: run at document start on the billing website only.
        if (WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            WebViewCompat.addDocumentStartJavaScript(webView, bridgeScript, allowedOrigins());
        }
        // Older WebViews are covered in the page listener (script is idempotent).
    }

    private String buildScriptConfig() {
        try {
            JSONObject json = new JSONObject();
            json.put("platform", "android");
            json.put("appName", appName);
            json.put("homeUrl", homeUrl);
            json.put("allowedHosts", new JSONArray(new ArrayList<>(allowedHosts)));
            json.put("pullToRefresh", pullToRefresh);
            json.put("downloadExtensions", toJsonArray(getConfig().getArray("downloadExtensions")));
            json.put("secureScreenPaths", toJsonArray(getConfig().getArray("secureScreenPaths")));
            return json.toString();
        } catch (Exception e) {
            return "{}";
        }
    }

    private static JSONArray toJsonArray(String[] values) {
        JSONArray array = new JSONArray();
        if (values != null) {
            for (String value : values) {
                array.put(value);
            }
        }
        return array;
    }

    private String readAsset(String path) {
        StringBuilder out = new StringBuilder();
        try (InputStream in = getContext().getAssets().open(path);
             BufferedReader reader = new BufferedReader(new InputStreamReader(in, StandardCharsets.UTF_8))) {
            char[] buffer = new char[8192];
            int read;
            while ((read = reader.read(buffer)) != -1) {
                out.append(buffer, 0, read);
            }
        } catch (Exception e) {
            return "";
        }
        return out.toString();
    }

    private void installPageListener() {
        getBridge().addWebViewListener(new WebViewListener() {
            @Override
            public void onPageStarted(WebView webView) {
                String url = webView.getUrl();
                refreshAllowedByPage = true;
                if (isAllowedUrl(url)) {
                    lastUrl = url;
                } else if (isLocalUrl(url)) {
                    applyTheme(shellColor, shellColor);
                }
            }

            @Override
            public void onPageLoaded(WebView webView) {
                main.removeCallbacks(stopRefreshing);
                stopRefreshing.run();
                String url = webView.getUrl();
                if (isAllowedUrl(url)) {
                    // Safety net for WebViews without document-start scripts.
                    if (!bridgeScript.isEmpty()) {
                        webView.evaluateJavascript(bridgeScript, null);
                    }
                } else if (isLocalUrl(url) && lastUrl != null) {
                    // Tell the local error screen which page to retry.
                    webView.evaluateJavascript(
                        "window.__bwpShell && window.__bwpShell.setRetryUrl(" + JSONObject.quote(lastUrl) + ");",
                        null
                    );
                }
            }

            @Override
            public void onReceivedError(WebView webView) {
                main.removeCallbacks(stopRefreshing);
                stopRefreshing.run();
            }
        });
    }

    // ------------------------------------------------------------------ container + pull to refresh

    /**
     * Puts the web view inside: SwipeRefreshLayout > FrameLayout > WebView.
     * The SwipeRefreshLayout is also the view that receives the safe-area padding.
     */
    private void installContainer(AppCompatActivity activity, final WebView webView) {
        ViewGroup parent = (ViewGroup) webView.getParent();
        if (parent == null) {
            return;
        }
        int index = parent.indexOfChild(webView);
        ViewGroup.LayoutParams params = webView.getLayoutParams();
        parent.removeView(webView);

        FrameLayout holder = new FrameLayout(activity);
        holder.addView(
            webView,
            new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        );

        swipe = new SwipeRefreshLayout(activity);
        swipe.addView(
            holder,
            new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        );
        barsDrawable = new SystemBarsDrawable(topColor, bottomColor);
        swipe.setBackground(barsDrawable);
        swipe.setColorSchemeColors(brandColor);
        swipe.setEnabled(pullToRefresh);
        // "Can the content still scroll up?" - if yes, the pull gesture belongs to the page.
        swipe.setOnChildScrollUpCallback((layout, child) ->
            !refreshAllowedByPage || webView.getScrollY() > 0 || isLocalUrl(webView.getUrl())
        );
        swipe.setOnRefreshListener(() -> {
            webView.reload();
            main.removeCallbacks(stopRefreshing);
            main.postDelayed(stopRefreshing, REFRESH_TIMEOUT_MS);
        });

        if (params != null) {
            parent.addView(swipe, index, params);
        } else {
            parent.addView(swipe, index);
        }
    }

    // ------------------------------------------------------------------ safe areas + status bar

    private void installInsetsHandling(AppCompatActivity activity) {
        if (swipe == null) {
            return;
        }
        final View decor = activity.getWindow().getDecorView();
        ViewCompat.setOnApplyWindowInsetsListener(swipe, (view, insets) -> {
            view.post(this::applySafeArea);
            return insets;
        });
        decor.getViewTreeObserver().addOnGlobalLayoutListener(this::applySafeArea);
        ViewCompat.requestApplyInsets(swipe);
    }

    /**
     * Pads the container by exactly the amount it is covered by system bars, the display
     * cut-out or the keyboard. It measures real positions, so it is correct both on
     * edge-to-edge devices (Android 15+) and on older ones, where the answer is simply 0.
     */
    private void applySafeArea() {
        if (swipe == null || swipe.getWidth() == 0 || swipe.getHeight() == 0) {
            return;
        }
        View decor = getActivity().getWindow().getDecorView();
        WindowInsetsCompat root = ViewCompat.getRootWindowInsets(decor);
        if (root == null) {
            return;
        }
        Insets bars = root.getInsets(WindowInsetsCompat.Type.systemBars() | WindowInsetsCompat.Type.displayCutout());
        Insets keyboard = root.getInsets(WindowInsetsCompat.Type.ime());
        int insetBottom = Math.max(bars.bottom, keyboard.bottom);

        int[] at = new int[2];
        swipe.getLocationInWindow(at);
        int left = at[0];
        int top = at[1];
        int right = left + swipe.getWidth();
        int bottom = top + swipe.getHeight();

        // Space that something else (for example Capacitor itself) already keeps free
        // between this container and the web view, so it is never applied twice.
        int gapLeft = 0;
        int gapTop = 0;
        int gapRight = 0;
        int gapBottom = 0;
        WebView webView = getBridge().getWebView();
        if (webView != null && webView.getWidth() > 0 && webView.getHeight() > 0) {
            int[] web = new int[2];
            webView.getLocationInWindow(web);
            gapLeft = Math.max(0, web[0] - (left + swipe.getPaddingLeft()));
            gapTop = Math.max(0, web[1] - (top + swipe.getPaddingTop()));
            gapRight = Math.max(0, (right - swipe.getPaddingRight()) - (web[0] + webView.getWidth()));
            gapBottom = Math.max(0, (bottom - swipe.getPaddingBottom()) - (web[1] + webView.getHeight()));
        }

        int padLeft = Math.max(0, bars.left - left - gapLeft);
        int padTop = Math.max(0, bars.top - top - gapTop);
        int padRight = Math.max(0, right - (decor.getWidth() - bars.right) - gapRight);
        int padBottom = Math.max(0, bottom - (decor.getHeight() - insetBottom) - gapBottom);

        if (
            padLeft != swipe.getPaddingLeft() ||
            padTop != swipe.getPaddingTop() ||
            padRight != swipe.getPaddingRight() ||
            padBottom != swipe.getPaddingBottom()
        ) {
            swipe.setPadding(padLeft, padTop, padRight, padBottom);
        }
        if (barsDrawable != null) {
            barsDrawable.setTopHeight(padTop);
        }
    }

    private void applyTheme(int top, int bottom) {
        topColor = top;
        bottomColor = bottom;
        if (barsDrawable != null) {
            barsDrawable.setColors(top, bottom);
        }
        Window window = getActivity().getWindow();
        if (Build.VERSION.SDK_INT < 35) {
            // From Android 15 the bars are transparent and the container paints behind them.
            window.setStatusBarColor(top);
            window.setNavigationBarColor(bottom);
        }
        WindowInsetsControllerCompat controller = WindowCompat.getInsetsController(window, window.getDecorView());
        controller.setAppearanceLightStatusBars(isLight(top));
        controller.setAppearanceLightNavigationBars(isLight(bottom));
    }

    private static boolean isLight(int color) {
        double luminance = (0.299 * Color.red(color) + 0.587 * Color.green(color) + 0.114 * Color.blue(color)) / 255.0;
        return luminance > 0.6;
    }

    private static int parseColor(String value, int fallback) {
        if (value == null || value.trim().isEmpty()) {
            return fallback;
        }
        try {
            return Color.parseColor(value.trim());
        } catch (IllegalArgumentException e) {
            return fallback;
        }
    }

    // ------------------------------------------------------------------ back button

    private void installBackHandler(final AppCompatActivity activity) {
        activity.getOnBackPressedDispatcher().addCallback(activity, new OnBackPressedCallback(true) {
            @Override
            public void handleOnBackPressed() {
                WebView webView = getBridge().getWebView();
                if (canGoBackInSite(webView)) {
                    webView.goBack();
                    return;
                }
                long now = SystemClock.elapsedRealtime();
                if (now - lastBackPress <= EXIT_WINDOW_MS) {
                    lastBackPress = 0L;
                    // Leave the app but keep the page and the login in memory.
                    activity.moveTaskToBack(true);
                } else {
                    lastBackPress = now;
                    Toast.makeText(activity, exitMessage, Toast.LENGTH_SHORT).show();
                }
            }
        });
    }

    /** True when "back" should go to the previous website page (never to the local shell pages). */
    private boolean canGoBackInSite(WebView webView) {
        if (webView == null || !webView.canGoBack() || isLocalUrl(webView.getUrl())) {
            return false;
        }
        try {
            WebBackForwardList history = webView.copyBackForwardList();
            int current = history.getCurrentIndex();
            if (current <= 0) {
                return false;
            }
            String previous = history.getItemAtIndex(current - 1).getUrl();
            return !isLocalUrl(previous);
        } catch (Exception e) {
            return true;
        }
    }

    // ------------------------------------------------------------------ links

    private boolean isAllowedUrl(String url) {
        if (url == null) {
            return false;
        }
        try {
            Uri uri = Uri.parse(url);
            String host = uri.getHost();
            return "https".equalsIgnoreCase(uri.getScheme()) && host != null && allowedHosts.contains(host.toLowerCase(Locale.ROOT));
        } catch (Exception e) {
            return false;
        }
    }

    private boolean isLocalUrl(String url) {
        if (url == null) {
            return true;
        }
        try {
            String local = getBridge().getLocalUrl();
            if (local != null && url.startsWith(local)) {
                return true;
            }
            String host = Uri.parse(url).getHost();
            return host == null || "localhost".equalsIgnoreCase(host);
        } catch (Exception e) {
            return false;
        }
    }

    /** Opens https://bill.bwpexperts.com/... links (Android App Links) inside the app. */
    private void openDeepLink(Intent intent, boolean coldStart) {
        if (intent == null || !Intent.ACTION_VIEW.equals(intent.getAction()) || intent.getData() == null) {
            return;
        }
        final String url = intent.getData().toString();
        if (!isAllowedUrl(url)) {
            return;
        }
        final WebView webView = getBridge().getWebView();
        // On a cold start this runs right after the launch screen was requested and replaces it.
        webView.post(() -> webView.loadUrl(url));
        if (coldStart) {
            lastUrl = url;
        }
    }

    private void openExternally(String url) {
        try {
            Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            getContext().startActivity(intent);
        } catch (Exception e) {
            toast("No app found to open this link");
        }
    }

    // ------------------------------------------------------------------ downloads

    private void installDownloadListener(final WebView webView) {
        webView.setDownloadListener((url, userAgent, contentDisposition, mimeType, contentLength) -> {
            if (url == null) {
                return;
            }
            boolean inPage = url.startsWith("blob:") || url.startsWith("data:");
            if (!inPage && !isAllowedUrl(url)) {
                // A file on another website: the phone's browser downloads it.
                openExternally(url);
                return;
            }
            String name = inPage ? "" : URLUtil.guessFileName(url, contentDisposition, mimeType);
            // The page fetches the file with the user's session and calls saveFile() below.
            String script =
                "(function(){" +
                "if(!window.__bwp){" + "try{" + bridgeScript + "}catch(e){}" + "}" +
                "if(window.__bwp){window.__bwp.download(" +
                JSONObject.quote(url) + "," + JSONObject.quote(name) + "," + JSONObject.quote(mimeType == null ? "" : mimeType) +
                ");}" +
                "})();";
            main.post(() -> webView.evaluateJavascript(script, null));
        });
    }

    private void doSaveFile(final NativeCall call) {
        String data = call.getString("data");
        if (data == null) {
            call.reject("No file data");
            return;
        }
        final String name = safeFileName(call.getString("name", "download"));
        final String mime = resolveMime(call.getString("mime", ""), name);
        try {
            File dir = new File(getContext().getCacheDir(), DOWNLOAD_DIR);
            if (!dir.exists() && !dir.mkdirs()) {
                call.reject("Could not create the download folder");
                return;
            }
            deleteOldFiles(dir);
            final File file = new File(dir, name);
            try (FileOutputStream out = new FileOutputStream(file)) {
                out.write(Base64.decode(data, Base64.DEFAULT));
            }
            final boolean savedToDownloads = copyToDownloads(file, name, mime);
            getActivity().runOnUiThread(() -> showDownloadDialog(file, name, mime, savedToDownloads));
            JSObject result = new JSObject();
            result.put("name", name);
            result.put("savedToDownloads", savedToDownloads);
            call.resolve(result);
        } catch (Exception e) {
            Log.e(TAG, "saveFile failed", e);
            call.reject("Could not save the file", e);
        }
    }

    /** Folder inside the public Downloads folder, named after the app. */
    private String downloadFolderName() {
        String folder = safeFileName(appName).replace('.', ' ').trim();
        return folder.isEmpty() ? "App" : folder;
    }

    /** Android 10+: copy into the public "Download/<app name>" folder. No storage permission needed. */
    private boolean copyToDownloads(File file, String name, String mime) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return false;
        }
        ContentResolver resolver = getContext().getContentResolver();
        Uri target = null;
        try {
            ContentValues values = new ContentValues();
            values.put(MediaStore.MediaColumns.DISPLAY_NAME, name);
            values.put(MediaStore.MediaColumns.MIME_TYPE, mime);
            values.put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/" + downloadFolderName());
            values.put(MediaStore.MediaColumns.IS_PENDING, 1);
            target = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values);
            if (target == null) {
                return false;
            }
            try (InputStream in = new FileInputStream(file); OutputStream out = resolver.openOutputStream(target)) {
                if (out == null) {
                    throw new IllegalStateException("No output stream");
                }
                byte[] buffer = new byte[16384];
                int read;
                while ((read = in.read(buffer)) != -1) {
                    out.write(buffer, 0, read);
                }
            }
            ContentValues done = new ContentValues();
            done.put(MediaStore.MediaColumns.IS_PENDING, 0);
            resolver.update(target, done, null, null);
            return true;
        } catch (Exception e) {
            Log.w(TAG, "Could not copy to Downloads", e);
            if (target != null) {
                try {
                    resolver.delete(target, null, null);
                } catch (Exception ignored) {
                    // nothing else to clean up
                }
            }
            return false;
        }
    }

    private void showDownloadDialog(final File file, final String name, final String mime, boolean savedToDownloads) {
        AppCompatActivity activity = getActivity();
        if (activity == null || activity.isFinishing()) {
            return;
        }
        String message = savedToDownloads ? "Saved to Downloads / " + downloadFolderName() + "." : "The file is ready.";
        new AlertDialog.Builder(activity)
            .setTitle(name)
            .setMessage(message)
            .setPositiveButton("Open", (dialog, which) -> openFile(file, mime))
            .setNeutralButton("Share", (dialog, which) -> shareFile(file, mime))
            .setNegativeButton("Close", null)
            .show();
    }

    private Uri uriFor(File file) {
        return FileProvider.getUriForFile(getContext(), getContext().getPackageName() + ".bwpfiles", file);
    }

    private void openFile(File file, String mime) {
        try {
            Uri uri = uriFor(file);
            Intent intent = new Intent(Intent.ACTION_VIEW);
            intent.setDataAndType(uri, mime);
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            getActivity().startActivity(intent);
        } catch (ActivityNotFoundException e) {
            toast("No app installed to open this file. Use Share instead.");
            shareFile(file, mime);
        } catch (Exception e) {
            Log.e(TAG, "openFile failed", e);
            toast("Could not open the file");
        }
    }

    private void shareFile(File file, String mime) {
        try {
            Uri uri = uriFor(file);
            Intent send = new Intent(Intent.ACTION_SEND);
            send.setType(mime);
            send.putExtra(Intent.EXTRA_STREAM, uri);
            send.setClipData(ClipData.newRawUri(file.getName(), uri));
            send.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            getActivity().startActivity(Intent.createChooser(send, "Share " + file.getName()));
        } catch (Exception e) {
            Log.e(TAG, "shareFile failed", e);
            toast("Could not share the file");
        }
    }

    private static String safeFileName(String name) {
        String safe = name == null ? "" : name.replaceAll("[\\\\/:*?\"<>|\\p{Cntrl}]+", "_").trim();
        while (safe.startsWith(".")) {
            safe = safe.substring(1);
        }
        if (safe.isEmpty()) {
            safe = "download";
        }
        if (safe.length() > 120) {
            safe = safe.substring(safe.length() - 120);
        }
        return safe;
    }

    private static String resolveMime(String mime, String name) {
        String clean = mime == null ? "" : mime.trim().toLowerCase(Locale.ROOT);
        if (!clean.isEmpty() && !"application/octet-stream".equals(clean) && !"binary/octet-stream".equals(clean)) {
            return clean;
        }
        int dot = name.lastIndexOf('.');
        if (dot >= 0 && dot < name.length() - 1) {
            String guessed = MimeTypeMap.getSingleton().getMimeTypeFromExtension(name.substring(dot + 1).toLowerCase(Locale.ROOT));
            if (guessed != null) {
                return guessed;
            }
        }
        return "application/octet-stream";
    }

    private static void deleteOldFiles(File dir) {
        File[] files = dir.listFiles();
        if (files == null) {
            return;
        }
        long cutoff = System.currentTimeMillis() - DOWNLOAD_MAX_AGE_MS;
        for (File file : files) {
            if (file.isFile() && file.lastModified() < cutoff) {
                //noinspection ResultOfMethodCallIgnored
                file.delete();
            }
        }
    }

    // ------------------------------------------------------------------ file inputs (camera / gallery / files)

    private void installFileChooser(final WebView webView) {
        // Must be created while the activity is being created (it registers a result callback).
        chromeClient = new BwpChromeClient(getBridge());
        // Capacitor installs its own client right after the plugins load; replace it afterwards.
        main.post(() -> {
            try {
                webView.setWebChromeClient(chromeClient);
            } catch (Throwable t) {
                Log.e(TAG, "Could not install the file chooser", t);
            }
        });
    }

    // ------------------------------------------------------------------ methods called from bwp-bridge.js

    private void doPrintPage(final NativeCall call) {
        final String title = call.getString("title", appName);
        getActivity().runOnUiThread(() -> {
            try {
                PrintManager manager = (PrintManager) getActivity().getSystemService(Context.PRINT_SERVICE);
                if (manager == null) {
                    call.reject("Printing is not available on this device");
                    return;
                }
                String job = safeFileName(title);
                manager.print(job, getBridge().getWebView().createPrintDocumentAdapter(job), new PrintAttributes.Builder().build());
                call.resolve();
            } catch (Exception e) {
                call.reject("Could not start printing", e);
            }
        });
    }

    private void doShare(final NativeCall call) {
        String title = call.getString("title", "");
        String text = call.getString("text", "");
        String url = call.getString("url", "");
        StringBuilder body = new StringBuilder();
        if (text != null && !text.isEmpty()) {
            body.append(text);
        }
        if (url != null && !url.isEmpty()) {
            if (body.length() > 0) {
                body.append("\n");
            }
            body.append(url);
        }
        if (body.length() == 0) {
            call.reject("Nothing to share");
            return;
        }
        final Intent send = new Intent(Intent.ACTION_SEND);
        send.setType("text/plain");
        send.putExtra(Intent.EXTRA_TEXT, body.toString());
        if (title != null && !title.isEmpty()) {
            send.putExtra(Intent.EXTRA_SUBJECT, title);
            send.putExtra(Intent.EXTRA_TITLE, title);
        }
        getActivity().runOnUiThread(() -> {
            try {
                getActivity().startActivity(Intent.createChooser(send, null));
                call.resolve();
            } catch (Exception e) {
                call.reject("Could not open the share sheet", e);
            }
        });
    }

    private void doSetTheme(final NativeCall call) {
        final int top = parseColor(call.getString("top"), topColor);
        final int bottom = parseColor(call.getString("bottom"), bottomColor);
        getActivity().runOnUiThread(() -> {
            // Ignore late answers from a page that is no longer showing.
            if (!isLocalUrl(getBridge().getWebView().getUrl())) {
                applyTheme(top, bottom);
            }
            call.resolve();
        });
    }

    private void doSetRefreshAllowed(final NativeCall call) {
        refreshAllowedByPage = call.getBoolean("allowed", true);
        call.resolve();
    }

    private void doPageReady(final NativeCall call) {
        main.removeCallbacks(stopRefreshing);
        main.post(stopRefreshing);
        call.resolve();
    }

    /**
     * Screenshot / screen-recording protection. Off by default.
     * To protect specific screens, list their path prefixes in src/app-config.json -> secureScreenPaths.
     */
    private void doSetScreenSecure(final NativeCall call) {
        final boolean enabled = call.getBoolean("enabled", false);
        getActivity().runOnUiThread(() -> {
            Window window = getActivity().getWindow();
            if (enabled) {
                window.addFlags(WindowManager.LayoutParams.FLAG_SECURE);
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE);
            }
            call.resolve();
        });
    }

    private void doOpenExternal(final NativeCall call) {
        String url = call.getString("url", "");
        Uri uri = url == null ? null : Uri.parse(url);
        String scheme = uri == null || uri.getScheme() == null ? "" : uri.getScheme().toLowerCase(Locale.ROOT);
        List<String> safeSchemes = new ArrayList<>();
        safeSchemes.add("https");
        safeSchemes.add("http");
        safeSchemes.add("tel");
        safeSchemes.add("mailto");
        safeSchemes.add("sms");
        safeSchemes.add("geo");
        safeSchemes.add("whatsapp");
        if (!safeSchemes.contains(scheme)) {
            call.reject("This kind of link is not allowed");
            return;
        }
        openExternally(url);
        call.resolve();
    }

    private void doGetLastUrl(final NativeCall call) {
        JSObject result = new JSObject();
        result.put("url", lastUrl != null ? lastUrl : homeUrl);
        call.resolve(result);
    }

    private void toast(final String message) {
        main.post(() -> Toast.makeText(getContext(), message, Toast.LENGTH_SHORT).show());
    }
}
