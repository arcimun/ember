import Foundation
import Cocoa

// ─── Logging ─────────────────────────────────────────────────────
let logFile = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/Ember.log")

// D4: Cached DateFormatter — avoids allocation on every log() call
private let _logDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    return f
}()

func log(_ msg: String) {
    let line = "[\(_logDateFormatter.string(from: Date()))] \(msg)\n"
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
enum LLMCorrectionMode: String {
    case auto = "auto"
    case always = "always"
    case never = "never"
}

struct Config {
    var groqKey: String = ""
    var language: String = "auto"
    var theme: String = "digital-rain"
    var endDelay: Double = 0.8
    var llmCorrection: LLMCorrectionMode = .never
    var vadAutoStop: Bool = false

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
                if k == "THEME" { cfg.theme = v }
                if k == "LLM_CORRECTION" { cfg.llmCorrection = LLMCorrectionMode(rawValue: v) ?? .never }
                if k == "VAD_AUTO_STOP" { cfg.vadAutoStop = (v == "true" || v == "1") }
            }
        }
        return cfg
    }

    static let configPath: String = {
        let dir = NSString(string: "~/.config/ember").expandingTildeInPath
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return (dir as NSString).appendingPathComponent("config.env")
    }()

    /// Read-modify-write: updates only specified keys, preserves everything else
    static func saveField(_ key: String, value: String) {
        var lines = ((try? String(contentsOfFile: configPath, encoding: .utf8)) ?? "")
            .components(separatedBy: .newlines)
        var found = false
        lines = lines.map { line in
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("\(key)=") {
                found = true; return "\(key)=\(value)"
            }
            return line
        }
        if !found {
            if let last = lines.last, last.isEmpty { lines.insert("\(key)=\(value)", at: lines.count - 1) }
            else { lines.append("\(key)=\(value)") }
        }
        try? lines.joined(separator: "\n").write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    static func save(groqKey: String, language: String, llmCorrection: LLMCorrectionMode? = nil, vadAutoStop: Bool? = nil) {
        saveField("GROQ_API_KEY", value: groqKey)
        saveField("DICTATION_LANGUAGE", value: language)
        if let llm = llmCorrection {
            saveField("LLM_CORRECTION", value: llm.rawValue)
        }
        if let vad = vadAutoStop {
            saveField("VAD_AUTO_STOP", value: vad ? "true" : "false")
        }
        log("✅ Config saved to \(configPath)")
    }
}

var config = Config.load()

// ─── First-Run API Key Dialog ──────────────────────────────────
// B4: Value proposition + B5: NSSecureTextField + B3: gsk_ validation + B6: Skip consequences
func showApiKeyDialog() {
    let alert = NSAlert()
    alert.messageText = "Welcome to Ember"
    // B4: Value proposition before asking for the key
    alert.informativeText = "Press `, speak, and text appears automatically — in any app.\n\nEmber uses Groq for transcription (free tier available). Enter your API key to get started."
    alert.alertStyle = .informational

    // B5: NSSecureTextField hides the key as it's typed
    let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 52))

    let inputField = NSSecureTextField(frame: NSRect(x: 0, y: 28, width: 320, height: 24))
    inputField.placeholderString = "gsk_..."
    container.addSubview(inputField)

    // B3: Format hint
    let hint = NSTextField(labelWithString: "Key must start with gsk_")
    hint.frame = NSRect(x: 0, y: 0, width: 320, height: 20)
    hint.font = .systemFont(ofSize: 11)
    hint.textColor = .secondaryLabelColor
    container.addSubview(hint)

    alert.accessoryView = container

    alert.addButton(withTitle: "Save")
    alert.addButton(withTitle: "Get Free Key")
    // B6: Explain skip consequences
    alert.addButton(withTitle: "Skip (transcription disabled)")

    let response = alert.runModal()

    switch response {
    case .alertFirstButtonReturn:
        // Save
        let key = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            log("⚠️ Empty API key — skipped")
            return
        }
        // B3: Validate gsk_ prefix format
        guard key.hasPrefix("gsk_") else {
            log("⚠️ Invalid API key format (must start with gsk_)")
            let errAlert = NSAlert()
            errAlert.messageText = "Invalid API Key"
            errAlert.informativeText = "Groq API keys start with \"gsk_\". Please check your key and try again."
            errAlert.alertStyle = .warning
            errAlert.addButton(withTitle: "OK")
            errAlert.runModal()
            DispatchQueue.main.async { showApiKeyDialog() }
            return
        }
        Config.saveField("GROQ_API_KEY", value: key)
        config = Config.load()
        log("✅ API key saved")

    case .alertSecondButtonReturn:
        // Get Free Key — open browser, then re-show dialog
        if let url = URL(string: "https://console.groq.com/keys") {
            NSWorkspace.shared.open(url)
        }
        DispatchQueue.main.async { showApiKeyDialog() }

    default:
        // Skip
        log("⚠️ API key dialog skipped — transcription disabled until key is set in Preferences")
    }
}

let historyDir: String = {
    let p = NSString(string: "~/.config/ember/history").expandingTildeInPath
    try? FileManager.default.createDirectory(atPath: p, withIntermediateDirectories: true)
    return p
}()

func saveHistory(raw: String, corrected: String, language: String, duration: Double) {
    guard !corrected.isEmpty else { return }
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
    let path = (historyDir as NSString).appendingPathComponent("\(f.string(from: Date())).json")
    var entry: [String: Any] = [
        "timestamp": ISO8601DateFormatter().string(from: Date()),
        "duration_ms": Int(duration * 1000),
        "corrected": corrected,
        "language": language,
        "provider": "groq-whisper"
    ]
    if !raw.isEmpty { entry["raw"] = raw }
    if let d = try? JSONSerialization.data(withJSONObject: entry, options: .prettyPrinted) {
        try? d.write(to: URL(fileURLWithPath: path))
        log("💾 \(path.components(separatedBy: "/").last ?? "")")
    }
}
