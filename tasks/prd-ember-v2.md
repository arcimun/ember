# PRD: Ember v2.0 — Themes, History, Model Benchmark, Config

## Introduction

Ember v2.0 adds four features: swappable visual themes (WebGL shaders), a searchable transcription history window, a Whisper model benchmark to validate the current "turbo" choice, and config improvements (theme selection, auto-detect language, language-agnostic LLM prompt). Current codebase: 957 LOC across 5 Swift files + 1 HTML overlay.

## Goals

- Ship 5+ distinct visual themes users can switch from the menu bar
- Provide searchable history UI with copy-to-clipboard and re-paste
- Validate Whisper model choice with data (turbo vs full) — latency, accuracy, file size
- Make language detection automatic by default (no hardcoded `ru`)
- Keep total codebase under ~1500 LOC (currently 957)

## User Stories

### US-001: Theme file structure and loader
**Type:** feat
**Status:** pending
**Description:** As a developer, I need a theme loading system so that overlay.html can render any theme from a structured directory.
**Files:** `Sources/Overlay.swift`, `Sources/Config.swift`, `Resources/overlay.html`

**Acceptance Criteria:**
- [ ] Create `Resources/themes/` directory
- [ ] Each theme = one `.html` file (self-contained WebGL2 shader + JS API)
- [ ] Every theme implements `setAudioLevel(float)`, `setActive(bool)`, `setProcessing(bool)` — same JS API as current overlay
- [ ] Move current violet flame shader to `Resources/themes/violet-flame.html`
- [ ] `overlay.html` becomes a thin loader: reads theme file, injects into WKWebView
- [ ] Config.swift: add `THEME` field (default: `violet-flame`)
- [ ] Overlay.swift: load theme by name from bundle's `themes/` directory
- [ ] Fallback: if theme file missing, load `violet-flame.html`
- [ ] Typecheck passes (`swift build`)

---

### US-002: Ship 5 initial themes
**Type:** feat
**Status:** pending
**Description:** As a user, I want multiple visual themes so I can pick the aesthetic I prefer.
**Files:** `Resources/themes/*.html`

**Acceptance Criteria:**
- [ ] `violet-flame.html` — current shader (moved from overlay.html)
- [ ] `aurora.html` — green/cyan aurora borealis, vertical wave motion
- [ ] `nebula.html` — deep blue/purple space nebula, particle drift
- [ ] `solar.html` — warm orange/gold solar flare, radial burst
- [ ] `minimal.html` — monochrome white glow, subtle pulse, no noise
- [ ] Each file is self-contained (<15KB), uses WebGL2 GLSL
- [ ] Each implements the 3-function JS API identically
- [ ] Each has transparent center (content pass-through) and animated edges
- [ ] All themes are voice-reactive (amplitude drives visual intensity)
- [ ] Manual test: switch between all 5 themes, verify each renders correctly

---

### US-003: Theme switcher in menu bar
**Type:** feat
**Status:** pending
**Description:** As a user, I want to switch themes from the menu bar without editing config files.
**Files:** `Sources/App.swift`, `Sources/Config.swift`, `Sources/Overlay.swift`

**Acceptance Criteria:**
- [ ] "Theme" submenu in menu bar with all available theme names
- [ ] Checkmark on current theme
- [ ] Selecting a theme: saves to `config.env` (read-modify-write, not overwrite), reloads overlay instantly (no app restart)
- [ ] Theme menu items disabled during active recording (re-enabled when recording stops)
- [ ] Theme names derived from filenames (kebab-case → Title Case: `violet-flame` → `Violet Flame`)
- [ ] New themes dropped into `Resources/themes/` auto-appear in menu (no code change)
- [ ] Typecheck passes (`swift build`)

---

### US-004: History data model and persistence
**Type:** feat
**Status:** pending
**Description:** As a developer, I need history stored as JSON files so transcriptions persist across sessions.
**Files:** `Sources/Config.swift`

**Acceptance Criteria:**
- [ ] Refactor `saveHistory()` signature: `saveHistory(raw:corrected:language:duration:)`
- [ ] Each transcription saved as JSON in `~/.config/ember/history/` (existing convention)
- [ ] JSON schema: `{ "timestamp": ISO8601, "raw": "...", "corrected": "...", "language": "ru", "duration_ms": 1200 }`
- [ ] Backward-compatible read: old files with `text` field → treat as `corrected`, `raw` = nil
- [ ] Add `language` field (detected by Whisper via verbose_json) and `duration_ms` (recording length)
- [ ] History files named `YYYY-MM-DD_HH-mm-ss.json` (existing convention)
- [ ] Typecheck passes (`swift build`)

---

### US-005: History window UI
**Type:** feat
**Status:** pending
**Description:** As a user, I want to browse and search my transcription history so I can find and reuse past dictations.
**Files:** `Sources/App.swift` (new: `Sources/History.swift`)

**Acceptance Criteria:**
- [ ] New file `Sources/History.swift` — `HistoryWindowController` class
- [ ] Window size: 600×500, resizable, title "Ember — History"
- [ ] Split view: left = session list (NSTableView), right = detail (NSTextView)
- [ ] Left panel shows: date/time, first ~50 chars of corrected text, duration badge
- [ ] Right panel shows: full corrected text, raw text below in gray, copy button
- [ ] NSSearchField at top — filters by text content (corrected + raw)
- [ ] Menu bar item "Show History" (no hotkey — Cmd+H conflicts with macOS "Hide") opens/focuses window
- [ ] If window already open, bring to front (not create new)
- [ ] "Copy" button copies corrected text to clipboard
- [ ] "Re-paste" button copies + simulates Cmd+V (same as normal transcription flow)
- [ ] Sessions sorted newest-first
- [ ] Typecheck passes (`swift build`)
- [ ] Manual test: open history, search, copy, re-paste

---

### US-006: Config improvements — language auto-detect and LLM prompt
**Type:** feat
**Status:** pending
**Description:** As a user, I want Ember to auto-detect my language so I don't have to configure it manually.
**Files:** `Sources/Config.swift`, `Sources/STT.swift`

**Acceptance Criteria:**
- [ ] `DICTATION_LANGUAGE` default changed from `ru` to `auto`
- [ ] When `auto`: omit `language` param from Whisper API call (Whisper auto-detects)
- [ ] Switch Whisper `response_format` from `text` to `verbose_json` to get detected language
- [ ] Parse JSON response: extract `text` and `language` fields
- [ ] Pass detected language to saveHistory(); save to history JSON
- [ ] LLM system prompt changed to language-agnostic: "Fix grammar and punctuation. Keep the original language. Do not translate. Do not add or remove content."
- [ ] When language is explicitly set (e.g., `ru`): behavior unchanged (passes to Whisper API)
- [ ] Typecheck passes (`swift build`)
- [ ] Manual test: dictate in Russian and English without changing config

---

### US-007: Whisper model benchmark
**Type:** test
**Status:** pending
**Description:** As a developer, I want benchmark data comparing whisper-large-v3-turbo vs whisper-large-v3 to validate our model choice.
**Files:** `Sources/STT.swift` (read-only for reference)

**Acceptance Criteria:**
- [ ] Create `scripts/benchmark-whisper.sh` — sends same 3 audio samples to both models
- [ ] Audio samples: short (3s), medium (15s), long (60s) — in Russian and English
- [ ] Measures: latency (ms), response size, word-level accuracy (manual comparison)
- [ ] Outputs markdown table to stdout
- [ ] Run benchmark, save results to `docs/whisper-benchmark.md`
- [ ] Decision documented: keep turbo or switch to full

---

### US-008: XCTest foundation
**Type:** test
**Status:** pending
**Description:** As a developer, I want basic tests so future changes don't break core logic.
**Files:** new: `Tests/EmberTests/ConfigTests.swift`, `Tests/EmberTests/RecorderTests.swift`

**Acceptance Criteria:**
- [ ] Add test target to `Package.swift`
- [ ] `ConfigTests.swift`: test .env parsing, default values, API key validation
- [ ] `RecorderTests.swift`: test WAV header generation, sample rate conversion math
- [ ] All tests pass with `swift test`
- [ ] No tests for network calls (Groq API) — those are integration tests, out of scope

## Functional Requirements

- FR-1: Theme system loads `.html` files from `Resources/themes/` bundle directory
- FR-2: Theme selection persisted in `~/.config/ember/config.env` as `THEME=<name>`
- FR-3: Overlay reloads theme in-place without app restart
- FR-4: History window displays all sessions from `~/.config/ember/history/`
- FR-5: Search filters history by text content in real-time
- FR-6: Copy and re-paste work from history detail view
- FR-7: Language auto-detection when `DICTATION_LANGUAGE=auto` (default)
- FR-8: LLM prompt is language-agnostic — works for any language without changes
- FR-9: Detected language saved in history JSON for each session

## Non-Goals

- No theme editor / theme creation UI
- No cloud sync for history
- No history pagination (all sessions loaded into memory — acceptable for years of use at ~1KB/session)
- No theme animations settings (speed, intensity) — themes are self-contained
- No Whisper model switcher in UI (benchmark decides once, hardcode the winner)
- No integration tests for Groq API

## Technical Considerations

- **Theme isolation**: Each theme is a complete HTML file. No shared CSS/JS between themes. This makes themes easy to create and impossible to break each other.
- **WKWebView reload**: `Overlay.swift` already creates a WKWebView — theme switch = `loadFileURL()` with new path, then re-call `setActive()`/`setAudioLevel()` to restore state.
- **History file I/O**: `Config.swift` already reads/writes to `~/.config/ember/`. History uses same directory pattern. FileManager enumeration for listing.
- **NSSearchField**: Native AppKit search — no dependencies. Filter predicate on the array of history items.
- **Package.swift change**: Add `.testTarget(name: "EmberTests", dependencies: ["Ember"])` — requires changing executable target to library + executable split, or using `@testable import`.
- **LOC budget**: ~200 for themes infra, ~150 for History.swift, ~30 for config changes, ~80 for tests = ~460 new LOC → total ~1400 (under 1500 target).

## Implementation Order

1. **US-006** (config/language) — smallest, unblocks testing flow
2. **US-001** (theme loader) — foundation for themes
3. **US-002** (5 themes) — parallelizable, mostly HTML/GLSL work
4. **US-003** (menu switcher) — depends on US-001
5. **US-004** (history data model) — foundation for history UI
6. **US-005** (history window) — depends on US-004
7. **US-007** (benchmark) — independent, can run anytime
8. **US-008** (XCTest) — last, tests the final state

## Success Metrics

- Theme switch completes in <200ms (no flicker)
- History window opens in <500ms with 1000+ sessions
- Auto-detect language works for Russian and English without config changes
- Benchmark provides clear data for model choice
- Zero regressions in existing dictation pipeline

## CEO Review Findings (2026-03-21)

### Issues Found & Resolved

1. **saveHistory() signature change** — current function saves only `text`. Needs refactoring to accept `raw`, `corrected`, `language`, `duration`. Backward-compatible read for old JSON files (has `text` → treat as `corrected`).

2. **Whisper response_format change** — must switch from `text` to `verbose_json` to get detected language. Changes STT.swift response parsing (~15 LOC).

3. **Config.save() overwrites all fields** — current implementation writes only groqKey+language, losing other fields. Must use read-modify-write pattern (already exists in showApiKeyDialog). Fix when adding THEME.

4. **Cmd+H conflict** — macOS standard "Hide Application". Removed hotkey from History. Menu item only.

5. **Theme switch during recording** — overlay would reload mid-dictation. Solution: disable theme menu items during recording.

6. **10K+ history files** — FileManager enumeration + JSON parse on main thread could be slow. Solution: load on background DispatchQueue, show spinner.

7. **WKWebView load failure** — if theme HTML fails to load, overlay stays black. Log warning, fallback to violet-flame.

### Error & Rescue Registry

| Codepath | Failure Mode | Rescued? | User Sees |
|----------|-------------|----------|-----------|
| loadTheme() | File missing | Y (fallback) | Default theme |
| loadTheme() | WKWebView fail | Y (log+fallback) | Default theme |
| Theme JS API | Missing function | Y (silent) | No animation |
| History load | Corrupted JSON | Y (skip) | Missing session |
| History load | Old format | Y (compat) | Corrected only |
| Whisper auto | No language field | Y (default "unknown") | "unknown" in history |
| Config.save | Disk full | N (edge case) | Config not saved |

### Failure Modes Summary

| Codepath | Failure | Rescued | Tested | User Sees | Logged |
|----------|---------|---------|--------|-----------|--------|
| Theme missing | Y | Y | Add to tests | Fallback | Y |
| History corrupt | Y | Y | Add to tests | Skipped | Y |
| Whisper verbose_json | N→Y | Y | Manual | Fallback text | Y |
| Config overwrite | N→Y | Y | Add to tests | OK | Y |

0 CRITICAL GAPS remaining.

## Open Questions

- None — all decisions made during office-hours, eng/design reviews, and CEO review
