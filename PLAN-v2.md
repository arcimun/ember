<!-- /autoplan restore point: /Users/ihyart/.gstack/projects/ember/main-autoplan-restore-20260325-201743.md -->
# Ember v2.0 — Swift Native Upgrade

## Strategic Decision

**Path A chosen:** Enhance existing Swift app with SwiftUI windows. No Electron rewrite.
Electron (Path B) deferred — may revisit for cross-platform (Windows) later.

**Rationale (CEO Review):**
- Working native app → don't rewrite in heavier stack for CSS effects
- Audio recording, hotkeys, Accessibility paste — all reliable in Swift, risky in Electron
- 5MB bundle vs 100MB — competitive advantage vs Superwhisper/Wispr
- SwiftUI on macOS 14+ gives proper Settings, Sheets, WindowGroups
- ~2 days CC time vs ~5 days for Electron migration

## Current State (v1.8.0)

```
Sources/
├── App.swift           — AppDelegate, menu bar, hotkey, state machine
├── Config.swift        — Config loading, API key dialog (NSAlert)
├── Overlay.swift       — NSWindow + WKWebView overlay, themes
├── Recorder.swift      — AVAudioEngine, WAV recording, VAD
├── STT.swift           — Groq Whisper API, LLM post-processing
└── History.swift       — JSON file history saving

Resources/themes/       — 16 HTML overlay themes
```

**What works:** hotkey, overlay (16 themes), Groq STT (<1s), auto-paste, VAD, auto-update (Sparkle), multi-display, history saving.

**What's missing:** proper Preferences window, onboarding, history viewer, About window, native menus.

## Target: v2.0 Scope

### Must Have (P0)
1. **SwiftUI Preferences window** (⌘,) — tabbed: General | Audio | Themes | Advanced
2. **Onboarding flow** — first-run sheet: welcome → API key → mic permission → try it
3. **About window** — standard macOS About (icon, version, links)
4. **Native menu bar** — Ember menu (About, Preferences, Quit) + Edit + Window + Help
5. **Version display** — in menu bar dropdown + About window

### Should Have (P1)
6. **History viewer** (⌘H) — SwiftUI List of past transcriptions, copy, search
7. **Theme preview** — grid of theme thumbnails in Preferences
8. **Hotkey recorder** — proper key combo recorder in Preferences (not just backtick)

### Nice to Have (P2 — defer if needed)
9. **System tray quick controls** — toggle auto-stop, switch theme from menu
10. **Apple Developer ID + notarization** — $99/yr, eliminates Gatekeeper issues

## Architecture

### New Files

```
Sources/
├── App.swift           — MODIFY: add SwiftUI lifecycle, native menus
├── Config.swift        — MODIFY: add @Observable wrapper for SwiftUI binding
├── Overlay.swift       — KEEP as-is
├── Recorder.swift      — KEEP as-is
├── STT.swift           — KEEP as-is (already has audio length fix)
├── History.swift       — MODIFY: add query/search methods
├── SettingsView.swift  — NEW: SwiftUI tabbed preferences
├── OnboardingView.swift — NEW: first-run wizard
├── HistoryView.swift   — NEW: transcription history list
└── ThemePreview.swift  — NEW: theme grid with live previews
```

### SwiftUI Integration Strategy

macOS 14+ supports `Settings` scene in SwiftUI App lifecycle. But Ember uses `NSApplicationDelegate` (AppKit) for:
- Global hotkeys (Carbon API)
- WKWebView overlay
- Menu bar status item

**Approach:** Keep AppKit lifecycle, host SwiftUI views via `NSHostingController`:
```swift
// Preferences window
let settingsWindow = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
settingsWindow.title = "Ember Preferences"
```

This is the standard pattern for mixed AppKit+SwiftUI apps.

### Settings Architecture

```swift
// Config becomes @Observable for SwiftUI binding
@Observable
class EmberConfig {
    var groqKey: String
    var language: String
    var theme: String
    var hotkey: String
    var llmCorrection: LLMCorrectionMode
    var vadAutoStop: Bool
    var endDelay: Double

    func save() { /* write to ~/.config/ember/config.env */ }
}
```

### Preferences Tabs

**General:**
- Language: Picker (auto, en, ru, es, zh, ja, +40 more)
- Hotkey: KeyRecorder view
- Auto-paste: Toggle + explanation
- Launch at login: Toggle

**Audio:**
- Input device: Picker (system audio devices)
- VAD auto-stop: Toggle
- End delay: Slider (0.3-3.0s)
- Audio level indicator (live)

**Themes:**
- Grid of 16 theme thumbnails (WebView snapshots)
- Click to select, live preview in overlay
- Color mode switcher (for Digital Rain 2: emerald/ember/blue)

**Advanced:**
- API Key: SecureField + "Get Free Key" link
- LLM Correction: Picker (never/auto/always)
- Data directory: path display
- Reset to defaults button

### Onboarding Flow

SwiftUI Sheet, 4 steps:
1. Welcome: app icon + "Press hotkey, speak, text appears" + Continue
2. API Key: SecureField + "Get Free Key" button + Skip
3. Permissions: "Grant Microphone" button + "Grant Accessibility" button
4. Try it: "Press ` and say something!" + live overlay demo

Shown once (flag in UserDefaults). Can be re-triggered from Help menu.

### History Viewer

```swift
struct HistoryView: View {
    @State var entries: [HistoryEntry]
    @State var searchText: String

    var body: some View {
        NavigationSplitView {
            List(filtered) { entry in
                HistoryRow(entry: entry)
            }
            .searchable(text: $searchText)
        } detail: {
            // Selected entry detail
        }
    }
}
```

Reads from `~/.config/ember/history/*.json` (existing format).

## Design

- **Dark mode default** (system-aware, follows macOS appearance)
- **SF Pro** system font (native macOS, no custom fonts needed)
- **Accent color**: system blue (follows macOS accent color preference)
- **Window size**: Preferences ~600x450, History ~700x500
- **Corner radius**: system default (macOS native)
- **Vibrancy**: NSVisualEffectView sidebar in History (native translucency)

No Liquid Glass needed — native macOS design IS the premium feel for a native app.

## Implementation Plan

### Phase 1: Config + Menus (~30min CC)
- Make Config @Observable
- Add native NSMenu (Ember, Edit, Window, Help)
- Wire ⌘, to Preferences, ⌘H to History
- Add About Ember menu item (standard NSApp.orderFrontStandardAboutPanel)

### Phase 2: Preferences Window (~1hr CC)
- SettingsView.swift with TabView (General, Audio, Themes, Advanced)
- Wire all config bindings
- Hotkey recorder component
- Theme preview grid

### Phase 3: Onboarding (~30min CC)
- OnboardingView.swift — 4-step sheet
- First-run detection (UserDefaults flag)
- Permission request buttons
- Help menu → "Show Welcome Guide"

### Phase 4: History Viewer (~30min CC)
- HistoryView.swift — NavigationSplitView
- Read existing JSON history files
- Search, copy, delete
- ⌘H shortcut

### Phase 5: Polish + Release (~30min CC)
- Version badge in menu dropdown
- Keyboard shortcuts consistency
- Build + test on clean system
- Bump to v2.0, update README, appcast
- PKG + DMG build

## Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| SwiftUI on macOS 14 limitations | Low | Fallback to NSHostingController, well-documented |
| Mixed AppKit+SwiftUI lifecycle | Low | Standard pattern, used by Apple's own apps |
| Theme preview performance | Low | Lazy loading, cache thumbnails |
| Hotkey recorder conflicts | Medium | Test with existing Carbon API |
| Breaking existing config | Low | Same ~/.config/ember/config.env format |

## Success Criteria

1. Preferences window opens with ⌘, — all settings work
2. Onboarding completes on first run without confusion
3. History viewer shows past transcriptions with search
4. About window shows correct version
5. All existing features unchanged (overlay, STT, paste)
6. Cold start still < 1 second (no Electron overhead)
7. Bundle size stays < 10MB
8. All 16 themes work as before

## NOT in Scope (deferred)

- Electron/React rewrite (Path B — future, maybe for Windows)
- Liquid Glass effects (CSS-only, requires Chromium)
- Cross-platform (Windows/Linux)
- Plugin system
- AI suggestions from history
- Apple Developer ID notarization ($99/yr — separate decision)

## Pre-Implementation Fixes (from Eng Review — do BEFORE new features)

### Fix 0A: Config struct → class singleton
```swift
// Config.swift — change struct to @Observable class
@Observable
class EmberConfig {
    static let shared = EmberConfig()
    // ... all fields ...
    private init() { self.load() }
    func load() { /* read from file, populate self */ }
    func save() { /* write to file */ }
}
// Replace all `config = Config.load()` → `EmberConfig.shared.load()`
```

### Fix 0B: Package.swift target → macOS 14
```swift
platforms: [.macOS(.v14)]  // was .v13 — needed for @Observable
```

### Fix 0C: Add NSAccessibilityUsageDescription to Info.plist
```xml
<key>NSAccessibilityUsageDescription</key>
<string>Ember needs Accessibility access to paste transcribed text into other apps.</string>
```

### Fix 0D: Guard developerExtrasEnabled with DEBUG
```swift
#if DEBUG
webConfig.preferences.setValue(true, forKey: "developerExtrasEnabled")
#endif
```

### Fix 0E: Serialize first-run dialogs (mic → api key, not parallel)
Chain mic permission callback → then show API key dialog.

### Fix 0F: Temp file cleanup on launch
```swift
// applicationDidFinishLaunching — clean stale audio files
for file in FileManager.default.contentsOfDirectory(atPath: "/tmp") where file.hasPrefix("ember_") {
    // delete if older than 1 hour
}
```

## Design Decisions (from Design Review)

### D1: Settings apply LIVE (no Save button)
macOS standard. Each toggle/slider applies immediately. Config auto-saves on change.

### D2: API Key moves to General tab (not Advanced)
Without key, app doesn't work. It's the first thing users need.

### D3: Onboarding is non-dismissible until step 3
Can't Escape/close until permissions granted. Step 2 (API Key) Skip → warning toast.

### D4: History detail panel spec
Shows: timestamp, duration, detected language, full text (selectable), Copy button, Delete button (with confirmation alert).

### D5: Empty states
- History empty: "No transcriptions yet — press ` to start"
- Search no results: "No results for «query»"
- History error: "Can't read history files"

### D6: Theme thumbnails = static PNGs (not WebView snapshots)
Pre-generate at build time. `Resources/thumbnails/{theme-name}.png`. Zero runtime cost.

### D7: Hotkey recorder = HotKey library (Sam Soffes, MIT)
Don't build custom. `github.com/soffes/HotKey` handles Carbon, conflicts, modifiers.

### D8: Audio device picker → deferred to v2.1
Core Audio complexity too high. Show "Uses system default" + link to System Settings.

### D9: VoiceOver labels required on all custom components
Theme grid buttons, history rows, audio indicator, permission buttons.

## Updated Phase Plan (with fixes integrated)

### Phase 0: Pre-Flight Fixes (~30min CC)
- Fix 0A-0F from Eng Review
- Config → @Observable class singleton
- Package.swift → macOS 14
- Info.plist + developerExtrasEnabled
- Temp file cleanup
- Dialog serialization

### Phase 1: Menus + About (~15min CC)
- Native NSMenu (Ember, Edit, Window, Help)
- ⌘, → Preferences, ⌘H → History
- Standard About panel

### Phase 2: Preferences (~1hr CC)
- SettingsView with TabView: General | Audio | Themes
- General: API key (SecureField + Verify), language, hotkey (HotKey lib), auto-paste, launch at login
- Audio: VAD toggle, end delay slider (step: 0.1s, label), live audio indicator
- Themes: static PNG grid, click to select, color mode for DR2
- All: live apply, VoiceOver labels

### Phase 3: Onboarding (~30min CC)
- 4-step non-dismissible sheet
- Step 2 Skip → warning + flag for menu reminder
- Step 3: permission buttons with granted/denied states
- Step 4: try it demo with overlay positioning note
- Final summary screen before dismiss

### Phase 4: History (~30min CC)
- NavigationSplitView with search
- Detail panel (D4 spec)
- Delete with confirmation
- Window reuse fix (Finding 2.5)
- Empty states (D5)

### Phase 5: Polish + Release (~30min CC)
- Version badge in menu
- Config corruption handling (log + backup)
- Build + test
- v2.0 bump, README, appcast, PKG

## Decision Audit Trail

| # | Phase | Decision | Principle | Rationale | Rejected |
|---|-------|----------|-----------|-----------|----------|
| 1 | CEO | Path A (Swift) over Path B (Electron) | P5 explicit | Working native app, don't rewrite for CSS effect | Electron rewrite |
| 2 | CEO | SELECTIVE EXPANSION mode | P3 pragmatic | Add Settings+History+Onboarding, don't rebuild everything | Full rewrite |
| 3 | CEO | Keep AppKit lifecycle + SwiftUI views | P5 explicit | Standard mixed pattern, avoids migration risk | Pure SwiftUI App lifecycle |
| 4 | CEO | Defer notarization | P6 action | Ship v2.0 now, notarize separately | Block release on signing |
| 5 | CEO | Defer cross-platform | P3 pragmatic | macOS-only for now, prove value first | Electron for Windows |
| 6 | Design | Live apply (no Save button) | P5 explicit | macOS standard pattern | Save/Apply button |
| 7 | Design | API Key in General tab | P1 complete | Critical for first use, shouldn't be hidden | Advanced tab |
| 8 | Design | Non-dismissible onboarding | P1 complete | Prevents broken first-run | Dismissible sheet |
| 9 | Design | Static PNG thumbnails for themes | P3 pragmatic | Zero runtime cost vs 3s WebView snapshots | Runtime WebView screenshots |
| 10 | Design | HotKey library for recorder | P3 pragmatic | Proven library vs 2-day custom build | Custom Carbon implementation |
| 11 | Design | Defer audio device picker to v2.1 | P3 pragmatic | Core Audio complexity too high for v2.0 | Full device picker |
| 12 | Eng | Config struct → @Observable class singleton | P5 explicit | Required for SwiftUI binding | Keep struct + workaround |
| 13 | Eng | Package.swift → macOS 14 | P1 complete | Match Info.plist, enable @Observable | Keep macOS 13 |
| 14 | Eng | Add NSAccessibilityUsageDescription | P1 complete | Required for proper permission prompts | Skip |
| 15 | Eng | Defer Keychain migration to v2.1 | P6 action | Ship now, improve security later | Block on Keychain |
| 16 | Eng | Delete confirmation on history | P1 complete | Irreversible action needs guard | Silent delete |

## GSTACK REVIEW REPORT

| Review | Trigger | Runs | Status | Findings |
|--------|---------|------|--------|----------|
| CEO Review | /autoplan | 1 | clean | Path A chosen, 7 findings addressed |
| Design Review | /autoplan | 1 | clean | 18 findings, 4 critical → all resolved in plan |
| Eng Review | /autoplan | 1 | clean | 20 findings, 8 HIGH → 6 pre-flight fixes + 2 deferred |

**VERDICT:** APPROVED — Plan ready for implementation after pre-flight fixes.
