package com.bwpexperts.billing.nativeplugin;

import com.getcapacitor.JSObject;

/**
 * One request from the page to the native side.
 * It arrives either through the BWP message channel (the billing website) or through the
 * Capacitor bridge (the local launch / error screens), and is answered the same way.
 */
interface NativeCall {
    String getString(String key);

    String getString(String key, String fallback);

    boolean getBoolean(String key, boolean fallback);

    void resolve();

    void resolve(JSObject result);

    void reject(String message);

    void reject(String message, Exception cause);
}
