import AppKit

final class VocabularyWindowController: NSWindowController {
    private enum Column {
        static let term = NSUserInterfaceItemIdentifier("term")
        static let enabled = NSUserInterfaceItemIdentifier("enabled")
        static let pinned = NSUserInterfaceItemIdentifier("pinned")
        static let useCount = NSUserInterfaceItemIdentifier("useCount")
    }

    private let learning: VocabularyLearningStore
    private let sections = NSSegmentedControl(labels: ["已加入", "候選", "學習紀錄"], trackingMode: .selectOne, target: nil, action: nil)
    private let learningLabel = NSTextField(wrappingLabelWithString: "")
    private let promptLabel = NSTextField(wrappingLabelWithString: "")
    private let confirmButton = NSButton(title: "確認加入", target: nil, action: nil)
    private var candidateRows: [VocabularyLearningCandidate] = []
    private var showsCandidates: Bool { sections.selectedSegment != 0 }
    private let store: MacVocabularyStore
    private let tableView = NSTableView()
    private let searchField = NSSearchField()
    private let countLabel = NSTextField(labelWithString: "")
    private let syncLabel = NSTextField(labelWithString: "尚未與 iPhone 同步")
    private let editButton = NSButton(title: "編輯…", target: nil, action: nil)
    private let deleteButton = NSButton(title: "刪除", target: nil, action: nil)
    private var filteredEntries: [VocabularySyncEntry] = []

    init(store: MacVocabularyStore, learning: VocabularyLearningStore) {
        self.store = store
        self.learning = learning
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "What's up my neighbor · 個人字典"
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = NekoAppearance.background
        window.contentMinSize = NSSize(width: 580, height: 640)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("VocabularyWindow")
        super.init(window: window)

        configureContent()
        sections.selectedSegment = 0
        sections.target = self
        sections.action = #selector(changeSection)
        learning.onChange = { [weak self] in self?.reloadEntries() }
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
        syncLabel.toolTip = text
        syncLabel.textColor = isError ? .systemRed : .secondaryLabelColor
    }

    private func configureContent() {
        guard let contentView = window?.contentView else { return }

        let brandImage = NSImageView()
        brandImage.image = NekoAppearance.catImage
        brandImage.imageScaling = .scaleProportionallyUpOrDown
        brandImage.translatesAutoresizingMaskIntoConstraints = false
        brandImage.widthAnchor.constraint(equalToConstant: 72).isActive = true
        brandImage.heightAnchor.constraint(equalToConstant: 36).isActive = true
        let brandTitle = NSTextField(labelWithString: "讓小黑貓，記住你的用詞。")
        brandTitle.font = .systemFont(ofSize: 22, weight: .semibold)
        brandTitle.textColor = NekoAppearance.ink
        let brandRow = NSStackView(views: [brandImage, brandTitle])
        brandRow.orientation = .horizontal
        brandRow.alignment = .centerY
        brandRow.spacing = 14

        let explanation = NSTextField(
            wrappingLabelWithString: "修正貼入的詞後，會顯示六秒提示後自動加入字典；滑鼠移上提示會暫停，按「不加入」即可取消。只在本機學習，尚未整合 iPhone 詞典同步。"
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
        scrollView.hasHorizontalScroller = true
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

        countLabel.font = .systemFont(ofSize: 12)
        countLabel.textColor = .secondaryLabelColor
        syncLabel.font = .systemFont(ofSize: 12)
        syncLabel.textColor = .secondaryLabelColor
        syncLabel.alignment = .right
        syncLabel.lineBreakMode = .byTruncatingMiddle
        syncLabel.maximumNumberOfLines = 1
        countLabel.maximumNumberOfLines = 1
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        syncLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let searchRow = NSStackView(views: [searchField, addButton])
        searchRow.orientation = .horizontal
        searchRow.spacing = 8
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        confirmButton.target = self
        confirmButton.action = #selector(confirmCandidate)
        confirmButton.bezelStyle = .rounded
        for button in [editButton, deleteButton, confirmButton] {
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        let actionRow = NSStackView(views: [editButton, deleteButton, confirmButton])
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 8

        let statusRow = NSStackView(views: [countLabel, syncLabel])
        statusRow.orientation = .horizontal
        statusRow.alignment = .firstBaseline
        statusRow.spacing = 12
        countLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        syncLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // Actions and metadata need separate lines: candidate actions have
        // longer titles, and must never compete with the update timestamp.
        let footer = NSStackView(views: [actionRow, statusRow])
        footer.orientation = .vertical
        footer.alignment = .leading
        footer.spacing = 10
        footer.setContentHuggingPriority(.required, for: .vertical)
        footer.setContentCompressionResistancePriority(.required, for: .vertical)
        actionRow.setContentHuggingPriority(.required, for: .vertical)
        statusRow.setContentHuggingPriority(.required, for: .vertical)

        learningLabel.maximumNumberOfLines = 3
        promptLabel.maximumNumberOfLines = 4
        learningLabel.font = .systemFont(ofSize: 12)
        promptLabel.font = .systemFont(ofSize: 12)
        let stack = NSStackView(views: [brandRow, explanation, sections, learningLabel, promptLabel, searchRow, scrollView, footer])
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
            learningLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            promptLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            searchRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            actionRow.widthAnchor.constraint(lessThanOrEqualTo: footer.widthAnchor),
            statusRow.widthAnchor.constraint(equalTo: footer.widthAnchor)
        ])
    }

    private func configureTable() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.columnAutoresizingStyle = .sequentialColumnAutoresizingStyle
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
        useColumn.title = "提示次數"
        useColumn.minWidth = 75
        useColumn.maxWidth = 90
        useColumn.width = 82
        useColumn.resizingMask = []
        tableView.addTableColumn(useColumn)
    }

    private func reloadEntries() {
        let selectedID = selectedEntry?.id
        let query = searchField.stringValue
        candidateRows = learning.candidates.filter {
            (sections.selectedSegment == 2 || $0.state == "candidate") &&
            (query.isEmpty || $0.term.localizedCaseInsensitiveContains(query) || $0.original.localizedCaseInsensitiveContains(query))
        }
        learningLabel.stringValue = "學習：" + (learning.storageError ?? store.loadError ?? learning.status)
        promptLabel.stringValue = learning.promptStatus
        promptLabel.toolTip = learning.promptStatus
        for column in tableView.tableColumns {
            switch column.identifier {
            case Column.enabled: column.title = showsCandidates ? "狀態" : "啟用"
            case Column.pinned:
                column.title = showsCandidates ? "來源" : "釘選"
                column.minWidth = showsCandidates ? 76 : 58
                column.maxWidth = showsCandidates ? 90 : 70
                column.width = showsCandidates ? 78 : 62
            case Column.useCount:
                column.title = showsCandidates ? "更新時間" : "提示次數"
                column.minWidth = showsCandidates ? 170 : 75
                column.maxWidth = showsCandidates ? 220 : 90
                column.width = showsCandidates ? 180 : 82
            default:
                column.title = showsCandidates ? "原辨識 → 修正詞" : "常用詞"
                column.minWidth = showsCandidates ? 180 : 240
            }
        }
        syncLabel.stringValue = store.entries.map(\.updatedAt).max().map { "更新：" + DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) } ?? "尚無詞條"
        syncLabel.toolTip = syncLabel.stringValue
        confirmButton.isHidden = !showsCandidates
        editButton.title = showsCandidates ? "修改候選…" : "編輯…"
        deleteButton.title = showsCandidates ? "拒絕／刪除紀錄" : "刪除"
        filteredEntries = store.filteredEntries(matching: searchField.stringValue)
        tableView.reloadData()
        countLabel.stringValue = "已加入 \(store.entries.count)／200；候選 \(learning.candidates.filter { $0.state == "candidate" }.count)"

        if let selectedID,
           let index = filteredEntries.firstIndex(where: { $0.id == selectedID }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        updateSelectionButtons()
    }

    private var selectedEntry: VocabularySyncEntry? {
        let row = tableView.selectedRow
        guard !showsCandidates, filteredEntries.indices.contains(row) else { return nil }
        return filteredEntries[row]
    }

    private func updateSelectionButtons() {
        let candidate = selectedCandidate
        let hasSelection = showsCandidates ? candidate?.state == "candidate" : selectedEntry != nil
        confirmButton.isEnabled = candidate?.state == "candidate"
        editButton.isEnabled = hasSelection
        deleteButton.isEnabled = showsCandidates ? candidate != nil : hasSelection
    }

    private var selectedCandidate: VocabularyLearningCandidate? {
        let row = tableView.selectedRow
        return showsCandidates && candidateRows.indices.contains(row) ? candidateRows[row] : nil
    }

    @objc private func changeSection() { tableView.deselectAll(nil); reloadEntries() }

    @objc private func confirmCandidate() {
        guard let candidate = selectedCandidate else { return }
        do { try learning.confirm(id: candidate.id) }
        catch { showValidationError(error.localizedDescription) }
    }

    @objc private func addEntry() {
        showEditor(entry: nil)
    }

    @objc private func editSelectedEntry() {
        if let candidate = selectedCandidate, candidate.state == "candidate" {
            let alert = NSAlert()
            alert.messageText = "修改候選（尚未加入詞典）"
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 26))
            field.stringValue = candidate.term
            alert.accessoryView = field
            alert.addButton(withTitle: "儲存候選")
            alert.addButton(withTitle: "取消")
            if alert.runModal() == .alertFirstButtonReturn {
                do { try learning.update(id: candidate.id, term: field.stringValue) }
                catch { showValidationError(error.localizedDescription) }
            }
            return
        }
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
        if let candidate = selectedCandidate {
            if candidate.state == "candidate" { learning.reject(id: candidate.id) }
            else { learning.deleteRecord(id: candidate.id) }
            return
        }
        guard let entry = selectedEntry else { return }
        let alert = NSAlert()
        alert.messageText = "刪除「\(entry.term)」？"
        alert.informativeText = "刪除後不再用於下一次辨識提示。"
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
        alert.informativeText = "這會刪除本機全部常用詞，但不會刪除 Groq API Key。"
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
        showsCandidates ? candidateRows.count : filteredEntries.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard let tableColumn else { return nil }
        if showsCandidates {
            guard candidateRows.indices.contains(row) else { return nil }
            let candidate = candidateRows[row]
            let state = candidate.state == "candidate" ? "待確認" : candidate.state == "added" ? (store.entries.contains { $0.id == candidate.entryID } ? "已加入" : "已移除") : "已拒絕"
            let text: String
            switch tableColumn.identifier {
            case Column.term: text = "\(candidate.original) → \(candidate.term)"
            case Column.enabled: text = state
            case Column.pinned: text = "本機修正"
            default: text = DateFormatter.localizedString(from: candidate.updatedAt, dateStyle: .short, timeStyle: .short)
            }
            let field = NSTextField(labelWithString: text)
            field.lineBreakMode = .byTruncatingTail
            field.toolTip = "\(text)；建立：\(candidate.createdAt)"
            return field
        }
        guard filteredEntries.indices.contains(row) else { return nil }
        let entry = filteredEntries[row]

        switch tableColumn.identifier {
        case Column.term:
            let field = NSTextField(labelWithString: entry.term)
            field.lineBreakMode = .byTruncatingTail
            field.toolTip = entry.term + (entry.isEnabled ? (learning.includedIDs.contains(entry.id) ? "：最近提示已納入" : "：最近提示未納入或尚未辨識") : "：已停用") + "；更新：\(entry.updatedAt)"
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
