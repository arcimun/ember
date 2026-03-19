import Foundation
import Cocoa
import AudioToolbox
import AVFoundation

// ═══════════════════════════════════════════════════════════════════
// Audio Recording — WAV file via AVAudioEngine (native)
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
                try? self?.audioFile?.write(from: buffer)
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
