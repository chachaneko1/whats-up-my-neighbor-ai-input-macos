import AppKit

final class VocabularyWindowController: NSWindowController {
    private enum Column {
        static let term = NSUserInterfaceItemIdentifier("term")
        static let enabled = NSUserInterfaceItemIdentifier("enabled")
        static let pinned = NSUserInterfaceItemIdentifier("pinned")
        static let useCount = NSUserInterfaceItemIdentifier("useCount")
    }

    private let store: MacVocabularyStore
    private let tableView = NSTableView()
    private let searchField = NSSearchField()
    private let countLabel = NSTextField(labelWithString: "")
    private let syncLabel = NSTextField(labelWithString: "尚未與 iPhone 同步")
    private let editButton = NSButton(title: "編輯…", target: nil, action: nil)
    private let deleteButton = NSButton(title: "刪除", target: nil, action: nil)
    private var filteredEntries: [VocabularySyncEntry] = []

    init(store: MacVocabularyStore) {
        self.store = store
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "常用詞典"
        window.minSize = NSSize(width: 580, height: 380)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("VocabularyWindow")
        super.init(window: window)

        configureContent()
        reloadEntries()
        store.onEntriesChange = { [weak self] in
            DispatchQueue.main.async {
                self?.reloadEntries()
            }
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(searchField)
    }

    func updateSyncStatus(_ text: String, isError: Bool = false) {
        syncLabel.stringValue = text
        syncLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }

        let explanation = NSTextField(
            wrappingLabelWithString: "啟用的詞會加入下一次 Groq 語音辨識提示。這裡的變更會在已配對的 iPhone 連線後雙向同步。"
        )
        explanation.textColor = .secondaryLabelColor

        searchField.placeholderString = "搜尋常用詞"
        searchField.delegate = self

        let addButton = NSButton(
            title: "新增…",
            target: self,
            action: #selector(addEntry)
        )
        addButton.bezelStyle = .rounded

        configureTable()
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = tableView

        editButton.target = self
        editButton.action = #selector(editSelectedEntry)
        editButton.bezelStyle = .rounded
        editButton.isEnabled = false

        deleteButton.target = self
        deleteButton.action = #selector(deleteSelectedEntry)
        deleteButton.bezelStyle = .rounded
        deleteButton.isEnabled = false

        let clearButton = NSButton(
            title: "清除全部…",
            target: self,
            action: #selector(deleteAllEntries)
        )
        clearButton.bezelStyle = .rounded

        countLabel.font = .systemFont(ofSize: 12)
        countLabel.textColor = .secondaryLabelColor
        syncLabel.font = .systemFont(ofSize: 12)
        syncLabel.textColor = .secondaryLabelColor
        syncLabel.alignment = .right

        let searchRow = NSStackView(views: [searchField, addButton])
        searchRow.orientation = .horizontal
        searchRow.spacing = 8
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let actionRow = NSStackView(views: [editButton, deleteButton, clearButton])
        actionRow.orientation = .horizontal
        actionRow.spacing = 8

        let statusRow = NSStackView(views: [countLabel, syncLabel])
        statusRow.orientation = .horizontal
        statusRow.spacing = 12
        countLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        syncLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let bottomRow = NSStackView(views: [actionRow, statusRow])
        bottomRow.orientation = .horizontal
        bottomRow.alignment = .centerY
        bottomRow.distribution = .fill
        bottomRow.spacing = 16
        actionRow.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let stack = NSStackView(views: [explanation, searchRow, scrollView, bottomRow])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            explanation.widthAnchor.constraint(equalTo: stack.widthAnchor),
            searchRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 240),
            bottomRow.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func configureTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.rowHeight = 30
        tableView.doubleAction = #selector(editSelectedEntry)
        tableView.target = self

        let termColumn = NSTableColumn(identifier: Column.term)
        termColumn.title = "常用詞"
        termColumn.minWidth = 240
        termColumn.width = 360
        termColumn.resizingMask = .autoresizingMask
        tableView.addTableColumn(termColumn)

        let enabledColumn = NSTableColumn(identifier: Column.enabled)
        enabledColumn.title = "啟用"
        enabledColumn.minWidth = 58
        enabledColumn.maxWidth = 70
        enabledColumn.width = 62
        enabledColumn.resizingMask = []
        tableView.addTableColumn(enabledColumn)

        let pinnedColumn = NSTableColumn(identifier: Column.pinned)
        pinnedColumn.title = "釘選"
        pinnedColumn.minWidth = 58
        pinnedColumn.maxWidth = 70
        pinnedColumn.width = 62
        pinnedColumn.resizingMask = []
        tableView.addTableColumn(pinnedColumn)

        let useColumn = NSTableColumn(identifier: Column.useCount)
        useColumn.title = "使用次數"
        useColumn.minWidth = 75
        useColumn.maxWidth = 90
        useColumn.width = 82
        useColumn.resizingMask = []
        tableView.addTableColumn(useColumn)
    }

    private func reloadEntries() {
        let selectedID = selectedEntry?.id
        filteredEntries = store.filteredEntries(matching: searchField.stringValue)
        tableView.reloadData()
        countLabel.stringValue = "常用詞 \(store.entries.count)／\(MacVocabularyStore.maximumEntryCount)"

        if let selectedID,
           let index = filteredEntries.firstIndex(where: { $0.id == selectedID }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        updateSelectionButtons()
    }

    private var selectedEntry: VocabularySyncEntry? {
        let row = tableView.selectedRow
        guard filteredEntries.indices.contains(row) else { return nil }
        return filteredEntries[row]
    }

    private func updateSelectionButtons() {
        let hasSelection = selectedEntry != nil
        editButton.isEnabled = hasSelection
        deleteButton.isEnabled = hasSelection
    }

    @objc private func addEntry() {
        showEditor(entry: nil)
    }

    @objc private func editSelectedEntry() {
        guard let entry = selectedEntry else { return }
        showEditor(entry: entry)
    }

    private func showEditor(entry: VocabularySyncEntry?) {
        let editor = MacVocabularyEditorView(entry: entry)
        let alert = NSAlert()
        alert.messageText = entry == nil ? "新增常用詞" : "編輯常用詞"
        alert.informativeText = "詞彙最多 40 個字；只有啟用的詞會加入 Groq 提示。"
        alert.alertStyle = .informational
        alert.accessoryView = editor
        alert.addButton(withTitle: "儲存")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = editor.termField

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            if let entry {
                try store.update(
                    id: entry.id,
                    term: editor.term,
                    isEnabled: editor.isEnabled,
                    isPinned: editor.isPinned
                )
            } else {
                try store.add(
                    term: editor.term,
                    isEnabled: editor.isEnabled,
                    isPinned: editor.isPinned
                )
            }
        } catch {
            showValidationError(error.localizedDescription)
        }
    }

    @objc private func deleteSelectedEntry() {
        guard let entry = selectedEntry else { return }
        let alert = NSAlert()
        alert.messageText = "刪除「\(entry.term)」？"
        alert.informativeText = "刪除會同步到已配對的 iPhone。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "刪除")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.delete(id: entry.id)
    }

    @objc private func deleteAllEntries() {
        guard !store.entries.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "清除全部常用詞？"
        alert.informativeText = "這會刪除 Mac 與同步後 iPhone 上的全部常用詞，但不會刪除 Groq API Key。"
        alert.alertStyle = .critical
        alert.addButton(withTitle: "清除全部")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.deleteAll()
    }

    private func showValidationError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "無法儲存常用詞"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    @objc private func toggleEnabled(_ sender: NSButton) {
        guard filteredEntries.indices.contains(sender.tag) else { return }
        store.setEnabled(sender.state == .on, for: filteredEntries[sender.tag].id)
    }

    @objc private func togglePinned(_ sender: NSButton) {
        guard filteredEntries.indices.contains(sender.tag) else { return }
        store.setPinned(sender.state == .on, for: filteredEntries[sender.tag].id)
    }
}

extension VocabularyWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        filteredEntries.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard filteredEntries.indices.contains(row), let tableColumn else { return nil }
        let entry = filteredEntries[row]

        switch tableColumn.identifier {
        case Column.term:
            let field = NSTextField(labelWithString: entry.term)
            field.lineBreakMode = .byTruncatingTail
            field.toolTip = entry.term
            return field
        case Column.enabled:
            let checkbox = NSButton(
                checkboxWithTitle: "",
                target: self,
                action: #selector(toggleEnabled(_:))
            )
            checkbox.state = entry.isEnabled ? .on : .off
            checkbox.tag = row
            checkbox.toolTip = entry.isEnabled ? "停用" : "啟用"
            return checkbox
        case Column.pinned:
            let checkbox = NSButton(
                checkboxWithTitle: "",
                target: self,
                action: #selector(togglePinned(_:))
            )
            checkbox.state = entry.isPinned ? .on : .off
            checkbox.tag = row
            checkbox.toolTip = entry.isPinned ? "取消釘選" : "釘選"
            return checkbox
        case Column.useCount:
            let field = NSTextField(labelWithString: String(entry.useCount))
            field.alignment = .center
            return field
        default:
            return nil
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateSelectionButtons()
    }
}

extension VocabularyWindowController: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        reloadEntries()
    }
}

private final class MacVocabularyEditorView: NSView {
    let termField = NSTextField()
    private let enabledButton = NSButton(checkboxWithTitle: "啟用", target: nil, action: nil)
    private let pinnedButton = NSButton(checkboxWithTitle: "優先使用（釘選）", target: nil, action: nil)

    var term: String {
        termField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isEnabled: Bool { enabledButton.state == .on }
    var isPinned: Bool { pinnedButton.state == .on }

    init(entry: VocabularySyncEntry?) {
        super.init(frame: NSRect(x: 0, y: 0, width: 420, height: 104))

        let label = NSTextField(labelWithString: "常用詞")
        label.frame = NSRect(x: 0, y: 76, width: 70, height: 20)
        addSubview(label)

        termField.frame = NSRect(x: 72, y: 72, width: 348, height: 26)
        termField.placeholderString = "例如：YUI Strategy、假處分"
        termField.stringValue = entry?.term ?? ""
        addSubview(termField)

        enabledButton.frame = NSRect(x: 72, y: 38, width: 90, height: 24)
        enabledButton.state = entry?.isEnabled == false ? .off : .on
        addSubview(enabledButton)

        pinnedButton.frame = NSRect(x: 172, y: 38, width: 170, height: 24)
        pinnedButton.state = entry?.isPinned == true ? .on : .off
        addSubview(pinnedButton)

        let privacy = NSTextField(
            wrappingLabelWithString: "只儲存詞彙與管理狀態，不會儲存完整逐字稿或錄音。"
        )
        privacy.textColor = .secondaryLabelColor
        privacy.font = .systemFont(ofSize: 11)
        privacy.frame = NSRect(x: 72, y: 4, width: 348, height: 28)
        addSubview(privacy)
    }

    required init?(coder: NSCoder) {
        nil
    }
}
