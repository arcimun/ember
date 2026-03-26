import SwiftUI
import AppKit

// ═══════════════════════════════════════════════════════════════════
// History Viewer — Phase 4 (SwiftUI NavigationSplitView)
// Replaces HistoryWindowController (NSTableView-based)
// Design decisions D4 + D5 from PLAN-v2.md
// ═══════════════════════════════════════════════════════════════════

// ─── HistoryEntry — Codable model ─────────────────────────────────

struct HistoryEntry: Identifiable, Hashable {
    let id: String          // filename (stable unique ID)
    let timestamp: Date
    let durationMs: Int
    let corrected: String
    let raw: String?
    let language: String
    let filename: String

    var durationSeconds: Double { Double(durationMs) / 1000.0 }

    var languageFlag: String {
        switch language.lowercased().prefix(2) {
        case "en": return "🇺🇸"
        case "ru": return "🇷🇺"
        case "de": return "🇩🇪"
        case "fr": return "🇫🇷"
        case "es": return "🇪🇸"
        case "zh": return "🇨🇳"
        case "ja": return "🇯🇵"
        case "ko": return "🇰🇷"
        case "pt": return "🇧🇷"
        case "it": return "🇮🇹"
        case "pl": return "🇵🇱"
        case "uk": return "🇺🇦"
        default:   return "🌐"
        }
    }

    var relativeTimestamp: String {
        let interval = Date().timeIntervalSince(timestamp)
        if interval < 60 { return "Just now" }
        if interval < 3600 {
            let m = Int(interval / 60)
            return "\(m) min ago"
        }
        if interval < 86400 {
            let h = Int(interval / 3600)
            return "\(h)h ago"
        }
        let cal = Calendar.current
        if cal.isDateInYesterday(timestamp) { return "Yesterday" }
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df.string(from: timestamp)
    }

    var fullTimestamp: String {
        let df = DateFormatter()
        df.dateStyle = .long
        df.timeStyle = .short
        return df.string(from: timestamp)
    }

    var textPreview: String {
        let first = corrected.components(separatedBy: "\n").first ?? corrected
        return String(first.prefix(80))
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: HistoryEntry, rhs: HistoryEntry) -> Bool { lhs.id == rhs.id }
}

// ─── HistoryStore — loads / deletes entries ───────────────────────

@Observable
final class HistoryStore {
    var entries: [HistoryEntry] = []
    var isLoading = false

    func load() {
        isLoading = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let loaded = await Task.detached(priority: .userInitiated) {
                Self.readEntries()
            }.value
            self.entries = loaded
            self.isLoading = false
        }
    }

    func delete(_ entry: HistoryEntry) {
        let path = (historyDir as NSString).appendingPathComponent(entry.filename)
        try? FileManager.default.removeItem(atPath: path)
        entries.removeAll { $0.id == entry.id }
    }

    func deleteAll() {
        for entry in entries {
            let path = (historyDir as NSString).appendingPathComponent(entry.filename)
            try? FileManager.default.removeItem(atPath: path)
        }
        entries.removeAll()
    }

    private static func readEntries() -> [HistoryEntry] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: historyDir) else { return [] }
        let iso = ISO8601DateFormatter()
        var result: [HistoryEntry] = []

        for file in files where file.hasSuffix(".json") {
            let path = (historyDir as NSString).appendingPathComponent(file)
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                log("⚠️ HistoryView: skipping corrupted file: \(file)")
                continue
            }

            let timestamp: Date
            if let ts = json["timestamp"] as? String, let d = iso.date(from: ts) {
                timestamp = d
            } else {
                timestamp = Date()
            }

            let corrected = (json["corrected"] as? String)
                ?? (json["text"] as? String) ?? ""
            guard !corrected.isEmpty else { continue }

            let raw = json["raw"] as? String
            let language = (json["language"] as? String) ?? "unknown"
            let durationMs = (json["duration_ms"] as? Int)
                ?? Int(((json["duration"] as? Double) ?? 0) * 1000)

            result.append(HistoryEntry(
                id: file,
                timestamp: timestamp,
                durationMs: durationMs,
                corrected: corrected,
                raw: raw,
                language: language,
                filename: file
            ))
        }

        return result.sorted { $0.timestamp > $1.timestamp }
    }
}

// ─── HistoryView — NavigationSplitView ───────────────────────────

struct HistoryView: View {
    @State private var store = HistoryStore()
    @State private var selection: HistoryEntry?
    @State private var searchText = ""
    @State private var showClearConfirm = false

    var filtered: [HistoryEntry] {
        guard !searchText.isEmpty else { return store.entries }
        let q = searchText.lowercased()
        return store.entries.filter {
            $0.corrected.lowercased().contains(q) ||
            ($0.raw?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            detailContent
        }
        .frame(minWidth: 500, minHeight: 350)
        .onAppear { store.load() }
        .alert("Clear All History", isPresented: $showClearConfirm) {
            Button("Clear All", role: .destructive) {
                store.deleteAll()
                selection = nil
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all \(store.entries.count) transcriptions.")
        }
    }

    // ─── Sidebar ──────────────────────────────────────────────────

    @ViewBuilder
    private var sidebarContent: some View {
        Group {
            if store.isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.entries.isEmpty {
                emptyHistoryState
            } else if filtered.isEmpty && !searchText.isEmpty {
                emptySearchState
            } else {
                List(filtered, selection: $selection) { entry in
                    HistoryRowView(entry: entry)
                        .tag(entry)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search transcriptions…")
        .navigationTitle("History")
        .toolbar {
            if !store.entries.isEmpty {
                ToolbarItem(placement: .destructiveAction) {
                    Button("Clear All") {
                        showClearConfirm = true
                    }
                    .foregroundStyle(.red)
                }
            }
        }
    }

    // ─── Empty States (D5) ────────────────────────────────────────

    private var emptyHistoryState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No transcriptions yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Press ` to start dictating")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptySearchState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No results for \u{201C}\(searchText)\u{201D}")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ─── Detail panel ─────────────────────────────────────────────

    @ViewBuilder
    private var detailContent: some View {
        if let entry = selection {
            HistoryDetailView(entry: entry) {
                // Delete callback
                store.delete(entry)
                selection = nil
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("Select a transcription to view details")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// ─── HistoryRowView ───────────────────────────────────────────────

struct HistoryRowView: View {
    let entry: HistoryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(entry.relativeTimestamp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(entry.languageFlag)
                    .font(.caption)
            }
            Text(entry.textPreview)
                .font(.system(size: 13))
                .lineLimit(2)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 2)
        .accessibilityLabel("\(entry.relativeTimestamp). \(entry.textPreview)")
    }
}

// ─── HistoryDetailView ────────────────────────────────────────────

struct HistoryDetailView: View {
    let entry: HistoryEntry
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // ── Meta badges ───────────────────────────────────
                HStack(spacing: 8) {
                    Label(entry.fullTimestamp, systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    badge(String(format: "%.1fs", entry.durationSeconds),
                          systemImage: "timer")
                    badge("\(entry.languageFlag) \(entry.language)",
                          systemImage: "globe")
                }

                Divider()

                // ── Transcription text ────────────────────────────
                Text(entry.corrected)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // ── Raw text (if different) ───────────────────────
                if let raw = entry.raw, raw != entry.corrected {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Raw")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(raw)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Divider()

                // ── Action buttons (D4) ───────────────────────────
                HStack {
                    Button {
                        copyToClipboard()
                    } label: {
                        Label(copied ? "Copied!" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(copied)
                    .animation(.easeInOut(duration: 0.2), value: copied)
                    .accessibilityLabel("Copy transcription to clipboard")

                    Spacer()

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .accessibilityLabel("Delete this transcription")
                }
            }
            .padding(20)
        }
        .alert("Delete Transcription?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This transcription will be permanently deleted.")
        }
    }

    private func badge(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(.secondary)
    }

    private func copyToClipboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(entry.corrected, forType: .string)
        log("📋 HistoryView: copied to clipboard")
        withAnimation { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { copied = false }
        }
    }
}

// ─── Window management — fix leak (Eng Review 2.5) ───────────────
/// Singleton window holder. Prevents creating multiple history windows.
final class HistoryWindowManager {
    static let shared = HistoryWindowManager()
    private init() {}

    private weak var window: NSWindow?

    func show() {
        if let w = window, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = HistoryView()
        let controller = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: controller)
        w.title = "Ember — History"
        w.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        w.setContentSize(NSSize(width: 700, height: 500))
        w.minSize = NSSize(width: 500, height: 350)
        w.center()
        w.isReleasedWhenClosed = false

        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
