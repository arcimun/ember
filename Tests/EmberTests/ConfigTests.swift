// Tests for Config .env parsing and history JSON backward compatibility
// Requires Xcode to run (swift test). CI has Xcode — local dev may not.
// See: .github/workflows/release.yml

#if canImport(XCTest)
import XCTest
import Foundation

final class ConfigTests: XCTestCase {
    private func parseEnv(_ contents: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in contents.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("#") || !t.contains("=") { continue }
            let parts = t.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let k = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let v = String(parts[1]).trimmingCharacters(in: .whitespaces)
            result[k] = v
        }
        return result
    }

    func testParseBasicEnv() {
        let env = parseEnv("GROQ_API_KEY=gsk_test123\nDICTATION_LANGUAGE=ru\n")
        XCTAssertEqual(env["GROQ_API_KEY"], "gsk_test123")
        XCTAssertEqual(env["DICTATION_LANGUAGE"], "ru")
    }

    func testParseEnvWithComments() {
        let env = parseEnv("# Comment\nGROQ_API_KEY=gsk_abc\n")
        XCTAssertEqual(env["GROQ_API_KEY"], "gsk_abc")
        XCTAssertEqual(env.count, 1)
    }

    func testParseEnvWithSpaces() {
        let env = parseEnv("  GROQ_API_KEY = gsk_spaced  \n  THEME = aurora  \n")
        XCTAssertEqual(env["GROQ_API_KEY"], "gsk_spaced")
        XCTAssertEqual(env["THEME"], "aurora")
    }

    func testParseEnvEmpty() {
        XCTAssertTrue(parseEnv("").isEmpty)
    }

    func testParseEnvEqualsInValue() {
        let env = parseEnv("GROQ_API_KEY=gsk_abc=def=ghi\n")
        XCTAssertEqual(env["GROQ_API_KEY"], "gsk_abc=def=ghi")
    }

    func testOldHistoryFormat() throws {
        let old: [String: Any] = ["text": "Привет мир", "duration": 3.5]
        let data = try JSONSerialization.data(withJSONObject: old)
        let p = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let corrected = (p["corrected"] as? String) ?? (p["text"] as? String) ?? ""
        XCTAssertEqual(corrected, "Привет мир")
        XCTAssertNil(p["raw"])
    }

    func testNewHistoryFormat() throws {
        let new: [String: Any] = ["raw": "привет", "corrected": "Привет!", "duration_ms": 3500]
        let data = try JSONSerialization.data(withJSONObject: new)
        let p = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let corrected = (p["corrected"] as? String) ?? (p["text"] as? String) ?? ""
        XCTAssertEqual(corrected, "Привет!")
        XCTAssertEqual(p["raw"] as? String, "привет")
    }
}
#endif
