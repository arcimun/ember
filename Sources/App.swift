import Cocoa
import Carbon.HIToolbox
import Sparkle
import AVFoundation

// ═══════════════════════════════════════════════════════════════════
//  Ember v1.6 — Voice-to-text for macOS
//  ` record → Groq Whisper STT → optional LLM fix → auto-paste
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
    var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    var handlerRef: EventHandlerRef?
    let status = InstallEventHandler(GetApplicationEventTarget(), carbonHotkeyHandler, 1, &eventType, nil, &handlerRef)
    guard status == noErr else {
        log("❌ Failed to install Carbon event handler: \(status)")
        return false
    }

    let tildeID = EventHotKeyID(signature: OSType(0x44494354), id: 1)
    let tildeStatus = RegisterEventHotKey(UInt32(kVK_ANSI_Grave), 0, tildeID, GetApplicationEventTarget(), 0, &tildeHotkeyRef)
    if tildeStatus != noErr {
        log("⚠️ Failed to register tilde hotkey: \(tildeStatus)")
        setupNSEventFallback()
        return true
    }

    let escID = EventHotKeyID(signature: OSType(0x44494354), id: 2)
    RegisterEventHotKey(UInt32(kVK_Escape), 0, escID, GetApplicationEventTarget(), 0, &escapeHotkeyRef)

    log("✅ Carbon hotkeys registered (tilde + escape)")
    return true
}

func setupNSEventFallback() {
    log("⚠️ Using NSEvent fallback for hotkeys")
    NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
        if event.keyCode == 50 && !event.isARepeat {
            DispatchQueue.main.async {
                guard let del = appDelegateRef else { return }
                if del.recorder.isRecording { del.recorder.stopRecording() }
                else if !del.recorder.isStopping { del.recorder.startRecording() }
            }
        } else if event.keyCode == 53 && !event.isARepeat {
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
    var themeMenu: NSMenu!
    let historyController = HistoryWindowController()
    // G1: Recording timer
    var recordingTimer: Timer?
    var recordingStartTime: Date?
    // US-002: Timing display timer
    var timingTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("🎤 Ember starting...")
        appDelegateRef = self
        recorder.delegate = self

        // Check microphone access
        checkMicrophoneAccess()

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

        // F1: Check reduceMotion accessibility setting — use minimal theme if enabled
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            log("♿ reduceMotion detected — switching to minimal theme")
            config.theme = "minimal"
            Config.saveField("THEME", value: "minimal")
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
        // Theme submenu
        themeMenu = NSMenu(title: "Theme")
        buildThemeMenu()
        let themeItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        themeItem.submenu = themeMenu
        menu.addItem(themeItem)

        let updateItem = NSMenuItem(title: "Check for Updates...", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        updateItem.target = updaterController
        menu.addItem(updateItem)
        let hi = NSMenuItem(title: "History...", action: #selector(openHistory), keyEquivalent: ""); hi.target = self; menu.addItem(hi)
        menu.addItem(.separator())
        let qi = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"); qi.target = self; menu.addItem(qi)
        statusItem.menu = menu

        overlayWindow = PlasmaOverlayWindow()

        // Carbon hotkeys — works without Accessibility permission
        if !setupCarbonHotkeys() {
            setupNSEventFallback()
        }
    }

    // ─── Microphone Access ────────────────────────────────────────
    func checkMicrophoneAccess() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .denied, .restricted:
            log("⚠️ Microphone access denied")
            DispatchQueue.main.async { [weak self] in
                self?.recorderDidEncounterError(.microphoneAccessDenied)
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                if granted {
                    log("✅ Microphone access granted")
                } else {
                    log("⚠️ Microphone access denied by user")
                    DispatchQueue.main.async { [weak self] in
                        self?.recorderDidEncounterError(.microphoneAccessDenied)
                    }
                }
            }
        case .authorized:
            log("✅ Microphone access authorized")
        @unknown default:
            break
        }
    }

    func setRecordingState(_ recording: Bool) {
        DispatchQueue.main.async { [self] in
            if recording {
                // G1: Start elapsed timer
                recordingStartTime = Date()
                recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                    guard let self = self, let start = self.recordingStartTime else { return }
                    let elapsed = Int(Date().timeIntervalSince(start))
                    let mm = elapsed / 60
                    let ss = elapsed % 60
                    let label = String(format: "%d:%02d", mm, ss)
                    self.statusItem.button?.title = " \(label)"
                    self.statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Recording")
                }
                statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Recording")
                statusItem.button?.title = " 0:00"
            } else {
                // G1: Stop timer and clear title
                recordingTimer?.invalidate()
                recordingTimer = nil
                recordingStartTime = nil
                statusItem.button?.title = ""
                statusItem.button?.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Ember")
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

    @objc func openHistory() { historyController.showWindow() }
    @objc func quitApp() { if recorder.isRecording { recorder.stopRecording() }; NSApp.terminate(nil) }

    // ─── Theme Switching ──────────────────────────────────────────
    func buildThemeMenu() {
        themeMenu.removeAllItems()
        for name in PlasmaOverlayWindow.availableThemes() {
            let title = name.replacingOccurrences(of: "-", with: " ").split(separator: " ")
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
            let item = NSMenuItem(title: title, action: #selector(switchTheme(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            item.state = (name == config.theme) ? .on : .off
            themeMenu.addItem(item)
        }
    }

    @objc func switchTheme(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        config.theme = name
        Config.saveField("THEME", value: name)
        overlayWindow?.loadTheme(name)
        // Restore overlay state if currently active
        if overlayWindow?.isShowing == true {
            overlayWindow?.webView.evaluateJavaScript("window.setActive(true)", completionHandler: nil)
        }
        buildThemeMenu()
        log("🎨 Theme switched to: \(name)")
    }

    func setThemeMenuEnabled(_ enabled: Bool) {
        for item in themeMenu.items { item.isEnabled = enabled }
    }

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
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 390),
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

        // ── LLM Correction ──
        let llmLabel = NSTextField(labelWithString: "LLM Correction:")
        llmLabel.font = .systemFont(ofSize: 13, weight: .medium)

        let llmPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        let llmOptions: [(LLMCorrectionMode, String)] = [
            (.never, "Never (fastest)"),
            (.auto, "Auto (long text only)"),
            (.always, "Always"),
        ]
        for (mode, label) in llmOptions {
            llmPopup.addItem(withTitle: label)
            llmPopup.lastItem?.representedObject = mode.rawValue
        }
        if let idx = llmOptions.firstIndex(where: { $0.0 == config.llmCorrection }) {
            llmPopup.selectItem(at: idx)
        }
        llmPopup.translatesAutoresizingMaskIntoConstraints = false

        let llmRow = NSStackView(views: [llmLabel, llmPopup])
        llmRow.orientation = .horizontal
        llmRow.spacing = 10
        llmRow.alignment = .centerY
        llmLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        llmPopup.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // ── VAD Auto-Stop ──
        let vadCheckbox = NSButton(checkboxWithTitle: "Auto-stop on silence (experimental)", target: nil, action: nil)
        vadCheckbox.state = config.vadAutoStop ? .on : .off
        vadCheckbox.translatesAutoresizingMaskIntoConstraints = false

        // ── Align labels ──
        let labelWidth: CGFloat = 110
        keyLabel.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true
        langLabel.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true
        llmLabel.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true

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

        let stack = NSStackView(views: [keyRow, langRow, llmRow, vadCheckbox, linkButton, spacer, buttonRow])
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
            llmRow.leadingAnchor.constraint(equalTo: stack.leadingAnchor, constant: 24),
            llmRow.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -24),
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
        self._prefsLLMPopup = llmPopup
        self._prefsVADCheckbox = vadCheckbox

        saveButton.target = self
        saveButton.action = #selector(preferencesSave)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Stored references for preferences fields (weak not needed — window holds them)
    private var _prefsKeyField: NSSecureTextField?
    private var _prefsLangPopup: NSPopUpButton?
    private var _prefsLLMPopup: NSPopUpButton?
    private var _prefsVADCheckbox: NSButton?

    @objc private func preferencesSave() {
        guard let keyField = _prefsKeyField, let langPopup = _prefsLangPopup else { return }
        let key = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let langCode = (langPopup.selectedItem?.representedObject as? String) ?? "auto"
        let llmRaw = (_prefsLLMPopup?.selectedItem?.representedObject as? String) ?? "never"
        let llmMode = LLMCorrectionMode(rawValue: llmRaw) ?? .never
        let vadEnabled = _prefsVADCheckbox?.state == .on

        Config.save(groqKey: key, language: langCode, llmCorrection: llmMode, vadAutoStop: vadEnabled)
        config = Config.load()

        preferencesWindow?.close()
        preferencesWindow = nil
        _prefsKeyField = nil
        _prefsLangPopup = nil
        _prefsLLMPopup = nil
        _prefsVADCheckbox = nil
    }

    @objc private func preferencesCancel() {
        preferencesWindow?.close()
        preferencesWindow = nil
        _prefsKeyField = nil
        _prefsLangPopup = nil
        _prefsLLMPopup = nil
        _prefsVADCheckbox = nil
    }

    @objc private func openGroqConsole() {
        if let url = URL(string: "https://console.groq.com/keys") {
            NSWorkspace.shared.open(url)
        }
    }

    // ─── Timing Display (US-002) ──────────────────────────────────
    func showTimingBriefly(_ totalTime: Double) {
        timingTimer?.invalidate()
        let label = String(format: "⚡ %.1fs", totalTime)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.statusItem.button?.title = " \(label)"
            self.timingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                self?.statusItem.button?.title = ""
            }
        }
    }

    // ─── RecorderDelegate ─────────────────────────────────────────
    func recorderDidStartRecording() {
        setRecordingState(true)
        setThemeMenuEnabled(false)
        overlayWindow?.show()
    }

    func recorderDidStopRecording() {
        setRecordingState(false)
        setThemeMenuEnabled(true)
    }

    func recorderDidStartProcessing() {
        setProcessingState(true)
        overlayWindow?.webView.evaluateJavaScript("window.setProcessing(true)", completionHandler: nil)
    }

    func recorderDidFinishProcessing(text: String, sttTime: Double, llmTime: Double) {
        setProcessingState(false)
        overlayWindow?.webView.evaluateJavaScript("window.setProcessing(false)", completionHandler: nil)

        // US-002: Show timing in menu bar briefly
        let totalTime = sttTime + llmTime
        showTimingBriefly(totalTime)

        guard !text.isEmpty else {
            overlayWindow?.hide()
            return
        }

        // G3: Celebratory pulse before fade-out
        overlayWindow?.webView.evaluateJavaScript("window.setCelebration()", completionHandler: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.overlayWindow?.hide()
        }

        let pb = NSPasteboard.general; pb.clearContents()
        pb.setString(text, forType: .string)

        // Auto-paste: Cmd+V (via simulatePaste — non-blocking, checks frontmost app)
        log("📋 Pasted \(text.count) chars")
        simulatePaste()
    }

    func recorderDidEncounterError(_ error: EmberError) {
        // Reset processing state and hide overlay
        setProcessingState(false)
        setRecordingState(false)
        setThemeMenuEnabled(true)
        overlayWindow?.flashError()

        log("⚠️ Error: \(error.userMessage)")

        // Show NSAlert on main thread
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Ember"
            alert.informativeText = error.userMessage
            alert.alertStyle = error.isRecoverable ? .warning : .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }

    func recorderDidCancel() {
        setRecordingState(false)
        setThemeMenuEnabled(true)
        overlayWindow?.hide()
    }

    func recorderDidUpdateAudioLevel(_ level: Float) {
        overlayWindow?.audioLevel = level
    }
}

// ─── Shared Paste Utility ────────────────────────────────────────
/// Simulate Cmd+V paste. Checks frontmost app is not Ember itself.
/// Uses asyncAfter instead of usleep to avoid blocking the main thread.
func simulatePaste() {
    // Ember is a menu bar app (LSUIElement) — it never steals focus from the target app.
    // The frontmost app at paste time is always the user's target window.
    let src = CGEventSource(stateID: .combinedSessionState)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
        if let d = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true) {
            d.flags = .maskCommand; d.post(tap: .cghidEventTap)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            if let u = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false) {
                u.flags = .maskCommand; u.post(tap: .cghidEventTap)
            }
        }
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
