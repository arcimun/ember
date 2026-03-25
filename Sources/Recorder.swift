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
    func recorderDidFinishProcessing(text: String, sttTime: Double, llmTime: Double)
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

    // VAD (Voice Activity Detection) properties
    private let silenceThreshold: Float = 0.008
    private var silentFrameCount: Int = 0
    private var speechFrameCount: Int = 0
    private let minSpeechFrames: Int = 15
    private let silenceFramesThreshold: Int = 15

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var audioFilePath = ""
    private let writeQueue = DispatchQueue(label: "com.arcimun.ember.audiowrite")

    weak var delegate: RecorderDelegate?

    private func autoTriggerTranscription() {
        guard isRecording else { return }
        log("🔇 VAD: silence detected — auto-stopping")
        DispatchQueue.main.async { [weak self] in
            self?.stopRecording()
        }
    }

    func startRecording() {
        guard !isRecording && !isStopping else { return }
        isRecording = true; currentText = ""; recordingStartTime = Date()
        // Reset VAD counters
        silentFrameCount = 0; speechFrameCount = 0

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

                // VAD: track speech and silence frames
                if config.vadAutoStop {
                    if rms >= self.silenceThreshold {
                        self.speechFrameCount += 1
                        self.silentFrameCount = 0
                    } else {
                        if self.speechFrameCount >= self.minSpeechFrames {
                            self.silentFrameCount += 1
                            if self.silentFrameCount > self.silenceFramesThreshold {
                                self.autoTriggerTranscription()
                            }
                        }
                    }
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

        // D1: Convert native CAF → 16kHz mono Int16 WAV using AVAudioConverter (in-process, no subprocess)
        let nativePath = audioFilePath + ".native.caf"
        if FileManager.default.fileExists(atPath: nativePath) {
            do {
                let sourceFile = try AVAudioFile(forReading: URL(fileURLWithPath: nativePath))
                let sourceFormat = sourceFile.processingFormat

                // Target: 16kHz mono Int16 (PCM) — Groq Whisper requirement
                guard let targetFormat = AVAudioFormat(
                    commonFormat: .pcmFormatInt16,
                    sampleRate: 16000,
                    channels: 1,
                    interleaved: true
                ) else {
                    throw EmberError.audioConversionFailed
                }

                guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
                    throw EmberError.audioConversionFailed
                }

                // Write output WAV via AVAudioFile
                let outputFile = try AVAudioFile(
                    forWriting: URL(fileURLWithPath: audioFilePath),
                    settings: targetFormat.settings,
                    commonFormat: .pcmFormatInt16,
                    interleaved: true
                )

                let inputFrameCapacity: AVAudioFrameCount = 8192
                let outputFrameCapacity = AVAudioFrameCount(
                    Double(inputFrameCapacity) * (targetFormat.sampleRate / sourceFormat.sampleRate) + 1
                )

                guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: inputFrameCapacity),
                      let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCapacity) else {
                    throw EmberError.audioConversionFailed
                }

                var reachedEnd = false
                while !reachedEnd {
                    var error: NSError?
                    let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                        do {
                            try sourceFile.read(into: inputBuffer)
                            outStatus.pointee = inputBuffer.frameLength > 0 ? .haveData : .endOfStream
                            if inputBuffer.frameLength == 0 { reachedEnd = true }
                        } catch {
                            outStatus.pointee = .endOfStream
                            reachedEnd = true
                        }
                        return inputBuffer
                    }
                    if let error = error {
                        log("⚠️ AVAudioConverter error: \(error)")
                        break
                    }
                    if outputBuffer.frameLength > 0 {
                        try outputFile.write(from: outputBuffer)
                    }
                    if status == .endOfStream { reachedEnd = true }
                }

                try? FileManager.default.removeItem(atPath: nativePath)
                log("✅ Audio converted (AVAudioConverter): \(audioFilePath.components(separatedBy: "/").last ?? "")")
            } catch {
                log("❌ AVAudioConverter failed: \(error)")
                try? FileManager.default.removeItem(atPath: nativePath)
            }
        }

        // Send WAV to Groq Whisper API
        guard FileManager.default.fileExists(atPath: audioFilePath) else {
            log("⚠️ No audio file after conversion")
            DispatchQueue.main.async {
                self.delegate?.recorderDidEncounterError(.audioConversionFailed)
                self.delegate?.recorderDidFinishProcessing(text: "", sttTime: 0, llmTime: 0)
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
                    self.delegate?.recorderDidFinishProcessing(text: "", sttTime: 0, llmTime: 0)
                }
                try? FileManager.default.removeItem(atPath: filePath)
                self.isStopping = false
                return
            }

            guard let result = result, result.text.count > 2 else {
                log("⚠️ No speech detected")
                DispatchQueue.main.async {
                    self.delegate?.recorderDidEncounterError(.noSpeechDetected)
                    self.delegate?.recorderDidFinishProcessing(text: "", sttTime: 0, llmTime: 0)
                }
                try? FileManager.default.removeItem(atPath: filePath)
                self.isStopping = false
                return
            }

            let rawText = result.text
            let detectedLang = result.language
            self.currentText = rawText
            log("📝 Raw: \"\(rawText.prefix(100))\"")

            let sttEnd = Date()

            // Determine whether to run LLM correction
            let wordCount = rawText.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.count
            let shouldUseLLM: Bool
            switch config.llmCorrection {
            case .always:
                shouldUseLLM = true
            case .never:
                shouldUseLLM = false
            case .auto:
                shouldUseLLM = wordCount >= 20
            }

            if shouldUseLLM {
                postProcessText(rawText, apiKey: apiKey) { [weak self] correctedText in
                    guard let self = self else { return }
                    self.currentText = correctedText

                    let llmDuration = Date().timeIntervalSince(sttEnd)
                    let sttDuration = sttEnd.timeIntervalSince(startTime ?? sttEnd)
                    let totalDuration = sttDuration + llmDuration
                    log(String(format: "⚡ %.1fs STT + %.1fs LLM = %.1fs total", sttDuration, llmDuration, totalDuration))

                    DispatchQueue.main.async {
                        self.delegate?.recorderDidFinishProcessing(text: correctedText, sttTime: sttDuration, llmTime: llmDuration)
                    }

                    let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0
                    saveHistory(raw: rawText, corrected: correctedText, language: detectedLang, duration: duration)
                    try? FileManager.default.removeItem(atPath: filePath)
                    self.isStopping = false
                    log("✅ Done: \"\(correctedText.prefix(100))\"")
                }
            } else {
                let sttDuration = sttEnd.timeIntervalSince(startTime ?? sttEnd)
                log(String(format: "⚡ %.1fs STT + 0.0s LLM = %.1fs total", sttDuration, sttDuration))
                self.currentText = rawText

                DispatchQueue.main.async {
                    self.delegate?.recorderDidFinishProcessing(text: rawText, sttTime: sttDuration, llmTime: 0)
                }

                let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0
                saveHistory(raw: rawText, corrected: rawText, language: detectedLang, duration: duration)
                try? FileManager.default.removeItem(atPath: filePath)
                self.isStopping = false
                log("✅ Done (no LLM): \"\(rawText.prefix(100))\"")
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
