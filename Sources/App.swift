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
    var preferencesWindow: NSWindow?

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
        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)
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

    // ─── Preferences Window ───────────────────────────────────────

    private static let languages: [(code: String, label: String)] = [
        ("auto", "Auto-detect"),
        ("ru", "Russian"),
        ("en", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("zh", "Chinese"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
    ]

    @objc func showPreferences() {
        // If window already exists, just bring it forward
        if let w = preferencesWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Ember Preferences"
        window.center()
        window.isReleasedWhenClosed = false

        // ── API Key ──
        let keyLabel = NSTextField(labelWithString: "API Key:")
        keyLabel.font = .systemFont(ofSize: 13, weight: .medium)

        let keyField = NSSecureTextField()
        keyField.placeholderString = "gsk_..."
        keyField.stringValue = config.groqKey
        keyField.translatesAutoresizingMaskIntoConstraints = false

        let keyRow = NSStackView(views: [keyLabel, keyField])
        keyRow.orientation = .horizontal
        keyRow.spacing = 10
        keyRow.alignment = .centerY
        keyLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        keyField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // ── Language ──
        let langLabel = NSTextField(labelWithString: "Language:")
        langLabel.font = .systemFont(ofSize: 13, weight: .medium)

        let langPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for lang in Self.languages {
            langPopup.addItem(withTitle: lang.label)
            langPopup.lastItem?.representedObject = lang.code
        }
        // Select current language
        if let idx = Self.languages.firstIndex(where: { $0.code == config.language }) {
            langPopup.selectItem(at: idx)
        }
        langPopup.translatesAutoresizingMaskIntoConstraints = false

        let langRow = NSStackView(views: [langLabel, langPopup])
        langRow.orientation = .horizontal
        langRow.spacing = 10
        langRow.alignment = .centerY
        langLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        langPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // ── Align labels ──
        keyLabel.widthAnchor.constraint(equalTo: langLabel.widthAnchor).isActive = true

        // ── Get API Key link ──
        let linkButton = NSButton(title: "Get API Key at console.groq.com", target: nil, action: nil)
        linkButton.isBordered = false
        linkButton.attributedTitle = NSAttributedString(
            string: "Get API Key at console.groq.com",
            attributes: [
                .foregroundColor: NSColor.linkColor,
                .font: NSFont.systemFont(ofSize: 12),
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
        )
        linkButton.target = self
        linkButton.action = #selector(openGroqConsole)

        // ── Buttons ──
        let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}" // Escape

        let saveButton = NSButton(title: "Save", target: nil, action: nil)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r" // Enter

        let buttonRow = NSStackView(views: [cancelButton, saveButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10

        // ── Main stack ──
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [keyRow, langRow, linkButton, spacer, buttonRow])
        stack.orientation = .vertical
        stack.spacing = 16
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false

        window.contentView = stack

        // ── Constraints ──
        NSLayoutConstraint.activate([
            keyRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 24),
            keyRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -24),
            langRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 24),
            langRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -24),
            buttonRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -24),
        ])

        // ── Actions (closures via target-action) ──
        cancelButton.target = self
        cancelButton.action = #selector(preferencesCancel)

        // Save needs references to the fields — store them via tags + associated approach
        // Using a simpler approach: store references and use a single save action
        self.preferencesWindow = window
        self._prefsKeyField = keyField
        self._prefsLangPopup = langPopup

        saveButton.target = self
        saveButton.action = #selector(preferencesSave)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Stored references for preferences fields (weak not needed — window holds them)
    private var _prefsKeyField: NSSecureTextField?
    private var _prefsLangPopup: NSPopUpButton?

    @objc private func preferencesSave() {
        guard let keyField = _prefsKeyField, let langPopup = _prefsLangPopup else { return }
        let key = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let langCode = (langPopup.selectedItem?.representedObject as? String) ?? "auto"

        Config.save(groqKey: key, language: langCode)
        config = Config.load()

        preferencesWindow?.close()
        preferencesWindow = nil
        _prefsKeyField = nil
        _prefsLangPopup = nil
    }

    @objc private func preferencesCancel() {
        preferencesWindow?.close()
        preferencesWindow = nil
        _prefsKeyField = nil
        _prefsLangPopup = nil
    }

    @objc private func openGroqConsole() {
        if let url = URL(string: "https://console.groq.com/keys") {
            NSWorkspace.shared.open(url)
        }
    }

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
