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

        // Target format: 16kHz mono 16-bit signed integer (Groq Whisper compatible)
        guard let wavFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true) else {
            log("❌ Cannot create WAV format")
            isRecording = false
            return
        }

        do {
            audioFile = try AVAudioFile(forWriting: URL(fileURLWithPath: audioFilePath), settings: wavFormat.settings)
        } catch {
            log("❌ Cannot create WAV file: \(error)")
            isRecording = false
            return
        }

        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
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

            // Convert from input format to 16kHz mono Int16 and write to file
            guard let converter = AVAudioConverter(from: inputFormat, to: wavFormat) else { return }
            let ratio = 16000.0 / inputFormat.sampleRate
            let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard outputFrameCount > 0,
                  let convertedBuffer = AVAudioPCMBuffer(pcmFormat: wavFormat, frameCapacity: outputFrameCount) else { return }

            var error: NSError?
            var hasData = true
            converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                if hasData {
                    outStatus.pointee = .haveData
                    hasData = false
                    return buffer
                }
                outStatus.pointee = .noDataNow
                return nil
            }

            if error == nil && convertedBuffer.frameLength > 0 {
                self.writeQueue.async { [weak self] in
                    try? self?.audioFile?.write(from: convertedBuffer)
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
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false; isStopping = true
        log("⏹️ Stopping..."); AudioServicesPlaySystemSound(1114)
        stopEngine()
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
        stopEngine()
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
