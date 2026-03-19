import Cocoa
import Foundation
import AudioToolbox
import QuartzCore
import Carbon.HIToolbox
import WebKit

// ═══════════════════════════════════════════════════════════════════
//  Ember v1.0.0 — Voice-to-text for macOS
//  ` record → Groq Whisper STT → Groq LLM fix → auto-paste
// ═══════════════════════════════════════════════════════════════════

// ─── Logging ─────────────────────────────────────────────────────
let logFile = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/Ember.log")

func log(_ msg: String) {
    let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
    let line = "[\(f.string(from: Date()))] \(msg)\n"
    print(line, terminator: "")
    if let data = line.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logFile.path) {
            if let handle = try? FileHandle(forWritingTo: logFile) {
                handle.seekToEndOfFile(); handle.write(data); handle.closeFile()
            }
        } else { try? data.write(to: logFile) }
    }
}

// ─── Config ──────────────────────────────────────────────────────
struct Config {
    var groqKey: String = ""
    var language: String = "ru"
    var endDelay: Double = 0.8

    static func load() -> Config {
        var cfg = Config()
        for path in [
            NSString(string: "~/.config/ember/config.env").expandingTildeInPath,
            NSString(string: "~/.openclaw/.env").expandingTildeInPath,
        ] {
            guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            for line in contents.components(separatedBy: .newlines) {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("#") || !t.contains("=") { continue }
                let parts = t.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let k = String(parts[0]).trimmingCharacters(in: .whitespaces)
                let v = String(parts[1]).trimmingCharacters(in: .whitespaces)
                if k == "GROQ_API_KEY" && cfg.groqKey.isEmpty { cfg.groqKey = v }
                if k == "DICTATION_LANGUAGE" { cfg.language = v }
            }
        }
        return cfg
    }
}

var config = Config.load()

// ─── First-Run API Key Dialog ──────────────────────────────────
func showApiKeyDialog() {
    let alert = NSAlert()
    alert.messageText = "Welcome to Ember"
    alert.informativeText = "Enter your Groq API key to get started.\nGet a free key at console.groq.com"
    alert.alertStyle = .informational

    let inputField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
    inputField.placeholderString = "gsk_..."
    alert.accessoryView = inputField

    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Get API Key")
    alert.addButton(withTitle: "Skip")

    let response = alert.runModal()

    switch response {
    case .alertFirstButtonReturn:
        // Save
        let key = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            log("⚠️ Empty API key — skipped")
            return
        }
        let configDir = NSString(string: "~/.config/ember").expandingTildeInPath
        try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        let configPath = (configDir as NSString).appendingPathComponent("config.env")
        // Append or create config file
        var contents = (try? String(contentsOfFile: configPath, encoding: .utf8)) ?? ""
        if contents.contains("GROQ_API_KEY=") {
            // Replace existing key
            let lines = contents.components(separatedBy: .newlines).map { line -> String in
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("GROQ_API_KEY=") {
                    return "GROQ_API_KEY=\(key)"
                }
                return line
            }
            contents = lines.joined(separator: "\n")
        } else {
            if !contents.isEmpty && !contents.hasSuffix("\n") { contents += "\n" }
            contents += "GROQ_API_KEY=\(key)\n"
        }
        try? contents.write(toFile: configPath, atomically: true, encoding: .utf8)
        config = Config.load()
        log("✅ API key saved to \(configPath)")

    case .alertSecondButtonReturn:
        // Get API Key — open browser, then re-show dialog
        if let url = URL(string: "https://console.groq.com/keys") {
            NSWorkspace.shared.open(url)
        }
        showApiKeyDialog()

    default:
        // Skip
        log("⚠️ API key dialog skipped")
    }
}

let historyDir: String = {
    let p = NSString(string: "~/.config/ember/history").expandingTildeInPath
    try? FileManager.default.createDirectory(atPath: p, withIntermediateDirectories: true)
    return p
}()

// ─── State ───────────────────────────────────────────────────────
var isRecording = false
var isStopping = false
var recProcess: Process?
var currentText = ""
var recordingStartTime: Date?
var currentAudioLevel: Float = 0

weak var appDelegateRef: AppDelegate?

// ═══════════════════════════════════════════════════════════════════
// Violet Flame Overlay — WebView with Canvas plasma waves
// Organic, living, voice-reactive flames on screen edges
// ═══════════════════════════════════════════════════════════════════

class PlasmaOverlayWindow: NSWindow {
    var webView: WKWebView!
    var audioTimer: Timer?

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

        // Load overlay HTML
        if let path = Bundle.main.path(forResource: "overlay", ofType: "html") {
            webView.loadFileURL(URL(fileURLWithPath: path), allowingReadAccessTo: URL(fileURLWithPath: path).deletingLastPathComponent())
            log("🎨 Overlay HTML loaded")
        } else {
            log("⚠️ overlay.html not found")
        }
    }

    var isShowing = false

    func show() {
        if !isShowing {
            orderFront(nil); alphaValue = 0
            NSAnimationContext.runAnimationGroup { $0.duration = 0.3; self.animator().alphaValue = 1 }
            isShowing = true
        }
        webView.evaluateJavaScript("window.setActive(true)", completionHandler: nil)

        // Send audio levels to WebView at 30fps
        if audioTimer == nil {
            audioTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30, repeats: true) { [weak self] _ in
                self?.webView.evaluateJavaScript("window.setAudioLevel(\(currentAudioLevel))", completionHandler: nil)
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

// ═══════════════════════════════════════════════════════════════════
// Audio Recording → WAV file → Groq Whisper API
// ═══════════════════════════════════════════════════════════════════

var audioFilePath = ""
var audioMonitorProcess: Process?  // separate process for real-time audio level

// ─── Find rec (SoX) binary ──────────────────────────────────────
func findRecBinary() -> String {
    for path in ["/opt/homebrew/bin/rec", "/usr/local/bin/rec", "/usr/bin/rec"] {
        if FileManager.default.fileExists(atPath: path) { return path }
    }
    // Try PATH via which
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    task.arguments = ["rec"]
    let pipe = Pipe()
    task.standardOutput = pipe
    try? task.run()
    task.waitUntilExit()
    let result = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return result.isEmpty ? "/opt/homebrew/bin/rec" : result
}

// ─── LLM Post-Processing (Groq) ─────────────────────────────────
// After recording stops, send raw text to LLM for grammar/punctuation fix
func postProcessText(_ rawText: String, completion: @escaping (String) -> Void) {
    guard !config.groqKey.isEmpty else {
        log("⚠️ No GROQ_API_KEY — skipping post-processing")
        completion(rawText)
        return
    }

    let url = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(config.groqKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 10

    let body: [String: Any] = [
        "model": "llama-3.3-70b-versatile",
        "temperature": 0,
        "messages": [
            ["role": "system", "content": """
                You are a text corrector for voice-dictated text. The text was dictated in Russian with occasional English words (code-switching).
                Fix: grammar, punctuation, spelling, spacing, capitalization.
                Preserve the original meaning exactly. Do not add or remove content.
                If English words/names appear (Claude, iPhone, Deepgram, etc.) — keep them in English with correct spelling.
                Return ONLY the corrected text, nothing else.
                """],
            ["role": "user", "content": rawText]
        ]
    ]

    request.httpBody = try? JSONSerialization.data(withJSONObject: body)

    log("🔄 Post-processing \(rawText.count) chars...")

    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            log("⚠️ Groq error: \(error.localizedDescription)")
            completion(rawText)
            return
        }

        guard let data = data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.isEmpty else {
            log("⚠️ Groq: empty response")
            completion(rawText)
            return
        }

        let corrected = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Guard against LLM hallucination: if result is vastly different length, use raw
        if corrected.count > rawText.count * 3 || corrected.isEmpty {
            log("⚠️ LLM hallucinated, using raw text")
            completion(rawText)
            return
        }

        log("✅ Corrected: \"\(corrected.prefix(100))\"")
        completion(corrected)
    }.resume()
}

// replaceFieldText removed — silent mode uses clipboard only

// ─── Recording ───────────────────────────────────────────────────
func startRecording() {
    guard !isRecording && !isStopping else { return }
    isRecording = true; currentText = ""; recordingStartTime = Date()

    audioFilePath = NSTemporaryDirectory() + "dictation_\(Int(Date().timeIntervalSince1970)).wav"

    log("🎙️ Recording to \(audioFilePath.components(separatedBy: "/").last ?? "")")

    // Record to WAV file using rec (SoX)
    let recBin = findRecBinary()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: recBin)
    process.arguments = ["-q", "-r", "16000", "-c", "1", "-b", "16", audioFilePath]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    do {
        try process.run(); recProcess = process
        AudioServicesPlaySystemSound(1113)
        appDelegateRef?.setRecordingState(true)
        appDelegateRef?.overlayWindow?.show()

        // Start audio monitor (raw PCM to stdout for RMS level)
        let monitor = Process()
        monitor.executableURL = URL(fileURLWithPath: recBin)
        monitor.arguments = ["-q", "-t", "raw", "-r", "16000", "-c", "1", "-b", "16", "-e", "signed-integer", "-L", "-"]
        monitor.standardError = FileHandle.nullDevice
        let monPipe = Pipe()
        monitor.standardOutput = monPipe
        monPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            data.withUnsafeBytes { raw in
                guard let ptr = raw.bindMemory(to: Int16.self).baseAddress else { return }
                let cnt = data.count / 2; var sum: Float = 0
                for i in 0..<cnt { let s = Float(ptr[i]) / 32768.0; sum += s * s }
                let rms = sqrt(sum / max(Float(cnt), 1))
                currentAudioLevel = currentAudioLevel * 0.6 + rms * 0.4
            }
        }
        try monitor.run()
        audioMonitorProcess = monitor
    } catch {
        log("❌ rec: \(error)"); isRecording = false
    }
}

func stopRecording() {
    guard isRecording else { return }
    isRecording = false; isStopping = true
    log("⏹️ Stopping..."); AudioServicesPlaySystemSound(1114)
    killRec()
    appDelegateRef?.setRecordingState(false)

    // Switch overlay to "processing" mode (orange) before hiding
    appDelegateRef?.overlayWindow?.webView.evaluateJavaScript("window.setProcessing(true)", completionHandler: nil)

    // Send WAV to Groq Whisper API
    guard FileManager.default.fileExists(atPath: audioFilePath) else {
        log("⚠️ No audio file"); isStopping = false; return
    }

    transcribeWithGroq(filePath: audioFilePath) { rawText in
        // Skip if empty, too short, or just whitespace
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 2 else {
            log("⚠️ No speech detected")
            DispatchQueue.main.async {
                appDelegateRef?.overlayWindow?.webView.evaluateJavaScript("window.setProcessing(false)", completionHandler: nil)
                appDelegateRef?.overlayWindow?.hide()
            }
            try? FileManager.default.removeItem(atPath: audioFilePath)
            isStopping = false
            return
        }

        currentText = trimmed
        log("📝 Raw: \"\(trimmed.prefix(100))\"")

        // LLM post-processing
        postProcessText(trimmed) { correctedText in
            currentText = correctedText

            DispatchQueue.main.async {
                // Hide overlay (processing complete)
                appDelegateRef?.overlayWindow?.webView.evaluateJavaScript("window.setProcessing(false)", completionHandler: nil)
                appDelegateRef?.overlayWindow?.hide()

                let pb = NSPasteboard.general; pb.clearContents()
                pb.setString(correctedText, forType: .string)

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
                log("📋 Pasted \(correctedText.count) chars")
            }

            saveHistory()
            try? FileManager.default.removeItem(atPath: audioFilePath)
            isStopping = false
            log("✅ Done: \"\(correctedText.prefix(100))\"")
        }
    }
}

// ─── Groq Whisper STT (fast, free, one API key for both STT + LLM) ──
func transcribeWithGroq(filePath: String, completion: @escaping (String) -> Void) {
    guard !config.groqKey.isEmpty else {
        log("❌ No GROQ_API_KEY!"); completion(""); return
    }

    guard let fileData = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else {
        log("❌ Cannot read audio file"); completion(""); return
    }

    let url = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(config.groqKey)", forHTTPHeaderField: "Authorization")
    request.timeoutInterval = 30

    let boundary = UUID().uuidString
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

    var body = Data()
    // File
    body.append("--\(boundary)\r\n".data(using: .utf8)!)
    body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
    body.append(fileData)
    body.append("\r\n".data(using: .utf8)!)
    // Model
    body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nwhisper-large-v3-turbo\r\n".data(using: .utf8)!)
    // Language
    body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"language\"\r\n\r\n\(config.language)\r\n".data(using: .utf8)!)
    // Response format
    body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"response_format\"\r\n\r\ntext\r\n".data(using: .utf8)!)
    body.append("--\(boundary)--\r\n".data(using: .utf8)!)
    request.httpBody = body

    log("📤 Groq Whisper: \(fileData.count / 1024)KB...")

    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            log("❌ Groq STT: \(error.localizedDescription)"); completion(""); return
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let b = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            log("❌ Groq STT HTTP \(http.statusCode): \(b.prefix(200))"); completion(""); return
        }
        guard let data = data,
              let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            log("⚠️ Groq STT: empty"); completion(""); return
        }
        completion(text)
    }.resume()
}

func cancelRecording() {
    guard isRecording else { return }
    isRecording = false
    log("❌ Cancelled"); AudioServicesPlaySystemSound(1114)
    killRec()
    try? FileManager.default.removeItem(atPath: audioFilePath)

    // Save to clipboard (even on cancel)
    if !currentText.isEmpty {
        let pb = NSPasteboard.general; pb.clearContents()
        pb.setString(currentText, forType: .string)
        log("📋 Saved \(currentText.count) chars to clipboard")
    }
    currentText = ""
    appDelegateRef?.setRecordingState(false); appDelegateRef?.overlayWindow?.hide()
}

func killRec() {
    if let p = recProcess, p.isRunning {
        kill(p.processIdentifier, SIGINT)
        let dl = Date().addingTimeInterval(1.0); while p.isRunning && Date() < dl { usleep(50_000) }
        if p.isRunning { p.terminate() }
    }; recProcess = nil

    // Kill audio monitor
    if let m = audioMonitorProcess, m.isRunning { m.terminate() }
    audioMonitorProcess = nil
    currentAudioLevel = 0
}

func saveHistory() {
    guard !currentText.isEmpty else { return }
    let dur = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    let path = (historyDir as NSString).appendingPathComponent("\(f.string(from: Date())).json")
    let entry: [String: Any] = ["timestamp": ISO8601DateFormatter().string(from: Date()),
                                 "duration": round(dur*10)/10, "text": currentText,
                                 "provider": "groq-whisper", "language": config.language]
    if let d = try? JSONSerialization.data(withJSONObject: entry, options: .prettyPrinted) {
        try? d.write(to: URL(fileURLWithPath: path))
        log("💾 \(path.components(separatedBy: "/").last ?? "")")
    }
}

// ═══════════════════════════════════════════════════════════════════
// Carbon Hotkey — works WITHOUT Accessibility permission!
// ═══════════════════════════════════════════════════════════════════

var tildeHotkeyRef: EventHotKeyRef?
var escapeHotkeyRef: EventHotKeyRef?

func carbonHotkeyHandler(nextHandler: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    var hotkeyID = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                      nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkeyID)

    DispatchQueue.main.async {
        switch hotkeyID.id {
        case 1: // Tilde
            if isRecording { stopRecording() }
            else if !isStopping { startRecording() }
        case 2: // Escape (only during recording)
            if isRecording { cancelRecording() }
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
                if isRecording { stopRecording() }
                else if !isStopping { startRecording() }
            }
        } else if event.keyCode == 53 && isRecording && !event.isARepeat { // escape
            DispatchQueue.main.async { cancelRecording() }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// App Delegate
// ═══════════════════════════════════════════════════════════════════

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var toggleMenuItem: NSMenuItem!
    var overlayWindow: PlasmaOverlayWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        log("🎤 Ember v1.0.0 starting...")
        appDelegateRef = self

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

    @objc func toggleRecording() {
        statusItem.menu?.cancelTrackingWithoutAnimation()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if isRecording { stopRecording() }
            else if !isStopping { startRecording() }
        }
    }

    @objc func openHistory() { NSWorkspace.shared.open(URL(fileURLWithPath: historyDir)) }
    @objc func quitApp() { if isRecording { stopRecording() }; NSApp.terminate(nil) }
}

// ─── Main ────────────────────────────────────────────────────────
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
