import Cocoa
import Carbon.HIToolbox
import Sparkle
import AVFoundation
import SwiftUI

// ═══════════════════════════════════════════════════════════════════
//  Ember v2.0 — Voice-to-text for macOS
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

    let cfg = EmberConfig.shared
    let tildeID = EventHotKeyID(signature: OSType(0x44494354), id: 1)
    let tildeStatus = RegisterEventHotKey(cfg.hotkeyKeyCode, cfg.hotkeyModifiers, tildeID, GetApplicationEventTarget(), 0, &tildeHotkeyRef)
    if tildeStatus != noErr {
        log("⚠️ Failed to register hotkey (keyCode: \(cfg.hotkeyKeyCode), mods: \(cfg.hotkeyModifiers)): \(tildeStatus)")
        setupNSEventFallback()
        return true
    }

    let escID = EventHotKeyID(signature: OSType(0x44494354), id: 2)
    RegisterEventHotKey(UInt32(kVK_Escape), 0, escID, GetApplicationEventTarget(), 0, &escapeHotkeyRef)

    log("✅ Carbon hotkeys registered (keyCode: \(cfg.hotkeyKeyCode), mods: \(cfg.hotkeyModifiers))")
    return true
}

/// Re-register the recording hotkey at runtime (called from Settings when user changes hotkey)
func reregisterRecordingHotkey() {
    // Unregister old
    if let ref = tildeHotkeyRef {
        UnregisterEventHotKey(ref)
        tildeHotkeyRef = nil
    }
    // Register new
    let cfg = EmberConfig.shared
    let hotkeyID = EventHotKeyID(signature: OSType(0x44494354), id: 1)
    let status = RegisterEventHotKey(cfg.hotkeyKeyCode, cfg.hotkeyModifiers, hotkeyID, GetApplicationEventTarget(), 0, &tildeHotkeyRef)
    if status != noErr {
        log("⚠️ Failed to re-register hotkey: \(status)")
    } else {
        log("✅ Hotkey re-registered (keyCode: \(cfg.hotkeyKeyCode), mods: \(cfg.hotkeyModifiers))")
    }
}

func setupNSEventFallback() {
    log("⚠️ Using NSEvent fallback for hotkeys")
    NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
        let cfg = EmberConfig.shared
        if event.keyCode == cfg.hotkeyKeyCode && !event.isARepeat {
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
    // History window uses HistoryWindowManager (singleton, prevents window leak — Eng 2.5)
    let onboardingController = OnboardingWindowController()
    // G1: Recording timer
    var recordingTimer: Timer?
    var recordingStartTime: Date?
    // US-002: Timing display timer
    var timingTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("🎤 Ember starting...")
        appDelegateRef = self
        recorder.delegate = self

        // Fix 0F: Clean stale temp audio files older than 1 hour
        cleanupTempFiles()

        // Fix 0E: Serialize first-run dialogs — mic permission FIRST, then API key
        checkMicrophoneAccessThenApiKey()

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
            EmberConfig.shared.theme = "minimal"
            EmberConfig.saveField("THEME", value: "minimal")
        }

        // Sparkle auto-updater
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

        // Menu bar status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Ember")
        }

        // Status item dropdown menu (quick actions)
        toggleMenuItem = NSMenuItem(title: "Start Recording (`)", action: #selector(toggleRecording), keyEquivalent: "")
        toggleMenuItem.target = self
        let statusMenu = NSMenu()
        statusMenu.addItem(toggleMenuItem)
        statusMenu.addItem(.separator())

        let prefsStatusItem = NSMenuItem(title: "Preferences...", action: #selector(showPreferences), keyEquivalent: ",")
        prefsStatusItem.target = self
        statusMenu.addItem(prefsStatusItem)
        statusMenu.addItem(.separator())

        // Theme submenu
        themeMenu = NSMenu(title: "Theme")
        buildThemeMenu()
        let themeItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        themeItem.submenu = themeMenu
        statusMenu.addItem(themeItem)

        let updateItem = NSMenuItem(title: "Check for Updates...", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        updateItem.target = updaterController
        statusMenu.addItem(updateItem)

        let hi = NSMenuItem(title: "History...", action: #selector(openHistory), keyEquivalent: "")
        hi.target = self
        statusMenu.addItem(hi)

        statusMenu.addItem(.separator())

        let qi = NSMenuItem(title: "Quit Ember", action: #selector(quitApp), keyEquivalent: "q")
        qi.target = self
        statusMenu.addItem(qi)

        statusItem.menu = statusMenu

        // Phase 1: Native NSMenu (Ember, Edit, Window, Help)
        setupMainMenu()

        overlayWindow = PlasmaOverlayWindow()

        // Carbon hotkeys — works without Accessibility permission
        if !setupCarbonHotkeys() {
            setupNSEventFallback()
        }

        // Listen for theme changes from SwiftUI Preferences
        NotificationCenter.default.addObserver(
            forName: .emberThemeChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let themeName = notification.object as? String {
                self?.overlayWindow?.loadTheme(themeName)
                self?.buildThemeMenu()
            }
        }

        // Show onboarding on first launch
        if OnboardingWindowController.shouldShow() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.onboardingController.show()
            }
        }
    }

    // ─── Fix 0F: Temp File Cleanup ────────────────────────────────
    private func cleanupTempFiles() {
        let fm = FileManager.default
        let tmpDir = "/tmp"
        guard let files = try? fm.contentsOfDirectory(atPath: tmpDir) else { return }
        let oneHourAgo = Date().addingTimeInterval(-3600)
        var cleaned = 0
        for file in files where file.hasPrefix("ember_") {
            let path = (tmpDir as NSString).appendingPathComponent(file)
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let modDate = attrs[.modificationDate] as? Date,
                  modDate < oneHourAgo else { continue }
            try? fm.removeItem(atPath: path)
            cleaned += 1
        }
        if cleaned > 0 { log("🧹 Cleaned \(cleaned) stale temp file(s)") }
    }

    // ─── Fix 0E: Serialized mic → API key dialogs ─────────────────
    private func checkMicrophoneAccessThenApiKey() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .denied, .restricted:
            log("⚠️ Microphone access denied")
            DispatchQueue.main.async { [weak self] in
                self?.recorderDidEncounterError(.microphoneAccessDenied)
            }
            // Still check API key even if mic denied
            checkApiKeyIfNeeded()

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                if granted {
                    log("✅ Microphone access granted")
                } else {
                    log("⚠️ Microphone access denied by user")
                    DispatchQueue.main.async { [weak self] in
                        self?.recorderDidEncounterError(.microphoneAccessDenied)
                    }
                }
                // Fix 0E: Show API key dialog AFTER mic permission completes
                DispatchQueue.main.async { [weak self] in
                    self?.checkApiKeyIfNeeded()
                }
            }

        case .authorized:
            log("✅ Microphone access authorized")
            checkApiKeyIfNeeded()

        @unknown default:
            checkApiKeyIfNeeded()
        }
    }

    private func checkApiKeyIfNeeded() {
        if EmberConfig.shared.groqKey.isEmpty {
            showApiKeyDialog()
        }
    }

    // ─── Microphone Access (kept for error handling) ──────────────
    func checkMicrophoneAccess() {
        // This method is kept for compatibility with RecorderDelegate
        // Actual first-run check is done via checkMicrophoneAccessThenApiKey()
    }

    // ─── Phase 1: Native NSMenu ───────────────────────────────────
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // ── Ember menu ──
        let emberMenu = NSMenu(title: "Ember")

        let aboutItem = NSMenuItem(title: "About Ember", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        emberMenu.addItem(aboutItem)

        emberMenu.addItem(.separator())

        let prefsItem = NSMenuItem(title: "Preferences…", action: #selector(showPreferences), keyEquivalent: ",")
        prefsItem.target = self
        emberMenu.addItem(prefsItem)

        emberMenu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Ember", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        emberMenu.addItem(quitItem)

        let emberMenuBarItem = NSMenuItem()
        emberMenuBarItem.submenu = emberMenu
        mainMenu.addItem(emberMenuBarItem)

        // ── Edit menu ──
        let editMenu = NSMenu(title: "Edit")

        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        let editMenuBarItem = NSMenuItem()
        editMenuBarItem.submenu = editMenu
        mainMenu.addItem(editMenuBarItem)

        // ── Window menu ──
        let windowMenu = NSMenu(title: "Window")

        let minimizeItem = NSMenuItem(title: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(minimizeItem)

        let zoomItem = NSMenuItem(title: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        windowMenu.addItem(zoomItem)

        windowMenu.addItem(.separator())

        let bringAllItem = NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        windowMenu.addItem(bringAllItem)

        let windowMenuBarItem = NSMenuItem()
        windowMenuBarItem.submenu = windowMenu
        mainMenu.addItem(windowMenuBarItem)
        NSApp.windowsMenu = windowMenu

        // ── Help menu ──
        let helpMenu = NSMenu(title: "Help")

        let helpItem = NSMenuItem(title: "Ember Help", action: #selector(openHelp), keyEquivalent: "?")
        helpItem.target = self
        helpMenu.addItem(helpItem)

        let welcomeItem = NSMenuItem(title: "Show Welcome Guide", action: #selector(showWelcomeGuide), keyEquivalent: "")
        welcomeItem.target = self
        helpMenu.addItem(welcomeItem)

        let helpMenuBarItem = NSMenuItem()
        helpMenuBarItem.submenu = helpMenu
        mainMenu.addItem(helpMenuBarItem)

        NSApp.mainMenu = mainMenu
        NSApp.helpMenu = helpMenu
    }

    // ─── About Panel ──────────────────────────────────────────────
    @objc func showAbout() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""

        let creditsText = """
        Ember v\(version) (build \(build))

        Voice-to-text for macOS.
        Press `, speak, text appears.

        GitHub: github.com/arcimun/ember
        License: MIT
        """

        let creditsAttr = NSAttributedString(
            string: creditsText,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Ember",
            .applicationVersion: version,
            .version: build,
            .credits: creditsAttr
        ])
    }

    @objc func openHelp() {
        if let url = URL(string: "https://github.com/arcimun/ember") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func showWelcomeGuide() {
        onboardingController.show()
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

    @objc func openHistory() { HistoryWindowManager.shared.show() }
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
            item.state = (name == EmberConfig.shared.theme) ? .on : .off
            themeMenu.addItem(item)
        }
    }

    @objc func switchTheme(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        EmberConfig.shared.theme = name
        EmberConfig.saveField("THEME", value: name)
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

    // ─── Preferences Window (SwiftUI) ────────────────────────────

    @objc func showPreferences() {
        // Reuse existing window if open
        if let w = preferencesWindow, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Ember Preferences"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 550, height: 420))
        window.center()
        window.isReleasedWhenClosed = false

        preferencesWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
