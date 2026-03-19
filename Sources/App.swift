import Cocoa
import Carbon.HIToolbox
import Sparkle

// ═══════════════════════════════════════════════════════════════════
//  Ember v1.0.0 — Voice-to-text for macOS
//  ` record → Groq Whisper STT → Groq LLM fix → auto-paste
// ═══════════════════════════════════════════════════════════════════

// ═══════════════════════════════════════════════════════════════════
// Carbon Hotkey — works WITHOUT Accessibility permission!
// ═══════════════════════════════════════════════════════════════════

var tildeHotkeyRef: EventHotKeyRef?
var escapeHotkeyRef: EventHotKeyRef?

// Forward reference — set by AppDelegate on launch
weak var appDelegateRef: AppDelegate?

func carbonHotkeyHandler(nextHandler: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    var hotkeyID = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                      nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID)

    DispatchQueue.main.async {
        guard let del = appDelegateRef else { return }
        switch hotkeyID.id {
        case 1: // Tilde
            if del.recorder.isRecording { del.recorder.stopRecording() }
            else if !del.recorder.isStopping { del.recorder.startRecording() }
        case 2: // Escape (only during recording)
            if del.recorder.isRecording { del.recorder.cancelRecording() }
        default: break
        }
    }

    return noErr
}

func setupCarbonHotkeys() -> Bool {
    // Install Carbon event handler
    var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

    var handlerRef: EventHandlerRef?
    let status = InstallEventHandler(
        GetApplicationEventTarget(),
        carbonHotkeyHandler,
        1, &eventType, nil, &handlerRef
    )

    guard status == noErr else {
        log("❌ Failed to install Carbon event handler: \(status)")
        return false
    }

    // Register Tilde (keycode 50, no modifiers)
    let tildeID = EventHotKeyID(signature: OSType(0x44494354), id: 1) // "EMBR" + 1
    let tildeStatus = RegisterEventHotKey(
        UInt32(kVK_ANSI_Grave), 0, tildeID,
        GetApplicationEventTarget(), 0, &tildeHotkeyRef
    )

    if tildeStatus != noErr {
        log("⚠️ Failed to register tilde hotkey: \(tildeStatus)")
        // Try NSEvent as fallback
        setupNSEventFallback()
        return true
    }

    // Register Escape (keycode 53, no modifiers)
    let escID = EventHotKeyID(signature: OSType(0x44494354), id: 2) // "EMBR" + 2
    RegisterEventHotKey(UInt32(kVK_Escape), 0, escID, GetApplicationEventTarget(), 0, &escapeHotkeyRef)

    log("✅ Carbon hotkeys registered (tilde + escape)")
    return true
}

func setupNSEventFallback() {
    log("⚠️ Using NSEvent fallback for hotkeys")
    NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
        if event.keyCode == 50 && !event.isARepeat { // tilde
            DispatchQueue.main.async {
                guard let del = appDelegateRef else { return }
                if del.recorder.isRecording { del.recorder.stopRecording() }
                else if !del.recorder.isStopping { del.recorder.startRecording() }
            }
        } else if event.keyCode == 53 && !event.isARepeat { // escape
            DispatchQueue.main.async {
                guard let del = appDelegateRef else { return }
                if del.recorder.isRecording { del.recorder.cancelRecording() }
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// App Delegate
// ═══════════════════════════════════════════════════════════════════

class AppDelegate: NSObject, NSApplicationDelegate, RecorderDelegate {
    var statusItem: NSStatusItem!
    var toggleMenuItem: NSMenuItem!
    var overlayWindow: PlasmaOverlayWindow?
    var updaterController: SPUStandardUpdaterController!
    let recorder = Recorder()

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("🎤 Ember v1.0.0 starting...")
        appDelegateRef = self
        recorder.delegate = self

        // Check Accessibility (for CGEvent typing — hotkey works without it)
        if !AXIsProcessTrusted() {
            log("⚠️ Accessibility not granted — text paste may not auto-type")
            log("   Add Ember.app in System Settings → Accessibility")
            // Request permission prompt
            let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(opts)
        } else {
            log("✅ Accessibility granted")
        }

        // First-run: prompt for API key if missing
        if config.groqKey.isEmpty {
            showApiKeyDialog()
        }

        // Sparkle auto-updater
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

        // Menu bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Ember")
        }

        toggleMenuItem = NSMenuItem(title: "Start Recording (`)", action: #selector(toggleRecording), keyEquivalent: "")
        toggleMenuItem.target = self
        let menu = NSMenu()
        menu.addItem(toggleMenuItem)
        menu.addItem(.separator())
        let updateItem = NSMenuItem(title: "Check for Updates...", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        updateItem.target = updaterController
        menu.addItem(updateItem)
        let hi = NSMenuItem(title: "History...", action: #selector(openHistory), keyEquivalent: "h"); hi.target = self; menu.addItem(hi)
        menu.addItem(.separator())
        let qi = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"); qi.target = self; menu.addItem(qi)
        statusItem.menu = menu

        overlayWindow = PlasmaOverlayWindow()

        // Carbon hotkeys — no Accessibility needed!
        if !setupCarbonHotkeys() {
            setupNSEventFallback()
        }
    }

    func setRecordingState(_ recording: Bool) {
        DispatchQueue.main.async { [self] in
            if let button = statusItem.button {
                if recording {
                    button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Recording")
                } else {
                    button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Ember")
                }
            }
            toggleMenuItem.title = recording ? "Stop Recording (`)" : "Start Recording (`)"
        }
    }

    func setProcessingState(_ processing: Bool) {
        DispatchQueue.main.async { [self] in
            if let button = statusItem.button {
                if processing {
                    button.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Processing")
                } else {
                    button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Ember")
                }
            }
        }
    }

    @objc func toggleRecording() {
        statusItem.menu?.cancelTrackingWithoutAnimation()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in
            if recorder.isRecording { recorder.stopRecording() }
            else if !recorder.isStopping { recorder.startRecording() }
        }
    }

    @objc func openHistory() { NSWorkspace.shared.open(URL(fileURLWithPath: historyDir)) }
    @objc func quitApp() { if recorder.isRecording { recorder.stopRecording() }; NSApp.terminate(nil) }

    // ─── RecorderDelegate ─────────────────────────────────────────
    func recorderDidStartRecording() {
        setRecordingState(true)
        overlayWindow?.show()
    }

    func recorderDidStopRecording() {
        setRecordingState(false)
    }

    func recorderDidStartProcessing() {
        setProcessingState(true)
        overlayWindow?.webView.evaluateJavaScript("window.setProcessing(true)", completionHandler: nil)
    }

    func recorderDidFinishProcessing(text: String) {
        setProcessingState(false)
        overlayWindow?.webView.evaluateJavaScript("window.setProcessing(false)", completionHandler: nil)
        overlayWindow?.hide()

        guard !text.isEmpty else { return }

        let pb = NSPasteboard.general; pb.clearContents()
        pb.setString(text, forType: .string)

        // Auto-paste: Cmd+V
        usleep(80_000)
        let src = CGEventSource(stateID: .combinedSessionState)
        if let d = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true) {
            d.flags = .maskCommand; d.post(tap: .cghidEventTap)
        }
        usleep(20_000)
        if let u = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false) {
            u.flags = .maskCommand; u.post(tap: .cghidEventTap)
        }
        log("📋 Pasted \(text.count) chars")
    }

    func recorderDidCancel() {
        setRecordingState(false)
        overlayWindow?.hide()
    }

    func recorderDidUpdateAudioLevel(_ level: Float) {
        overlayWindow?.audioLevel = level
    }
}

// ─── Entry Point ────────────────────────────────────────────────
@main
enum EmberApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
