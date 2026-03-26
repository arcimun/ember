import SwiftUI
import Carbon.HIToolbox

// ═══════════════════════════════════════════════════════════════════
// Hotkey Recorder — captures a key combo for recording trigger
// ═══════════════════════════════════════════════════════════════════

/// Human-readable name for a Carbon keyCode
func keyCodeToString(_ keyCode: UInt32) -> String {
    let names: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N",
        46: "M", 47: ".", 50: "`",
        // Function keys
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
        101: "F9", 103: "F11", 105: "F13", 107: "F14", 109: "F10",
        111: "F12", 113: "F15", 115: "Home", 116: "PgUp", 117: "Delete",
        118: "F4", 119: "End", 120: "F2", 121: "PgDn", 122: "F1",
        // Special
        36: "Return", 48: "Tab", 49: "Space", 51: "Backspace", 53: "Escape",
        76: "Enter",
    ]
    return names[keyCode] ?? "Key\(keyCode)"
}

/// Convert Carbon modifier mask to human-readable symbols
func modifiersToString(_ mods: UInt32) -> String {
    var parts: [String] = []
    if mods & UInt32(controlKey) != 0 { parts.append("⌃") }
    if mods & UInt32(optionKey) != 0 { parts.append("⌥") }
    if mods & UInt32(shiftKey) != 0 { parts.append("⇧") }
    if mods & UInt32(cmdKey) != 0 { parts.append("⌘") }
    return parts.joined()
}

/// Convert NSEvent modifierFlags to Carbon modifier mask
func nsModifiersToCarbonMask(_ flags: NSEvent.ModifierFlags) -> UInt32 {
    var mask: UInt32 = 0
    if flags.contains(.command) { mask |= UInt32(cmdKey) }
    if flags.contains(.option) { mask |= UInt32(optionKey) }
    if flags.contains(.control) { mask |= UInt32(controlKey) }
    if flags.contains(.shift) { mask |= UInt32(shiftKey) }
    return mask
}

/// Full display string for a hotkey combo
func hotkeyDisplayString(keyCode: UInt32, modifiers: UInt32) -> String {
    let modStr = modifiersToString(modifiers)
    let keyStr = keyCodeToString(keyCode)
    return modStr.isEmpty ? keyStr : "\(modStr)\(keyStr)"
}

// System-reserved shortcuts that should not be registered
private let reservedCombos: Set<String> = [
    "⌘Q", "⌘W", "⌘Tab", "⌘Space", "⌘⇧3", "⌘⇧4", "⌘⇧5",
    "⌃Space", "⌃⌘Space"
]

// ═══════════════════════════════════════════════════════════════════
// NSView-based key capture (SwiftUI can't intercept raw keyDown)
// ═══════════════════════════════════════════════════════════════════

class HotkeyRecorderNSView: NSView {
    var onKeyCapture: ((UInt32, UInt32) -> Void)?
    var isRecording = false

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return }

        let keyCode = UInt32(event.keyCode)

        // Ignore modifier-only presses
        if keyCode == 55 || keyCode == 54 || keyCode == 56 || keyCode == 58 ||
           keyCode == 59 || keyCode == 60 || keyCode == 61 || keyCode == 62 { return }

        // Escape cancels recording
        if keyCode == 53 {
            isRecording = false
            window?.makeFirstResponder(nil)
            return
        }

        let carbonMods = nsModifiersToCarbonMask(event.modifierFlags)

        // Check reserved
        let display = hotkeyDisplayString(keyCode: keyCode, modifiers: carbonMods)
        if reservedCombos.contains(display) {
            NSSound.beep()
            return
        }

        isRecording = false
        window?.makeFirstResponder(nil)
        onKeyCapture?(keyCode, carbonMods)
    }

    override func flagsChanged(with event: NSEvent) {
        // Allow flagsChanged to propagate normally
    }
}

struct HotkeyRecorderRepresentable: NSViewRepresentable {
    @Binding var isRecording: Bool
    var onCapture: (UInt32, UInt32) -> Void

    func makeNSView(context: Context) -> HotkeyRecorderNSView {
        let view = HotkeyRecorderNSView()
        view.onKeyCapture = onCapture
        return view
    }

    func updateNSView(_ nsView: HotkeyRecorderNSView, context: Context) {
        nsView.isRecording = isRecording
        nsView.onKeyCapture = onCapture
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════
// SwiftUI View — the recorder button + display
// ═══════════════════════════════════════════════════════════════════

struct HotkeyRecorderView: View {
    @State private var isRecording = false
    @State private var keyCode: UInt32
    @State private var modifiers: UInt32
    @State private var showConflict = false

    init() {
        _keyCode = State(initialValue: EmberConfig.shared.hotkeyKeyCode)
        _modifiers = State(initialValue: EmberConfig.shared.hotkeyModifiers)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Display current hotkey
                Text(hotkeyDisplayString(keyCode: keyCode, modifiers: modifiers))
                    .font(.system(.title3, design: .monospaced, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isRecording ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isRecording ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: 1)
                    )

                Button(isRecording ? "Press a key…" : "Change") {
                    isRecording.toggle()
                }
                .buttonStyle(.bordered)

                if keyCode != 50 || modifiers != 0 {
                    Button("Reset") {
                        setHotkey(keyCode: 50, modifiers: 0)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }
            }

            if isRecording {
                Text("Press any key or combo. Escape to cancel.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if showConflict {
                Text("This shortcut is reserved by the system.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Hidden NSView that actually captures keyDown
            HotkeyRecorderRepresentable(isRecording: $isRecording) { newCode, newMods in
                setHotkey(keyCode: newCode, modifiers: newMods)
            }
            .frame(width: 0, height: 0)
        }
    }

    private func setHotkey(keyCode newCode: UInt32, modifiers newMods: UInt32) {
        keyCode = newCode
        modifiers = newMods
        isRecording = false
        showConflict = false

        // Save to config
        EmberConfig.shared.hotkeyKeyCode = newCode
        EmberConfig.shared.hotkeyModifiers = newMods
        EmberConfig.saveField("HOTKEY_KEYCODE", value: "\(newCode)")
        EmberConfig.saveField("HOTKEY_MODIFIERS", value: "\(newMods)")

        // Re-register with Carbon
        reregisterRecordingHotkey()

        log("⌨️ Hotkey changed to: \(hotkeyDisplayString(keyCode: newCode, modifiers: newMods))")
    }
}
