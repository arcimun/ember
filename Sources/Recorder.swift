import Foundation
import Cocoa
import AudioToolbox
import AVFoundation

// ═══════════════════════════════════════════════════════════════════
// Audio Recording — WAV file via AVAudioEngine (native)
// ═══════════════════════════════════════════════════════════════════

// ─── Typed Error Enum ─────────────────────────────────────────────
enum EmberError: Error {
    case noApiKey
    case audioFileError
    case networkError
    case httpError(Int, String)
    case emptyResponse
    case noSpeechDetected
    case audioWriteError
    case engineStartFailed
    case audioConversionFailed
    case microphoneAccessDenied

    var userMessage: String {
        switch self {
        case .noApiKey:
            return "No API key set. Open Preferences to add your Groq API key."
        case .audioFileError:
            return "Could not access audio file. Check disk space."
        case .networkError:
            return "Network error. Check your internet connection."
        case .httpError(let code, let msg):
            return "API error \(code): \(msg)"
        case .emptyResponse:
            return "Empty response from API. Please try again."
        case .noSpeechDetected:
            return "No speech detected. Try speaking louder or closer to the mic."
        case .audioWriteError:
            return "Failed to write audio data."
        case .engineStartFailed:
            return "Failed to start audio engine. Check microphone permissions."
        case .audioConversionFailed:
            return "Failed to convert audio format."
        case .microphoneAccessDenied:
            return "Microphone access denied. Enable in System Settings → Privacy → Microphone."
        }
    }

    var isRecoverable: Bool {
        switch self {
        case .noApiKey, .microphoneAccessDenied:
            return false
        case .networkError, .httpError, .emptyResponse, .noSpeechDetected:
            return true
        case .audioFileError, .audioWriteError, .engineStartFailed, .audioConversionFailed:
            return true
        }
    }
}

protocol RecorderDelegate: AnyObject {
    func recorderDidStartRecording()
    func recorderDidStopRecording()
    func recorderDidFinishProcessing(text: String)
    func recorderDidCancel()
    func recorderDidUpdateAudioLevel(_ level: Float)
    func recorderDidStartProcessing()
    func recorderDidEncounterError(_ error: EmberError)
}

class Recorder {
    var isRecording = false
    var isStopping = false
    var currentText = ""
    var recordingStartTime: Date?
    var audioLevel: Float = 0

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var audioFilePath = ""
    private let writeQueue = DispatchQueue(label: "com.arcimun.ember.audiowrite")

    weak var delegate: RecorderDelegate?

    func startRecording() {
        guard !isRecording && !isStopping else { return }
        isRecording = true; currentText = ""; recordingStartTime = Date()

        audioFilePath = NSTemporaryDirectory() + "ember_\(Int(Date().timeIntervalSince1970)).wav"
        log("🎙️ Recording to \(audioFilePath.components(separatedBy: "/").last ?? "")")

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Record in mic's native format (e.g. 48kHz Float32).
        // Convert to 16kHz mono Int16 WAV after recording stops (via afconvert).
        let nativePath = audioFilePath + ".native.caf"
        do {
            audioFile = try AVAudioFile(forWriting: URL(fileURLWithPath: nativePath),
                                        settings: inputFormat.settings)
        } catch {
            log("❌ Cannot create audio file: \(error)")
            isRecording = false
            DispatchQueue.main.async {
                self.delegate?.recorderDidEncounterError(.audioFileError)
            }
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            // RMS level calculation (on audio thread — lightweight math only)
            if let channelData = buffer.floatChannelData?[0] {
                let count = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<count { sum += channelData[i] * channelData[i] }
                let rms = sqrt(sum / max(Float(count), 1))
                self.audioLevel = self.audioLevel * 0.6 + rms * 0.4
                DispatchQueue.main.async {
                    self.delegate?.recorderDidUpdateAudioLevel(self.audioLevel)
                }
            }

            // Write buffer to file on background queue (native format, no conversion)
            self.writeQueue.async { [weak self] in
                do {
                    try self?.audioFile?.write(from: buffer)
                } catch {
                    log("⚠️ Audio write error: \(error)")
                }
            }
        }

        do {
            try engine.start()
            audioEngine = engine
            AudioServicesPlaySystemSound(1113)
            delegate?.recorderDidStartRecording()
        } catch {
            log("❌ AVAudioEngine: \(error)")
            isRecording = false
            inputNode.removeTap(onBus: 0)
            DispatchQueue.main.async {
                self.delegate?.recorderDidEncounterError(.engineStartFailed)
            }
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false; isStopping = true
        log("⏹️ Stopping..."); AudioServicesPlaySystemSound(1114)
        stopEngine()
        delegate?.recorderDidStopRecording()
        delegate?.recorderDidStartProcessing()

        // Convert native format (48kHz float) → 16kHz mono Int16 WAV for Groq
        let nativePath = audioFilePath + ".native.caf"
        if FileManager.default.fileExists(atPath: nativePath) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
            task.arguments = [nativePath, audioFilePath, "-f", "WAVE", "-d", "LEI16@16000", "-c", "1"]
            try? task.run()
            task.waitUntilExit()
            try? FileManager.default.removeItem(atPath: nativePath)
        }

        // Send WAV to Groq Whisper API
        guard FileManager.default.fileExists(atPath: audioFilePath) else {
            log("⚠️ No audio file after afconvert")
            DispatchQueue.main.async {
                self.delegate?.recorderDidEncounterError(.audioConversionFailed)
                self.delegate?.recorderDidFinishProcessing(text: "")
            }
            isStopping = false; return
        }

        let filePath = audioFilePath
        let apiKey = config.groqKey
        let language = config.language

        let startTime = self.recordingStartTime
        transcribeWithGroq(filePath: filePath, apiKey: apiKey, language: language) { [weak self] result, sttError in
            guard let self = self else { return }

            if let sttError = sttError {
                log("⚠️ STT error: \(sttError.userMessage)")
                DispatchQueue.main.async {
                    self.delegate?.recorderDidEncounterError(sttError)
                    self.delegate?.recorderDidFinishProcessing(text: "")
                }
                try? FileManager.default.removeItem(atPath: filePath)
                self.isStopping = false
                return
            }

            guard let result = result, result.text.count > 2 else {
                log("⚠️ No speech detected")
                DispatchQueue.main.async {
                    self.delegate?.recorderDidEncounterError(.noSpeechDetected)
                    self.delegate?.recorderDidFinishProcessing(text: "")
                }
                try? FileManager.default.removeItem(atPath: filePath)
                self.isStopping = false
                return
            }

            let rawText = result.text
            let detectedLang = result.language
            self.currentText = rawText
            log("📝 Raw: \"\(rawText.prefix(100))\"")

            // LLM post-processing
            postProcessText(rawText, apiKey: apiKey) { [weak self] correctedText in
                guard let self = self else { return }
                self.currentText = correctedText

                DispatchQueue.main.async {
                    self.delegate?.recorderDidFinishProcessing(text: correctedText)
                }

                let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0
                saveHistory(raw: rawText, corrected: correctedText, language: detectedLang, duration: duration)
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
        stopEngine()
        try? FileManager.default.removeItem(atPath: audioFilePath)
        try? FileManager.default.removeItem(atPath: audioFilePath + ".native.caf")

        // Save to clipboard (even on cancel)
        if !currentText.isEmpty {
            let pb = NSPasteboard.general; pb.clearContents()
            pb.setString(currentText, forType: .string)
            log("📋 Saved \(currentText.count) chars to clipboard")
        }
        currentText = ""
        delegate?.recorderDidCancel()
    }

    private func stopEngine() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        // Flush all pending writes before closing the file
        writeQueue.sync {
            self.audioFile = nil
        }
        audioLevel = 0
    }
}
