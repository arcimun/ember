import Foundation
import Cocoa
import AudioToolbox

// ═══════════════════════════════════════════════════════════════════
// Audio Recording — WAV file via SoX `rec`
// ═══════════════════════════════════════════════════════════════════

protocol RecorderDelegate: AnyObject {
    func recorderDidStartRecording()
    func recorderDidStopRecording()
    func recorderDidFinishProcessing(text: String)
    func recorderDidCancel()
    func recorderDidUpdateAudioLevel(_ level: Float)
    func recorderDidStartProcessing()
}

class Recorder {
    var isRecording = false
    var isStopping = false
    var currentText = ""
    var recordingStartTime: Date?
    var audioLevel: Float = 0

    private var recProcess: Process?
    private var audioMonitorProcess: Process?
    private var audioFilePath = ""

    weak var delegate: RecorderDelegate?

    // ─── Find rec (SoX) binary ──────────────────────────────────────
    private func findRecBinary() -> String {
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
            delegate?.recorderDidStartRecording()

            // Start audio monitor (raw PCM to stdout for RMS level)
            let monitor = Process()
            monitor.executableURL = URL(fileURLWithPath: recBin)
            monitor.arguments = ["-q", "-t", "raw", "-r", "16000", "-c", "1", "-b", "16", "-e", "signed-integer", "-L", "-"]
            monitor.standardError = FileHandle.nullDevice
            let monPipe = Pipe()
            monitor.standardOutput = monPipe
            monPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                data.withUnsafeBytes { raw in
                    guard let ptr = raw.bindMemory(to: Int16.self).baseAddress else { return }
                    let cnt = data.count / 2; var sum: Float = 0
                    for i in 0..<cnt { let s = Float(ptr[i]) / 32768.0; sum += s * s }
                    let rms = sqrt(sum / max(Float(cnt), 1))
                    self?.audioLevel = (self?.audioLevel ?? 0) * 0.6 + rms * 0.4
                    self?.delegate?.recorderDidUpdateAudioLevel(self?.audioLevel ?? 0)
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
        delegate?.recorderDidStopRecording()
        delegate?.recorderDidStartProcessing()

        // Send WAV to Groq Whisper API
        guard FileManager.default.fileExists(atPath: audioFilePath) else {
            log("⚠️ No audio file"); isStopping = false; return
        }

        let filePath = audioFilePath
        let apiKey = config.groqKey
        let language = config.language

        transcribeWithGroq(filePath: filePath, apiKey: apiKey, language: language) { [weak self] rawText in
            guard let self = self else { return }

            // Skip if empty, too short, or just whitespace
            let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count > 2 else {
                log("⚠️ No speech detected")
                DispatchQueue.main.async {
                    self.delegate?.recorderDidFinishProcessing(text: "")
                }
                try? FileManager.default.removeItem(atPath: filePath)
                self.isStopping = false
                return
            }

            self.currentText = trimmed
            log("📝 Raw: \"\(trimmed.prefix(100))\"")

            // LLM post-processing
            postProcessText(trimmed, apiKey: apiKey) { [weak self] correctedText in
                guard let self = self else { return }
                self.currentText = correctedText

                DispatchQueue.main.async {
                    self.delegate?.recorderDidFinishProcessing(text: correctedText)
                }

                saveHistory(currentText: correctedText, recordingStartTime: self.recordingStartTime)
                try? FileManager.default.removeItem(atPath: filePath)
                self.isStopping = false
                log("✅ Done: \"\(correctedText.prefix(100))\"")
            }
        }
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
        delegate?.recorderDidCancel()
    }

    private func killRec() {
        if let p = recProcess, p.isRunning {
            kill(p.processIdentifier, SIGINT)
            let dl = Date().addingTimeInterval(1.0); while p.isRunning && Date() < dl { usleep(50_000) }
            if p.isRunning { p.terminate() }
        }; recProcess = nil

        // Kill audio monitor
        if let m = audioMonitorProcess, m.isRunning { m.terminate() }
        audioMonitorProcess = nil
        audioLevel = 0
    }
}
