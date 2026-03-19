import Foundation

// ═══════════════════════════════════════════════════════════════════
// Groq Whisper STT + LLM Post-Processing
// ═══════════════════════════════════════════════════════════════════

// ─── Groq Whisper STT (fast, free, one API key for both STT + LLM) ──
func transcribeWithGroq(filePath: String, apiKey: String, language: String, completion: @escaping (String) -> Void) {
    guard !apiKey.isEmpty else {
        log("❌ No GROQ_API_KEY!"); completion(""); return
    }

    guard let fileData = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else {
        log("❌ Cannot read audio file"); completion(""); return
    }

    let url = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
    body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"language\"\r\n\r\n\(language)\r\n".data(using: .utf8)!)
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

// ─── LLM Post-Processing (Groq) ─────────────────────────────────
// After recording stops, send raw text to LLM for grammar/punctuation fix
func postProcessText(_ rawText: String, apiKey: String, completion: @escaping (String) -> Void) {
    guard !apiKey.isEmpty else {
        log("⚠️ No GROQ_API_KEY — skipping post-processing")
        completion(rawText)
        return
    }

    let url = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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
