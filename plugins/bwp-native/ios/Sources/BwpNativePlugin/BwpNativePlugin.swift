import Foundation
import UIKit
import WebKit
import QuickLook
import Capacitor

/**
 BWP Billing - native features for iOS.

 Everything that makes the app more than a plain web view lives in this plugin, so the
 generated Capacitor project (AppDelegate, storyboard) stays untouched:

  - injects src/bwp-bridge.js into the billing website
  - pull-to-refresh and the swipe-back gesture
  - status-bar strip that follows the page colour (notch / Dynamic Island safe)
  - downloads: preview with Share / Save to Files / Print (Quick Look)
  - print (AirPrint dialog) and share sheet
  - Universal Links (https://bill.bwpexperts.com/...)

 */
@objc(BwpNativePlugin)
public class BwpNativePlugin: CAPPlugin, CAPBridgedPlugin, QLPreviewControllerDataSource {

    public let identifier = "BwpNativePlugin"
    public let jsName = "BwpNative"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "saveFile", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "printPage", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "share", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setTheme", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setRefreshAllowed", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "pageReady", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setScreenSecure", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "openExternal", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getLastUrl", returnType: CAPPluginReturnPromise)
    ]

    // Configuration (capacitor.config.ts -> plugins.BwpNative)
    private var homeUrl = "https://bill.bwpexperts.com/"
    private var allowedHosts: [String] = ["bill.bwpexperts.com"]
    private var brandColor = UIColor(red: 1 / 255, green: 79 / 255, blue: 74 / 255, alpha: 1)
    private var shellColor = UIColor.white
    private var pullToRefresh = true
    private var downloadExtensions: [String] = ["pdf", "csv", "xls", "xlsx", "doc", "docx", "zip"]
    private var secureScreenPaths: [String] = []

    // State
    private var lastUrl: String?
    private var statusStrip: UIView?
    private var refreshControl: UIRefreshControl?
    private var observations: [NSKeyValueObservation] = []
    private var previewFile: URL?
    private var isSetUp = false

    // MARK: - Lifecycle

    override public func load() {
        readConfig()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUniversalLink(_:)),
            name: Notification.Name.capacitorOpenUniversalLink,
            object: nil
        )
        if Thread.isMainThread {
            setUp(attempt: 0)
        } else {
            DispatchQueue.main.async { [weak self] in self?.setUp(attempt: 0) }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func readConfig() {
        let config = getConfig()
        homeUrl = config.getString("homeUrl", homeUrl) ?? homeUrl
        pullToRefresh = config.getBoolean("pullToRefresh", true)
        if let value = config.getString("brandColor"), let color = BwpNativePlugin.color(fromHex: value) {
            brandColor = color
        }
        if let value = config.getString("backgroundColor"), let color = BwpNativePlugin.color(fromHex: value) {
            shellColor = color
        }
        let json = config.getConfigJSON()
        if let hosts = json["allowedHosts"] as? [String], !hosts.isEmpty {
            allowedHosts = hosts.map { $0.lowercased() }
        } else if let host = URL(string: homeUrl)?.host {
            allowedHosts = [host.lowercased()]
        }
        if let list = json["downloadExtensions"] as? [String] {
            downloadExtensions = list
        }
        if let list = json["secureScreenPaths"] as? [String] {
            secureScreenPaths = list
        }
    }

    private func setUp(attempt: Int) {
        guard !isSetUp else { return }
        guard let webView = bridge?.webView else {
            // The web view is created together with the bridge; retry briefly if it is not there yet.
            if attempt < 20 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.setUp(attempt: attempt + 1)
                }
            }
            return
        }
        isSetUp = true

        let scriptInstalled = installBridgeScript(webView)
        CAPLog.print("BwpNative: ready (bridge script \(scriptInstalled ? "installed" : "MISSING"))")

        // Native navigation feel: swipe from the left edge goes back.
        webView.allowsBackForwardNavigationGestures = true

        if pullToRefresh {
            webView.scrollView.bounces = true
            webView.scrollView.alwaysBounceVertical = true
            let control = UIRefreshControl()
            control.tintColor = brandColor
            control.addTarget(self, action: #selector(handleRefresh(_:)), for: .valueChanged)
            webView.scrollView.refreshControl = control
            refreshControl = control
        }

        installStatusStrip(on: webView)

        observations.append(webView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
            guard !view.isLoading else { return }
            DispatchQueue.main.async { self?.refreshControl?.endRefreshing() }
        })
        observations.append(webView.observe(\.url, options: [.new]) { [weak self] view, _ in
            let current = view.url
            DispatchQueue.main.async { self?.urlChanged(current) }
        })
    }

    // MARK: - Bridge script

    @discardableResult
    private func installBridgeScript(_ webView: WKWebView) -> Bool {
        guard
            let file = Bundle.main.url(forResource: "bwp-bridge", withExtension: "js", subdirectory: "public"),
            let source = try? String(contentsOf: file, encoding: .utf8)
        else {
            CAPLog.print("BwpNative: public/bwp-bridge.js not found in the app bundle. Run: npx cap sync ios")
            return false
        }
        let config: [String: Any] = [
            "platform": "ios",
            "homeUrl": homeUrl,
            "allowedHosts": allowedHosts,
            "pullToRefresh": pullToRefresh,
            "downloadExtensions": downloadExtensions,
            "secureScreenPaths": secureScreenPaths
        ]
        var json = "{}"
        if let data = try? JSONSerialization.data(withJSONObject: config, options: []),
           let text = String(data: data, encoding: .utf8) {
            json = text
        }
        // The script itself only runs on the allowed hosts (main frame).
        let script = WKUserScript(
            source: "window.__BWP_CONFIG__ = \(json);\n\(source)",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        webView.configuration.userContentController.addUserScript(script)
        return true
    }

    // MARK: - Status bar strip (safe area)

    private func installStatusStrip(on webView: WKWebView) {
        let strip = UIView()
        strip.translatesAutoresizingMaskIntoConstraints = false
        strip.isUserInteractionEnabled = false
        strip.backgroundColor = shellColor
        webView.addSubview(strip)
        NSLayoutConstraint.activate([
            strip.topAnchor.constraint(equalTo: webView.topAnchor),
            strip.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
            strip.trailingAnchor.constraint(equalTo: webView.trailingAnchor),
            strip.bottomAnchor.constraint(equalTo: webView.safeAreaLayoutGuide.topAnchor)
        ])
        statusStrip = strip
        applyTheme(top: shellColor)
    }

    private func applyTheme(top: UIColor) {
        statusStrip?.backgroundColor = top
        // Dark icons on a light strip, light icons on a dark strip.
        bridge?.statusBarStyle = BwpNativePlugin.isLight(top) ? .darkContent : .lightContent
    }

    private func urlChanged(_ url: URL?) {
        guard let url = url else { return }
        if isAllowed(url) {
            lastUrl = url.absoluteString
        } else if url.host == nil || url.host == "localhost" {
            // Local launch / error screen.
            applyTheme(top: shellColor)
        }
    }

    private func isAllowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return allowedHosts.contains(host)
    }

    // MARK: - Pull to refresh

    @objc private func handleRefresh(_ sender: UIRefreshControl) {
        guard let webView = bridge?.webView else {
            sender.endRefreshing()
            return
        }
        if let url = webView.url, isAllowed(url) {
            webView.reload()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak sender] in
            sender?.endRefreshing()
        }
    }

    // MARK: - Universal Links

    @objc private func handleUniversalLink(_ notification: Notification) {
        var target: URL?
        if let info = notification.object as? [String: Any] {
            if let url = info["url"] as? URL {
                target = url
            } else if let text = info["url"] as? String {
                target = URL(string: text)
            }
        }
        guard let url = target, isAllowed(url) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.bridge?.webView?.load(URLRequest(url: url))
        }
    }

    // MARK: - Methods called from bwp-bridge.js

    /// Saves a downloaded file and shows it in Quick Look (preview + Share / Save to Files / Print).
    @objc func saveFile(_ call: CAPPluginCall) {
        guard
            let encoded = call.getString("data"),
            let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters)
        else {
            call.reject("No file data")
            return
        }
        let name = BwpNativePlugin.safeFileName(call.getString("name") ?? "download")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("bwp-downloads", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: nil)
            let file = folder.appendingPathComponent(name)
            try data.write(to: file, options: .atomic)
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let presenter = self.bridge?.viewController else {
                    call.reject("The app is not ready to show the file")
                    return
                }
                self.previewFile = file
                let preview = QLPreviewController()
                preview.dataSource = self
                presenter.present(preview, animated: true, completion: nil)
                call.resolve(["name": name])
            }
        } catch {
            call.reject("Could not save the file", nil, error)
        }
    }

    public func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        return previewFile == nil ? 0 : 1
    }

    public func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        let file = previewFile ?? FileManager.default.temporaryDirectory
        return file as NSURL
    }

    @objc func printPage(_ call: CAPPluginCall) {
        let title = call.getString("title") ?? "BWP Billing"
        DispatchQueue.main.async { [weak self] in
            guard let webView = self?.bridge?.webView else {
                call.reject("Nothing to print")
                return
            }
            let info = UIPrintInfo(dictionary: nil)
            info.outputType = .general
            info.jobName = title
            let controller = UIPrintInteractionController.shared
            controller.printInfo = info
            controller.printFormatter = webView.viewPrintFormatter()
            controller.present(animated: true, completionHandler: nil)
            call.resolve()
        }
    }

    @objc func share(_ call: CAPPluginCall) {
        var items: [Any] = []
        if let text = call.getString("text"), !text.isEmpty {
            items.append(text)
        }
        if let text = call.getString("url"), !text.isEmpty, let url = URL(string: text) {
            items.append(url)
        }
        guard !items.isEmpty else {
            call.reject("Nothing to share")
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let presenter = self?.bridge?.viewController else {
                call.reject("The app is not ready to share")
                return
            }
            let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
            // iPad shows the sheet as a popover and needs an anchor.
            if let popover = sheet.popoverPresentationController {
                popover.sourceView = presenter.view
                popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            presenter.present(sheet, animated: true, completion: nil)
            call.resolve()
        }
    }

    @objc func setTheme(_ call: CAPPluginCall) {
        let top = BwpNativePlugin.color(fromHex: call.getString("top") ?? "")
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Ignore late answers from a page that is no longer showing.
            if let top = top, let url = self.bridge?.webView?.url, self.isAllowed(url) {
                self.applyTheme(top: top)
            }
            call.resolve()
        }
    }

    @objc func setRefreshAllowed(_ call: CAPPluginCall) {
        // iOS only triggers the refresh control from the top of the main page, so the
        // guard that Android needs is not required here.
        call.resolve()
    }

    @objc func pageReady(_ call: CAPPluginCall) {
        DispatchQueue.main.async { [weak self] in
            self?.refreshControl?.endRefreshing()
            call.resolve()
        }
    }

    /// Screenshot protection hook. iOS has no public switch to block screenshots; this is the
    /// single place to add a privacy cover for sensitive screens later. Off by default.
    @objc func setScreenSecure(_ call: CAPPluginCall) {
        call.resolve()
    }

    @objc func openExternal(_ call: CAPPluginCall) {
        guard
            let text = call.getString("url"),
            let url = URL(string: text),
            let scheme = url.scheme?.lowercased(),
            ["https", "http", "tel", "mailto", "sms", "whatsapp", "maps"].contains(scheme)
        else {
            call.reject("This kind of link is not allowed")
            return
        }
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            call.resolve()
        }
    }

    @objc func getLastUrl(_ call: CAPPluginCall) {
        call.resolve(["url": lastUrl ?? homeUrl])
    }

    // MARK: - Helpers

    private static func safeFileName(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "\\/:*?\"<>|").union(.controlCharacters)
        var safe = name.components(separatedBy: forbidden).joined(separator: "_").trimmingCharacters(in: .whitespaces)
        while safe.hasPrefix(".") {
            safe.removeFirst()
        }
        if safe.isEmpty {
            safe = "download"
        }
        if safe.count > 120 {
            safe = String(safe.suffix(120))
        }
        return safe
    }

    private static func color(fromHex text: String) -> UIColor? {
        var hex = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    private static func isLight(_ color: UIColor) -> Bool {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return true }
        return (0.299 * red + 0.587 * green + 0.114 * blue) > 0.6
    }
}
