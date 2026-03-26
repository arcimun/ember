import SwiftUI
import AVFoundation

// ═══════════════════════════════════════════════════════════════════
// Ember v2.0 — SwiftUI Preferences Window
// Tabs: General | Audio | Themes
// ═══════════════════════════════════════════════════════════════════

struct SettingsView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(0)

            AudioTab()
                .tabItem { Label("Audio", systemImage: "waveform") }
                .tag(1)

            ThemesTab()
                .tabItem { Label("Themes", systemImage: "paintpalette") }
                .tag(2)
        }
        .frame(width: 550, height: 420)
        .padding(.top, 4)
    }
}

// ═══════════════════════════════════════════════════════════════════
// General Tab
// ═══════════════════════════════════════════════════════════════════

private struct GeneralTab: View {
    @State private var apiKey: String = EmberConfig.shared.groqKey
    @State private var apiKeyStatus: APIKeyStatus = .unchecked
    @State private var isVerifying = false
    @State private var language: String = EmberConfig.shared.language
    @State private var autoPaste: Bool = true  // always-on in v2.0 — future setting

    enum APIKeyStatus {
        case unchecked, valid, invalid
        var color: Color {
            switch self {
            case .unchecked: return .secondary
            case .valid: return .green
            case .invalid: return .red
            }
        }
        var icon: String {
            switch self {
            case .unchecked: return "circle.dashed"
            case .valid: return "checkmark.circle.fill"
            case .invalid: return "xmark.circle.fill"
            }
        }
        var label: String {
            switch self {
            case .unchecked: return "Not verified"
            case .valid: return "Valid"
            case .invalid: return "Invalid"
            }
        }
    }

    let languages: [(code: String, label: String)] = [
        ("auto", "Auto-detect"),
        ("en", "English"),
        ("ru", "Russian"),
        ("es", "Spanish"),
        ("zh", "Chinese"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("fr", "French"),
        ("de", "German"),
        ("pt", "Portuguese"),
        ("ar", "Arabic"),
        ("hi", "Hindi"),
        ("it", "Italian"),
        ("nl", "Dutch"),
        ("pl", "Polish"),
        ("tr", "Turkish"),
        ("uk", "Ukrainian"),
        ("sv", "Swedish"),
        ("da", "Danish"),
        ("fi", "Finnish"),
        ("no", "Norwegian"),
    ]

    var body: some View {
        Form {
            // ── API Key ──
            Section {
                HStack(spacing: 8) {
                    SecureField("gsk_...", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Groq API Key")
                        .onChange(of: apiKey) { _, _ in
                            apiKeyStatus = .unchecked
                            saveApiKey()
                        }

                    Button(action: verifyApiKey) {
                        if isVerifying {
                            ProgressView().scaleEffect(0.7).frame(width: 16, height: 16)
                        } else {
                            Text("Verify")
                        }
                    }
                    .disabled(apiKey.isEmpty || isVerifying)
                    .frame(width: 60)

                    Image(systemName: apiKeyStatus.icon)
                        .foregroundStyle(apiKeyStatus.color)
                        .accessibilityLabel(apiKeyStatus.label)
                }

                HStack {
                    Image(systemName: apiKeyStatus.icon)
                        .foregroundStyle(apiKeyStatus.color)
                        .font(.caption)
                    Text(apiKeyStatus.label)
                        .font(.caption)
                        .foregroundStyle(apiKeyStatus.color)
                    Spacer()
                    Button("Get Free Key") {
                        if let url = URL(string: "https://console.groq.com/keys") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            } header: {
                Text("API Key")
            }

            // ── Language ──
            Section {
                Picker("Language", selection: $language) {
                    ForEach(languages, id: \.code) { lang in
                        Text(lang.label).tag(lang.code)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: language) { _, newVal in
                    EmberConfig.shared.language = newVal
                    EmberConfig.saveField("DICTATION_LANGUAGE", value: newVal)
                }
            } header: {
                Text("Language")
            }

            // ── Auto-paste ──
            Section {
                Toggle("Automatically paste transcribed text", isOn: .constant(true))
                    .disabled(true)
                Text("Requires Accessibility permission in System Settings → Privacy & Security → Accessibility.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Behavior")
            }

            // ── Hotkey ──
            Section {
                HotkeyRecorderView()
            } header: {
                Text("Recording Hotkey")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            apiKey = EmberConfig.shared.groqKey
            language = EmberConfig.shared.language
        }
    }

    private func saveApiKey() {
        EmberConfig.shared.groqKey = apiKey
        EmberConfig.saveField("GROQ_API_KEY", value: apiKey)
    }

    private func verifyApiKey() {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        isVerifying = true
        apiKeyStatus = .unchecked

        let url = URL(string: "https://api.groq.com/openai/v1/models")!
        var req = URLRequest(url: url)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10

        URLSession.shared.dataTask(with: req) { _, response, _ in
            DispatchQueue.main.async {
                self.isVerifying = false
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    self.apiKeyStatus = .valid
                    self.saveApiKey()
                    EmberConfig.shared.load()
                } else {
                    self.apiKeyStatus = .invalid
                }
            }
        }.resume()
    }
}

// ═══════════════════════════════════════════════════════════════════
// Audio Tab
// ═══════════════════════════════════════════════════════════════════

private struct AudioTab: View {
    @State private var vadAutoStop: Bool = EmberConfig.shared.vadAutoStop
    @State private var endDelay: Double = EmberConfig.shared.endDelay
    @State private var llmCorrection: LLMCorrectionMode = EmberConfig.shared.llmCorrection

    var body: some View {
        Form {
            // ── VAD Auto-Stop ──
            Section {
                Toggle("Auto-stop when you stop speaking", isOn: $vadAutoStop)
                    .onChange(of: vadAutoStop) { _, newVal in
                        EmberConfig.shared.vadAutoStop = newVal
                        EmberConfig.saveField("VAD_AUTO_STOP", value: newVal ? "true" : "false")
                    }
                Text("Voice Activity Detection — recording stops automatically after silence.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Voice Activity Detection")
            }

            // ── End Delay ──
            Section {
                HStack {
                    Slider(value: $endDelay, in: 0.3...3.0, step: 0.1) {
                        Text("End Delay")
                    }
                    .disabled(!vadAutoStop)
                    .onChange(of: endDelay) { _, newVal in
                        EmberConfig.shared.endDelay = newVal
                        EmberConfig.saveField("END_DELAY", value: String(format: "%.1f", newVal))
                    }
                    Text(String(format: "%.1f sec", endDelay))
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                        .foregroundStyle(vadAutoStop ? .primary : .secondary)
                }
                .accessibilityLabel("Silence end delay: \(String(format: "%.1f", endDelay)) seconds")
            } header: {
                Text("End Delay")
            } footer: {
                Text("Seconds of silence before auto-stop triggers. Requires Auto-stop enabled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // ── Input Device ──
            Section {
                HStack {
                    Image(systemName: "mic")
                        .foregroundStyle(.secondary)
                    Text("Uses system default input device")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Sound Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                }
            } header: {
                Text("Input Device")
            }

            // ── LLM Correction ──
            Section {
                Picker("LLM Correction", selection: $llmCorrection) {
                    Text("Never (fastest)").tag(LLMCorrectionMode.never)
                    Text("Auto (long text)").tag(LLMCorrectionMode.auto)
                    Text("Always").tag(LLMCorrectionMode.always)
                }
                .pickerStyle(.menu)
                .onChange(of: llmCorrection) { _, newVal in
                    EmberConfig.shared.llmCorrection = newVal
                    EmberConfig.saveField("LLM_CORRECTION", value: newVal.rawValue)
                }
                Text("Post-processes transcription with LLM to fix grammar and punctuation. Adds latency.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Post-Processing")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            vadAutoStop = EmberConfig.shared.vadAutoStop
            endDelay = EmberConfig.shared.endDelay
            llmCorrection = EmberConfig.shared.llmCorrection
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// Themes Tab
// ═══════════════════════════════════════════════════════════════════

private struct ThemesTab: View {
    @State private var selectedTheme: String = EmberConfig.shared.theme
    @State private var digitalRainColorMode: DigitalRainColorMode = .emerald

    enum DigitalRainColorMode: String, CaseIterable {
        case emerald = "emerald"
        case ember = "ember"
        case blue = "blue"

        var label: String {
            switch self {
            case .emerald: return "Emerald"
            case .ember: return "Ember"
            case .blue: return "Blue"
            }
        }

        var color: Color {
            switch self {
            case .emerald: return Color(red: 0, green: 0.9, blue: 0.4)
            case .ember: return Color(red: 1.0, green: 0.4, blue: 0.1)
            case .blue: return Color(red: 0.2, green: 0.6, blue: 1.0)
            }
        }
    }

    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
    ]

    var themes: [String] {
        let available = PlasmaOverlayWindow.availableThemes()
        return available.isEmpty ? ["digital-rain-2", "minimal", "fire", "ocean"] : available
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(themes, id: \.self) { theme in
                        ThemeCard(
                            name: theme,
                            isSelected: selectedTheme == theme,
                            action: {
                                selectedTheme = theme
                                EmberConfig.shared.theme = theme
                                EmberConfig.saveField("THEME", value: theme)
                                // Notify overlay via notification (AppDelegate will apply)
                                NotificationCenter.default.post(name: .emberThemeChanged, object: theme)
                            }
                        )
                    }
                }
                .padding(16)
            }

            // Color mode picker for Digital Rain 2
            if selectedTheme == "digital-rain-2" {
                Divider()
                HStack {
                    Text("Color Mode:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Picker("Color Mode", selection: $digitalRainColorMode) {
                        ForEach(DigitalRainColorMode.allCases, id: \.self) { mode in
                            HStack {
                                Circle()
                                    .fill(mode.color)
                                    .frame(width: 10, height: 10)
                                Text(mode.label)
                            }
                            .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
    }
}

private struct ThemeCard: View {
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var displayName: String {
        name.replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    var themeColor: Color {
        switch name {
        case "digital-rain-2": return Color(red: 0, green: 0.8, blue: 0.3)
        case "fire", "ember-fire": return Color(red: 1.0, green: 0.35, blue: 0.0)
        case "ocean", "ocean-waves": return Color(red: 0.1, green: 0.5, blue: 0.9)
        case "minimal": return Color.gray
        case "aurora": return Color(red: 0.4, green: 0.8, blue: 0.6)
        case "plasma": return Color(red: 0.7, green: 0.2, blue: 0.9)
        case "neon": return Color(red: 0.0, green: 1.0, blue: 0.8)
        case "sunset": return Color(red: 1.0, green: 0.5, blue: 0.2)
        default: return Color.accentColor
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [themeColor.opacity(0.8), themeColor.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 60)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                    )
                    .overlay(
                        isSelected ? Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white)
                            .font(.title2) : nil
                    )

                Text(displayName)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(displayName) theme\(isSelected ? ", selected" : "")")
    }
}

// ═══════════════════════════════════════════════════════════════════
// Notification for theme changes from Preferences
// ═══════════════════════════════════════════════════════════════════

extension Notification.Name {
    static let emberThemeChanged = Notification.Name("emberThemeChanged")
}

