import SwiftUI
import AVFoundation

// ═══════════════════════════════════════════════════════════════════
// Ember v2.0 — Onboarding Wizard (4-step sheet)
// Shows on first launch, re-triggerable from Help menu
// ═══════════════════════════════════════════════════════════════════

struct OnboardingView: View {
    @State private var currentStep = 0
    @State private var apiKey: String = ""
    @State private var apiKeySkipped = false
    @State private var showSkipWarning = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Step content
            Group {
                switch currentStep {
                case 0: StepWelcome(onContinue: { advance() })
                case 1: StepAPIKey(
                    apiKey: $apiKey,
                    onContinue: { advance() },
                    onSkip: {
                        apiKeySkipped = true
                        showSkipWarning = true
                    }
                )
                case 2: StepPermissions(onContinue: { advance() })
                case 3: StepReady(
                    onOpenPreferences: { openPreferences() },
                    onGetStarted: { complete() }
                )
                default: EmptyView()
                }
            }
            .frame(width: 480, height: 360)

            // Progress dots + step indicator
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    ForEach(0..<4) { i in
                        Circle()
                            .fill(i == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                            .animation(.easeInOut(duration: 0.2), value: currentStep)
                    }
                }
                Text("Step \(currentStep + 1) of 4")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 20)
        }
        .alert("No API Key", isPresented: $showSkipWarning) {
            Button("Add Later in Preferences") { advance() }
            Button("Enter Key Now", role: .cancel) { showSkipWarning = false }
        } message: {
            Text("Transcription won't work without an API key. You can add it later in Preferences (⌘,).")
        }
        .frame(width: 480)
        .background(.background)
    }

    private func advance() {
        withAnimation(.easeInOut(duration: 0.25)) {
            currentStep = min(currentStep + 1, 3)
        }
    }

    private func complete() {
        UserDefaults.standard.set(true, forKey: "onboardingComplete")
        dismiss()
    }

    private func openPreferences() {
        (NSApp.delegate as? AppDelegate)?.showPreferences()
    }
}

// ═══════════════════════════════════════════════════════════════════
// Step 1 — Welcome
// ═══════════════════════════════════════════════════════════════════

private struct StepWelcome: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)
                .accessibilityLabel("Ember app icon")

            VStack(spacing: 8) {
                Text("Welcome to Ember")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Press your hotkey, speak, release\n— text appears wherever your cursor is.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button("Continue") { onContinue() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return)
        }
        .padding(32)
    }
}

// ═══════════════════════════════════════════════════════════════════
// Step 2 — API Key
// ═══════════════════════════════════════════════════════════════════

private struct StepAPIKey: View {
    @Binding var apiKey: String
    let onContinue: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 8) {
                Text("Enter Your API Key")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Ember uses Groq for fast transcription.\nThe free tier gives you plenty of minutes.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                SecureField("gsk_...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Groq API Key")
                    .onChange(of: apiKey) { _, newVal in
                        if !newVal.isEmpty {
                            EmberConfig.shared.groqKey = newVal
                            EmberConfig.saveField("GROQ_API_KEY", value: newVal)
                        }
                    }

                Button("Get Free Key →") {
                    if let url = URL(string: "https://console.groq.com/keys") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
                .font(.callout)
            }
            .frame(width: 320)

            Spacer()

            HStack(spacing: 16) {
                Button("Skip for now") { onSkip() }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.secondary)

                Button("Continue") { onContinue() }
                    .buttonStyle(.borderedProminent)
                    .disabled(apiKey.isEmpty)
                    .keyboardShortcut(.return)
            }
        }
        .padding(32)
        .onAppear {
            apiKey = EmberConfig.shared.groqKey
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// Step 3 — Permissions
// ═══════════════════════════════════════════════════════════════════

private struct StepPermissions: View {
    let onContinue: () -> Void

    @State private var micStatus: PermissionStatus = .unknown
    @State private var accessibilityStatus: PermissionStatus = .unknown

    enum PermissionStatus {
        case unknown, granted, denied

        var icon: String {
            switch self {
            case .unknown: return "circle.dashed"
            case .granted: return "checkmark.circle.fill"
            case .denied: return "exclamationmark.triangle.fill"
            }
        }

        var color: Color {
            switch self {
            case .unknown: return .secondary
            case .granted: return .green
            case .denied: return .yellow
            }
        }

        var label: String {
            switch self {
            case .unknown: return "Not requested"
            case .granted: return "Granted"
            case .denied: return "Not granted"
            }
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkshield.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 8) {
                Text("Permissions")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Ember needs these permissions to work.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                PermissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    description: "Record your voice for transcription",
                    status: micStatus,
                    buttonLabel: micStatus == .granted ? "Granted" : "Grant Access",
                    buttonDisabled: micStatus == .granted,
                    action: requestMicrophone
                )

                PermissionRow(
                    icon: "accessibility",
                    title: "Accessibility",
                    description: "Paste transcribed text into other apps",
                    status: accessibilityStatus,
                    buttonLabel: accessibilityStatus == .granted ? "Granted" : "Open Settings",
                    buttonDisabled: accessibilityStatus == .granted,
                    action: requestAccessibility
                )
            }
            .frame(width: 380)

            Spacer()

            Button("Continue") { onContinue() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.return)

            Text("You can grant these later — tap Continue to skip.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .onAppear { checkPermissions() }
    }

    private func checkPermissions() {
        // Microphone
        let avStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        switch avStatus {
        case .authorized: micStatus = .granted
        case .denied, .restricted: micStatus = .denied
        default: micStatus = .unknown
        }

        // Accessibility
        accessibilityStatus = AXIsProcessTrusted() ? .granted : .denied
    }

    private func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async {
                micStatus = granted ? .granted : .denied
            }
        }
    }

    private func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
        // Open System Settings directly
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        // Re-check after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            accessibilityStatus = AXIsProcessTrusted() ? .granted : .denied
        }
    }
}

private struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let status: StepPermissions.PermissionStatus
    let buttonLabel: String
    let buttonDisabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: status.icon)
                    .foregroundStyle(status.color)
                    .font(.callout)
                    .accessibilityLabel(status.label)

                Button(buttonLabel) { action() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(buttonDisabled)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.background.secondary)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(status.label). \(description)")
    }
}

// ═══════════════════════════════════════════════════════════════════
// Step 4 — Ready
// ═══════════════════════════════════════════════════════════════════

private struct StepReady: View {
    let onOpenPreferences: () -> Void
    let onGetStarted: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "party.popper.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 8) {
                Text("You're all set!")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "keyboard")
                            .foregroundStyle(.secondary)
                        Text("Press")
                            .foregroundStyle(.secondary)
                        Text("`")
                            .font(.title3)
                            .fontWeight(.bold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.secondary.opacity(0.15))
                            )
                        Text("to start recording")
                            .foregroundStyle(.secondary)
                    }
                    .font(.body)
                }
            }

            Spacer()

            HStack(spacing: 16) {
                Button("Open Preferences") {
                    onGetStarted()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        onOpenPreferences()
                    }
                }
                .buttonStyle(.bordered)

                Button("Get Started") { onGetStarted() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.return)
            }
        }
        .padding(32)
    }
}

// ═══════════════════════════════════════════════════════════════════
// Onboarding Host Window — transparent NSWindow wrapper
// ═══════════════════════════════════════════════════════════════════

class OnboardingWindowController {
    private var window: NSWindow?

    func show() {
        if let w = window, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingVC = NSHostingController(rootView: OnboardingView())

        let w = NSWindow(contentViewController: hostingVC)
        w.title = "Welcome to Ember"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        window = w

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func shouldShow() -> Bool {
        return !UserDefaults.standard.bool(forKey: "onboardingComplete")
    }
}

