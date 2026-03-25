import Cocoa
import WebKit

// ═══════════════════════════════════════════════════════════════════
// Violet Flame Overlay — WebView with Canvas plasma waves
// Organic, living, voice-reactive flames on screen edges
// ═══════════════════════════════════════════════════════════════════

class PlasmaOverlayWindow: NSWindow, WKNavigationDelegate {
    var webView: WKWebView!
    var audioTimer: Timer?
    var audioLevel: Float = 0  // Set externally by recorder
    var isShowing = false

    // D8: Find the screen that contains the current mouse cursor
    static func screenWithCursor() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            if screen.frame.contains(mouseLocation) { return screen }
        }
        return NSScreen.main ?? NSScreen.screens.first!
    }

    init() {
        let screen = PlasmaOverlayWindow.screenWithCursor()
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver; isOpaque = false; backgroundColor = .clear
        ignoresMouseEvents = true; hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // WKWebView with TRULY transparent background
        let webConfig = WKWebViewConfiguration()
        webConfig.preferences.setValue(true, forKey: "developerExtrasEnabled")
        webView = WKWebView(frame: screen.frame, configuration: webConfig)

        // Multiple transparency methods for reliability
        webView.setValue(false, forKey: "drawsBackground")
        if #available(macOS 12.0, *) {
            webView.underPageBackgroundColor = .clear
        }
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        webView.layer?.isOpaque = false
        contentView = webView

        // Hide webView until theme HTML fully loads (prevents yellow/white flash)
        webView.isHidden = true
        webView.navigationDelegate = self

        // Adapt to screen changes (switching between MacBook ↔ external display)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.adaptToScreen()
        }

        loadTheme(config.theme)
    }

    func adaptToScreen() {
        // D8: Use screen with cursor for multi-display support
        let screen = PlasmaOverlayWindow.screenWithCursor()
        setFrame(screen.frame, display: true)
        webView.frame = NSRect(origin: .zero, size: screen.frame.size)
        log("🖥️ Overlay adapted to screen: \(Int(screen.frame.width))x\(Int(screen.frame.height))")
    }

    // Reveal webView when theme HTML finishes loading (prevents flash of default BG)
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.isHidden = false
    }

    func loadTheme(_ name: String) {
        let themesURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/themes")
        var themeURL = themesURL.appendingPathComponent("\(name).html")
        if !FileManager.default.fileExists(atPath: themeURL.path) {
            log("⚠️ Theme '\(name)' not found, falling back to violet-flame")
            themeURL = themesURL.appendingPathComponent("violet-flame.html")
        }
        guard FileManager.default.fileExists(atPath: themeURL.path) else {
            log("❌ No theme files found"); return
        }
        webView.loadFileURL(themeURL, allowingReadAccessTo: themesURL)
        log("🎨 Theme loaded: \(name)")
    }

    static func availableThemes() -> [String] {
        let themesURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/themes")
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: themesURL.path) else { return [] }
        return files.filter { $0.hasSuffix(".html") }
            .map { $0.replacingOccurrences(of: ".html", with: "") }
            .sorted()
    }

    func show() {
        adaptToScreen()
        if !isShowing {
            orderFront(nil); alphaValue = 0
            NSAnimationContext.runAnimationGroup { $0.duration = 0.3; self.animator().alphaValue = 1 }
            isShowing = true
        }
        webView.evaluateJavaScript("window.setActive(true)", completionHandler: nil)

        // Send audio levels to WebView at 30fps
        if audioTimer == nil {
            audioTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.webView.evaluateJavaScript("window.setAudioLevel(\(self.audioLevel))", completionHandler: nil)
            }
        }
    }

    func hide() {
        webView.evaluateJavaScript("window.setActive(false)", completionHandler: nil)
        audioTimer?.invalidate(); audioTimer = nil
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.4; self.animator().alphaValue = 0 }, completionHandler: {
            self.orderOut(nil)
            self.isShowing = false
        })
    }

    func flashError() {
        // Show overlay if not already visible
        if !isShowing {
            adaptToScreen()
            orderFront(nil)
            alphaValue = 1
            isShowing = true
        }
        webView.evaluateJavaScript("window.setError(true)", completionHandler: nil)
        // Hide after 0.8s
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.webView.evaluateJavaScript("window.setError(false)", completionHandler: nil)
            self?.hide()
        }
    }
}
