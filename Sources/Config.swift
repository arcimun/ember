import Foundation
import Cocoa

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

func saveHistory(currentText: String, recordingStartTime: Date?) {
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
