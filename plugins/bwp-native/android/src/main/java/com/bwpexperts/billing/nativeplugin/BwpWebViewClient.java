package com.bwpexperts.billing.nativeplugin;

import android.net.http.SslError;
import android.webkit.SslErrorHandler;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;

import com.getcapacitor.Bridge;
import com.getcapacitor.BridgeWebViewClient;

/**
 * Decides when the "could not connect" screen is shown.
 *
 * Capacitor's own client shows it for every problem with the main page, including pages the
 * server answers with an error status (403, 404, 500...). That hides the server's real page and
 * makes a working connection look broken. This client behaves like a browser:
 *
 *  - connection problems (no network, DNS, timeout, TLS) -> the connection screen, with the
 *    technical reason so it can be reported
 *  - pages with an HTTP error status                     -> shown as the server sent them
 *  - certificate errors                                  -> always refused, never bypassed
 */
class BwpWebViewClient extends BridgeWebViewClient {

    /** Receives the reason of a failed main-page load. */
    interface Reporter {
        void onMainPageFailed(String detail, String url);

        boolean isOwnSite(String url);

        String errorPageUrl();
    }

    private final Reporter reporter;

    BwpWebViewClient(Bridge bridge, Reporter reporter) {
        super(bridge);
        this.reporter = reporter;
    }

    @Override
    public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
        if (request != null && request.isForMainFrame() && error != null) {
            String url = request.getUrl() != null ? request.getUrl().toString() : "";
            reporter.onMainPageFailed(error.getDescription() + " (" + error.getErrorCode() + ")", url);
        }
        // Capacitor notifies its listeners and loads the error page for the main frame.
        super.onReceivedError(view, request, error);
    }

    @Override
    public void onReceivedHttpError(WebView view, WebResourceRequest request, WebResourceResponse errorResponse) {
        // Intentionally not passed on: the server's own page (login redirect, 403, 404, 500...)
        // stays on screen, exactly as in a browser.
    }

    @Override
    public void onReceivedSslError(WebView view, SslErrorHandler handler, SslError error) {
        // Never continue with a certificate that cannot be verified.
        handler.cancel();
        String url = error != null ? error.getUrl() : null;
        if (url != null && reporter.isOwnSite(url)) {
            reporter.onMainPageFailed("Certificate problem (SSL error " + error.getPrimaryError() + ")", url);
            String errorPage = reporter.errorPageUrl();
            if (errorPage != null) {
                view.loadUrl(errorPage);
            }
        }
    }
}
