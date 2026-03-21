import Cocoa

// ═══════════════════════════════════════════════════════════════════
// History Window — browse and search past transcriptions
// ═══════════════════════════════════════════════════════════════════

struct HistoryItem {
    let timestamp: Date
    let raw: String?
    let corrected: String
    let language: String
    let durationMs: Int
    let filename: String
}

class HistoryWindowController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private var window: NSWindow?
    private var tableView: NSTableView!
    private var detailText: NSTextView!
    private var searchField: NSSearchField!
    private var allItems: [HistoryItem] = []
    private var filteredItems: [HistoryItem] = []
    private var copyButton: NSButton!
    private var repasteButton: NSButton!
    private var spinner: NSProgressIndicator!

    func showWindow() {
        if let w = window, w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 500),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        w.title = "Ember — History"
        w.center()
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 400, height: 300)
        window = w

        // Search field
        searchField = NSSearchField()
        searchField.placeholderString = "Search transcriptions..."
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        // Table view (left/top panel — session list)
        tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = 48
        tableView.delegate = self
        tableView.dataSource = self

        let col1 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("session"))
        col1.title = "Session"
        tableView.addTableColumn(col1)

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // Detail view (right/bottom panel)
        detailText = NSTextView()
        detailText.isEditable = false
        detailText.isSelectable = true
        detailText.font = .systemFont(ofSize: 14)
        detailText.textContainerInset = NSSize(width: 8, height: 8)
        detailText.translatesAutoresizingMaskIntoConstraints = false

        let detailScroll = NSScrollView()
        detailScroll.documentView = detailText
        detailScroll.hasVerticalScroller = true
        detailScroll.translatesAutoresizingMaskIntoConstraints = false

        // Buttons
        copyButton = NSButton(title: "Copy", target: self, action: #selector(copySelected))
        copyButton.bezelStyle = .rounded
        repasteButton = NSButton(title: "Re-paste", target: self, action: #selector(repasteSelected))
        repasteButton.bezelStyle = .rounded

        let buttonRow = NSStackView(views: [copyButton, repasteButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        // Loading spinner
        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.translatesAutoresizingMaskIntoConstraints = false

        // Split view
        let splitView = NSSplitView()
        splitView.isVertical = false
        splitView.dividerStyle = .thin
        splitView.addSubview(scrollView)
        splitView.addSubview(detailScroll)
        splitView.translatesAutoresizingMaskIntoConstraints = false

        // Layout
        let container = NSView()
        container.addSubview(searchField)
        container.addSubview(spinner)
        container.addSubview(splitView)
        container.addSubview(buttonRow)
        w.contentView = container

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),

            spinner.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            splitView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            splitView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -8),

            buttonRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            buttonRow.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),

            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])

        // Set initial split position
        splitView.setPosition(250, ofDividerAt: 0)

        loadHistory()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // ─── Data Loading ─────────────────────────────────────────────

    private func loadHistory() {
        spinner.startAnimation(nil)
        spinner.isHidden = false
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let items = Self.loadItems()
            DispatchQueue.main.async {
                self.spinner.stopAnimation(nil)
                self.spinner.isHidden = true
                self.allItems = items
                self.applyFilter()
            }
        }
    }

    private static func loadItems() -> [HistoryItem] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: historyDir) else { return [] }
        var items: [HistoryItem] = []
        let isoFormatter = ISO8601DateFormatter()

        for file in files where file.hasSuffix(".json") {
            let path = (historyDir as NSString).appendingPathComponent(file)
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                log("⚠️ Skipping corrupted history file: \(file)")
                continue
            }

            let timestamp: Date
            if let ts = json["timestamp"] as? String, let d = isoFormatter.date(from: ts) {
                timestamp = d
            } else {
                timestamp = Date()
            }

            // Backward-compatible: old format has "text", new has "corrected"+"raw"
            let corrected = (json["corrected"] as? String) ?? (json["text"] as? String) ?? ""
            let raw = json["raw"] as? String
            let language = (json["language"] as? String) ?? "unknown"
            let durationMs = (json["duration_ms"] as? Int) ?? Int(((json["duration"] as? Double) ?? 0) * 1000)

            guard !corrected.isEmpty else { continue }
            items.append(HistoryItem(timestamp: timestamp, raw: raw, corrected: corrected,
                                     language: language, durationMs: durationMs, filename: file))
        }

        return items.sorted { $0.timestamp > $1.timestamp }
    }

    private func applyFilter() {
        let query = searchField?.stringValue.lowercased() ?? ""
        if query.isEmpty {
            filteredItems = allItems
        } else {
            filteredItems = allItems.filter {
                $0.corrected.lowercased().contains(query) ||
                ($0.raw?.lowercased().contains(query) ?? false)
            }
        }
        tableView.reloadData()
        if !filteredItems.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            updateDetail(index: 0)
        } else {
            detailText.string = filteredItems.isEmpty && !allItems.isEmpty
                ? "No matches" : "No recordings yet. Press ` to start dictating!"
        }
    }

    // ─── NSSearchFieldDelegate ────────────────────────────────────

    func controlTextDidChange(_ obj: Notification) {
        applyFilter()
    }

    // ─── NSTableViewDataSource / Delegate ─────────────────────────

    func numberOfRows(in tableView: NSTableView) -> Int { filteredItems.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = filteredItems[row]
        let cell = NSTableCellView()

        let df = DateFormatter()
        df.dateFormat = "MMM d HH:mm"
        let dateStr = df.string(from: item.timestamp)
        let preview = String(item.corrected.prefix(50)).replacingOccurrences(of: "\n", with: " ")
        let durStr = String(format: "%.1fs", Double(item.durationMs) / 1000.0)

        let label = NSTextField(labelWithString: "\(dateStr)  ·  \(preview)")
        label.font = .systemFont(ofSize: 12)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        let dur = NSTextField(labelWithString: durStr)
        dur.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        dur.textColor = .secondaryLabelColor
        dur.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(label)
        cell.addSubview(dur)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: dur.leadingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            dur.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            dur.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0 && row < filteredItems.count else { return }
        updateDetail(index: row)
    }

    private func updateDetail(index: Int) {
        let item = filteredItems[index]
        let attrStr = NSMutableAttributedString()

        // Corrected text
        attrStr.append(NSAttributedString(string: item.corrected + "\n\n",
            attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.labelColor]))

        // Raw text (if available)
        if let raw = item.raw {
            attrStr.append(NSAttributedString(string: "Raw: " + raw,
                attributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]))
        }

        detailText.textStorage?.setAttributedString(attrStr)
    }

    // ─── Actions ──────────────────────────────────────────────────

    @objc private func copySelected() {
        let row = tableView.selectedRow
        guard row >= 0 && row < filteredItems.count else { return }
        let pb = NSPasteboard.general; pb.clearContents()
        pb.setString(filteredItems[row].corrected, forType: .string)
        log("📋 History: copied to clipboard")
    }

    @objc private func repasteSelected() {
        copySelected()
        // Simulate Cmd+V (same as normal transcription flow)
        usleep(80_000)
        let src = CGEventSource(stateID: .combinedSessionState)
        if let d = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true) {
            d.flags = .maskCommand; d.post(tap: .cghidEventTap)
        }
        usleep(20_000)
        if let u = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false) {
            u.flags = .maskCommand; u.post(tap: .cghidEventTap)
        }
        log("📋 History: re-pasted")
    }
}
