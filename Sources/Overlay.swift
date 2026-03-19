import Cocoa
import WebKit

// ═══════════════════════════════════════════════════════════════════
// Violet Flame Overlay — WebView with Canvas plasma waves
// Organic, living, voice-reactive flames on screen edges
// ═══════════════════════════════════════════════════════════════════

class PlasmaOverlayWindow: NSWindow {
    var webView: WKWebView!
    var audioTimer: Timer?
    var audioLevel: Float = 0  // Set externally by recorder
    var isShowing = false

    init() {
        guard let screen = NSScreen.main else {
            super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false); return
        }
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = .screenSaver; isOpaque = false; backgroundColor = .clear
        ignoresMouseEvents = true; hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        // WKWebView with TRULY transparent background
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        webView = WKWebView(frame: screen.frame, configuration: config)

        // Multiple transparency methods for reliability
        webView.setValue(false, forKey: "drawsBackground")
        if #available(macOS 12.0, *) {
            webView.underPageBackgroundColor = .clear
        }
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        webView.layer?.isOpaque = false
        contentView = webView

        // Adapt to screen changes (switching between MacBook ↔ external display)
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.adaptToScreen()
        }

        // Load overlay HTML
        if let path = Bundle.main.path(forResource: "overlay", ofType: "html") {
            webView.loadFileURL(URL(fileURLWithPath: path), allowingReadAccessTo: URL(fileURLWithPath: path).deletingLastPathComponent())
            log("🎨 Overlay HTML loaded")
        } else {
            log("⚠️ overlay.html not found")
        }
    }

    func adaptToScreen() {
        guard let screen = NSScreen.main else { return }
        setFrame(screen.frame, display: true)
        webView.frame = NSRect(origin: .zero, size: screen.frame.size)
        log("🖥️ Overlay adapted to screen: \(Int(screen.frame.width))x\(Int(screen.frame.height))")
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
}
