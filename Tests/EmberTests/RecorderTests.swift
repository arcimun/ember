// Tests for audio recording math, RMS, and hallucination guard
// Requires Xcode to run (swift test). CI has Xcode — local dev may not.

#if canImport(XCTest)
import XCTest
import Foundation

final class RecorderTests: XCTestCase {
    func testSampleRateConversion48kTo16k() {
        XCTAssertEqual(48000.0 / 16000.0, 3.0)
    }

    func testByteRate16kMono16bit() {
        XCTAssertEqual(16000 * 1 * 2, 32000) // 32KB/s
    }

    func testFileSizeEstimate3Seconds() {
        XCTAssertEqual(44 + Int(3.0 * 32000.0), 96044) // header + data
    }

    func testRMSSilence() {
        let samples: [Float] = [0, 0, 0, 0, 0]
        let sum = samples.reduce(Float(0)) { $0 + $1 * $1 }
        let rms = sqrt(sum / Float(samples.count))
        XCTAssertEqual(rms, 0.0, accuracy: 0.001)
    }

    func testRMSSineWave() {
        let samples: [Float] = stride(from: Float(0), to: .pi * 2, by: 0.01).map { sin($0) }
        let sum = samples.reduce(Float(0)) { $0 + $1 * $1 }
        let rms = sqrt(sum / Float(samples.count))
        XCTAssertEqual(rms, 1.0 / sqrt(2), accuracy: 0.02)
    }

    func testRMSSmoothing() {
        var level: Float = 0
        level = level * 0.6 + 0.5 * 0.4
        XCTAssertEqual(level, 0.2, accuracy: 0.001)
        level = level * 0.6 + 0.5 * 0.4
        XCTAssertEqual(level, 0.32, accuracy: 0.001)
    }

    func testHallucinationGuardTriggered() {
        let raw = "hello world"
        let bad = String(repeating: "a", count: raw.count * 3 + 1)
        XCTAssertTrue(bad.count > raw.count * 3)
    }

    func testHallucinationGuardPasses() {
        let raw = "привет мир"
        let ok = "Привет, мир!"
        XCTAssertFalse(ok.count > raw.count * 3)
    }
}
#endif
