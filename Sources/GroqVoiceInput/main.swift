import AppKit
import AVFoundation
import ApplicationServices
import Carbon
import Security

private let bundleID = "tw.panh.FreeVoiceType"
private let keychainService = "tw.panh.FreeVoiceType.groq"
private let keychainAccount = "api-key"
private let hotKeySignature: OSType = 0x56545950 // VTYP
private let hotKeyCodeDefaultsKey = "recordingHotKeyCode"
private let hotKeyModifiersDefaultsKey = "recordingHotKeyModifiers"

private struct HotKeyShortcut: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
}

private let defaultHotKey = HotKeyShortcut(
    keyCode: UInt32(kVK_UpArrow),
    modifiers: UInt32(optionKey)
)

private func shortcutDisplayName(_ shortcut: HotKeyShortcut) -> String {
    var result = ""
    if shortcut.modifiers & UInt32(controlKey) != 0 { result += "⌃" }
    if shortcut.modifiers & UInt32(optionKey) != 0 { result += "⌥" }
    if shortcut.modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
    if shortcut.modifiers & UInt32(cmdKey) != 0 { result += "⌘" }

    let names: [UInt32: String] = [
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Return): "↩",
        UInt32(kVK_Tab): "⇥",
        UInt32(kVK_Delete): "⌫",
        UInt32(kVK_Escape): "⎋",
        UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_Home): "↖",
        UInt32(kVK_End): "↘",
        UInt32(kVK_PageUp): "⇞",
        UInt32(kVK_PageDown): "⇟",
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B",
        UInt32(kVK_ANSI_C): "C", UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H",
        UInt32(kVK_ANSI_I): "I", UInt32(kVK_ANSI_J): "J",
        UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N",
        UInt32(kVK_ANSI_O): "O", UInt32(kVK_ANSI_P): "P",
        UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T",
        UInt32(kVK_ANSI_U): "U", UInt32(kVK_ANSI_V): "V",
        UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1",
        UInt32(kVK_ANSI_2): "2", UInt32(kVK_ANSI_3): "3",
        UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7",
        UInt32(kVK_ANSI_8): "8", UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2",
        UInt32(kVK_F3): "F3", UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9", UInt32(kVK_F10): "F10",
        UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12"
    ]
    result += names[shortcut.keyCode] ?? "KeyCode (shortcut.keyCode)"
    return result
}

private final class ShortcutRecorderView: NSView {
    private let shortcutLabel = NSTextField(labelWithString: "")
    private(set) var shortcut: HotKeyShortcut

    init(shortcut: HotKeyShortcut) {
        self.shortcut = shortcut
        super.init(frame: NSRect(x: 0, y: 0, width: 360, height: 72))

        shortcutLabel.alignment = .center
        shortcutLabel.font = .systemFont(ofSize: 24, weight: .medium)
        shortcutLabel.frame = NSRect(x: 0, y: 30, width: 360, height: 32)
        addSubview(shortcutLabel)

        let help = NSTextField(labelWithString: "點一下這裡，再按新的組合鍵（至少包含一個修飾鍵）")
        help.alignment = .center
        help.textColor = .secondaryLabelColor
        help.frame = NSRect(x: 0, y: 4, width: 360, height: 20)
        addSubview(help)
        updateLabel()
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        var modifiers: UInt32 = 0
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }

        guard modifiers != 0 else {
            NSSound.beep()
            return
        }
        shortcut = HotKeyShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        updateLabel()
    }

    private func updateLabel() {
        shortcutLabel.stringValue = shortcutDisplayName(shortcut)
    }
}

private final class APIKeySetupView: NSView {
    let keyField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 390, height: 26))

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 390, height: 142))

        let steps = NSTextField(wrappingLabelWithString: "1. 開啟 Groq API Keys 網頁並登入\n2. 按 Create API Key，複製以 gsk_ 開頭的金鑰\n3. 回到這裡貼上，再按「安全儲存」")
        steps.frame = NSRect(x: 0, y: 76, width: 390, height: 60)
        addSubview(steps)

        let openButton = NSButton(title: "開啟 Groq API Keys 網頁", target: self, action: #selector(openGroqKeysPage))
        openButton.bezelStyle = .rounded
        openButton.frame = NSRect(x: 0, y: 50, width: 210, height: 30)
        addSubview(openButton)

        keyField.placeholderString = "貼上 gsk_…"
        keyField.isEditable = true
        keyField.isSelectable = true
        keyField.frame = NSRect(x: 0, y: 20, width: 390, height: 26)
        addSubview(keyField)

        let privacy = NSTextField(labelWithString: "金鑰只儲存在這台 Mac 的鑰匙圈，不會寫入設定檔。")
        privacy.textColor = .secondaryLabelColor
        privacy.font = .systemFont(ofSize: 11)
        privacy.frame = NSRect(x: 0, y: 0, width: 390, height: 16)
        addSubview(privacy)

        if let clipboardKey = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           clipboardKey.hasPrefix("gsk_"),
           clipboardKey.count > 20 {
            keyField.stringValue = clipboardKey
        }
    }

    required init?(coder: NSCoder) { nil }

    @objc private func openGroqKeysPage() {
        NSWorkspace.shared.open(URL(string: "https://console.groq.com/keys")!)
    }
}

private var sharedController: VoiceTypeController?

private let hotKeyHandler: EventHandlerUPP = { _, _, _ in
    DispatchQueue.main.async {
        sharedController?.toggleRecording()
    }
    return noErr
}

final class VoiceTypeController: NSObject, NSApplicationDelegate, AVAudioRecorderDelegate {
    private var statusItem: NSStatusItem!
    private var toggleMenuItem: NSMenuItem!
    private var vocabularySyncMenuItem: NSMenuItem!
    private var remoteConnectionMenuItem: NSMenuItem!
    private var remoteTargetMenuItem: NSMenuItem!
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var currentHotKey = defaultHotKey
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var activeUploadURL: URL?
    private var isUploading = false
    private let remoteBridge = MacRemoteBridge()
    private let remoteTargetController = RemoteTargetController()
    private let pasteCorrectionMonitor = PasteCorrectionMonitor()
    private let vocabularyStore = MacVocabularyStore()
    private var vocabularyWindowController: VocabularyWindowController?
    private var vocabularySyncStatus = "等待 iPhone 連線"
    private var vocabularySyncHasError = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        sharedController = self
        cleanupStaleRecordings()
        currentHotKey = loadHotKey()
        configureStatusItem()
        registerHotKey()
        requestPermissions()
        configureRemoteInput()

        if CommandLine.arguments.contains("--show-vocabulary") {
            DispatchQueue.main.async { [weak self] in
                self?.showVocabularyWindow()
            }
        }
        if readAPIKey() == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.showAPIKeyDialog(firstRun: true)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        recorder?.stop()
        if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
        if let activeUploadURL { try? FileManager.default.removeItem(at: activeUploadURL) }
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        pasteCorrectionMonitor.stop()
        remoteBridge.stop()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "AI 語音輸入")

        let menu = NSMenu()
        let title = NSMenuItem(title: "AI 語音輸入", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(NSMenuItem.separator())

        toggleMenuItem = NSMenuItem(title: toggleMenuTitle(), action: #selector(toggleFromMenu), keyEquivalent: "")
        toggleMenuItem.target = self
        menu.addItem(toggleMenuItem)

        let shortcutItem = NSMenuItem(title: "設定快捷鍵…", action: #selector(showHotKeyDialog), keyEquivalent: "")
        shortcutItem.target = self
        menu.addItem(shortcutItem)

        let vocabularyItem = NSMenuItem(title: "常用詞典…", action: #selector(showVocabularyWindow), keyEquivalent: "")
        vocabularyItem.target = self
        menu.addItem(vocabularyItem)

        vocabularySyncMenuItem = NSMenuItem(title: "詞典同步：等待 iPhone 連線", action: nil, keyEquivalent: "")
        vocabularySyncMenuItem.isEnabled = false
        menu.addItem(vocabularySyncMenuItem)

        let keyItem = NSMenuItem(title: "設定／更換 Groq API 金鑰…", action: #selector(showAPIKeyFromMenu), keyEquivalent: "")
        keyItem.target = self
        menu.addItem(keyItem)

        let permissionsItem = NSMenuItem(title: "開啟輔助使用權限設定…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        permissionsItem.target = self
        menu.addItem(permissionsItem)

        menu.addItem(NSMenuItem.separator())
        remoteConnectionMenuItem = NSMenuItem(title: "iPhone 遠端：準備中…", action: nil, keyEquivalent: "")
        remoteConnectionMenuItem.isEnabled = false
        menu.addItem(remoteConnectionMenuItem)

        remoteTargetMenuItem = NSMenuItem(title: "尚未鎖定輸入框", action: nil, keyEquivalent: "")
        remoteTargetMenuItem.isEnabled = false
        menu.addItem(remoteTargetMenuItem)

        let pairingItem = NSMenuItem(title: "配對 iPhone…", action: #selector(showPairingCode), keyEquivalent: "")
        pairingItem.target = self
        menu.addItem(pairingItem)

        let forgetPhoneItem = NSMenuItem(title: "忘記已配對的 iPhone…", action: #selector(forgetPairedPhone), keyEquivalent: "")
        forgetPhoneItem.target = self
        menu.addItem(forgetPhoneItem)

        menu.addItem(NSMenuItem.separator())
        let quit = NSMenuItem(title: "結束 AI 語音輸入", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func configureRemoteInput() {
        vocabularyStore.onLocalChange = { [weak self] in
            self?.sendVocabularySnapshot(kind: .vocabularySync)
        }
        remoteBridge.onConnectionChange = { [weak self] status in
            self?.remoteConnectionMenuItem.title = "iPhone 遠端：\(status)"
        }
        remoteBridge.onConnectionStateChange = { [weak self] isConnected in
            guard let self else { return }
            if isConnected {
                self.sendVocabularySnapshot(kind: .vocabularySync)
            } else {
                self.updateVocabularySyncStatus("等待 iPhone 連線")
            }
        }
        remoteBridge.onPairingComplete = { [weak self] phoneName in
            guard let self else { return }
            self.remoteConnectionMenuItem.title = "iPhone 遠端：已配對 \(phoneName)"
            NSSound(named: "Glass")?.play()
        }
        remoteBridge.onMessage = { [weak self] message in
            guard let self else { return }
            switch message.kind {
            case .vocabularySync, .vocabularySyncAck:
                self.handleVocabularySyncMessage(message)
            default:
                self.remoteTargetController.handle(message) { [weak self] response in
                    self?.remoteBridge.send(response) ?? false
                }
            }
        }
        remoteTargetController.onTargetChange = { [weak self] status in
            self?.remoteTargetMenuItem.title = status
        }
        remoteTargetController.onPastedText = { [weak self] element, text in
            self?.pasteCorrectionMonitor.beginMonitoringAfterPaste(
                originalText: text,
                targetElement: element,
                verificationDelay: 0.08
            )
        }
        pasteCorrectionMonitor.onCandidate = { [weak self] candidate in
            self?.showVocabularySuggestion(candidate)
        }
        remoteBridge.start()
    }

    private func showVocabularySuggestion(_ candidate: MacVocabularyCandidate) {
        let suggestedTerm = candidate.suggestedTerm
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !suggestedTerm.isEmpty,
              !vocabularyStore.contains(term: suggestedTerm),
              vocabularyStore.entries.count < MacVocabularyStore.maximumEntryCount else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        let termField = NSTextField(
            frame: NSRect(x: 0, y: 0, width: 340, height: 26)
        )
        termField.stringValue = suggestedTerm
        termField.placeholderString = "可先修改詞彙"

        let alert = NSAlert()
        alert.messageText = "加入常用詞典？"
        if candidate.originalSegment.isEmpty {
            alert.informativeText = "你剛才在 Groq 貼入的文字中新增了這個詞。確認後才會保存並同步到 iPhone。"
        } else {
            alert.informativeText = "你剛才把「\(candidate.originalSegment)」修正為下面的詞。確認後才會保存並同步到 iPhone。"
        }
        alert.alertStyle = .informational
        alert.addButton(withTitle: "加入詞典")
        alert.addButton(withTitle: "這次不要")
        alert.accessoryView = termField
        alert.window.initialFirstResponder = termField

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try vocabularyStore.add(term: termField.stringValue)
            NSSound(named: "Glass")?.play()
        } catch MacVocabularyError.duplicateTerm {
            return
        } catch {
            showError(error.localizedDescription)
        }
    }

    @objc private func showVocabularyWindow() {
        if vocabularyWindowController == nil {
            vocabularyWindowController = VocabularyWindowController(store: vocabularyStore)
        }
        vocabularyWindowController?.updateSyncStatus(
            vocabularySyncStatus,
            isError: vocabularySyncHasError
        )
        vocabularyWindowController?.present()
    }

    @discardableResult
    private func sendVocabularySnapshot(kind: RemoteMessageKind) -> Bool {
        guard remoteBridge.connectedPhoneName != nil else {
            updateVocabularySyncStatus("等待 iPhone 連線")
            return false
        }
        updateVocabularySyncStatus("同步中…")
        let sent = remoteBridge.send(
            RemoteMessage(
                kind: kind,
                vocabulary: vocabularyStore.snapshot()
            )
        )
        if !sent {
            updateVocabularySyncStatus("等待重新連線", isError: true)
        }
        return sent
    }

    private func handleVocabularySyncMessage(_ message: RemoteMessage) {
        guard RemoteProtocolPolicy.supports(message.protocolVersion) else {
            updateVocabularySyncStatus("版本不相容，請更新兩端", isError: true)
            return
        }
        guard let payload = message.vocabulary else {
            updateVocabularySyncStatus("同步資料無效", isError: true)
            return
        }

        _ = vocabularyStore.merge(payload)
        switch message.kind {
        case .vocabularySync:
            if sendVocabularySnapshot(kind: .vocabularySyncAck) {
                updateVocabularySyncStatus("已同步")
            }
        case .vocabularySyncAck:
            updateVocabularySyncStatus("已同步")
        default:
            break
        }
    }

    private func updateVocabularySyncStatus(_ status: String, isError: Bool = false) {
        vocabularySyncStatus = status
        vocabularySyncHasError = isError
        vocabularySyncMenuItem.title = "詞典同步：\(status)"
        vocabularyWindowController?.updateSyncStatus(status, isError: isError)
    }

    @objc private func showPairingCode() {
        var randomValue: UInt32 = 0
        let status = withUnsafeMutableBytes(of: &randomValue) { bytes in
            SecRandomCopyBytes(kSecRandomDefault, bytes.count, bytes.baseAddress!)
        }
        guard status == errSecSuccess else {
            showError("無法建立安全配對碼，請再試一次。")
            return
        }

        let code = String(format: "%06u", randomValue % 1_000_000)
        remoteBridge.beginPairing(code: code)

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "配對 iPhone"
        alert.informativeText = "請在 iPhone 的「Mac 連線」中選擇這台 Mac，輸入配對碼：\n\n\(code)\n\n配對碼 5 分鐘後失效。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "完成")
        alert.runModal()
        NSApp.hide(nil)
    }

    @objc private func forgetPairedPhone() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "忘記已配對的 iPhone？"
        alert.informativeText = "之後若要使用遠端貼上，必須重新輸入一次配對碼。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "忘記")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            remoteTargetController.clearTarget()
            remoteBridge.forgetPairedPhone()
        }
        NSApp.hide(nil)
    }

    private func registerHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyHandler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        let registerStatus = registerCurrentHotKey()

        if installStatus != noErr || registerStatus != noErr {
            showError("無法註冊快捷鍵 (shortcutDisplayName(currentHotKey))。可能已被其他程式使用。")
        }
    }

    private func registerCurrentHotKey() -> OSStatus {
        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: 1)
        return RegisterEventHotKey(
            currentHotKey.keyCode,
            currentHotKey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func loadHotKey() -> HotKeyShortcut {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: hotKeyCodeDefaultsKey) != nil,
              defaults.object(forKey: hotKeyModifiersDefaultsKey) != nil else {
            return defaultHotKey
        }
        return HotKeyShortcut(
            keyCode: UInt32(defaults.integer(forKey: hotKeyCodeDefaultsKey)),
            modifiers: UInt32(defaults.integer(forKey: hotKeyModifiersDefaultsKey))
        )
    }

    private func saveHotKey(_ shortcut: HotKeyShortcut) {
        UserDefaults.standard.set(Int(shortcut.keyCode), forKey: hotKeyCodeDefaultsKey)
        UserDefaults.standard.set(Int(shortcut.modifiers), forKey: hotKeyModifiersDefaultsKey)
    }

    private func toggleMenuTitle() -> String {
        "開始／停止錄音（(shortcutDisplayName(currentHotKey))）"
    }

    @objc private func showHotKeyDialog() {
        NSApp.activate(ignoringOtherApps: true)
        let recorder = ShortcutRecorderView(shortcut: currentHotKey)
        let alert = NSAlert()
        alert.messageText = "設定錄音快捷鍵"
        alert.informativeText = "按下你想使用的全域快捷鍵。若與其他 App 衝突，將保留目前設定。"
        alert.alertStyle = .informational
        alert.accessoryView = recorder
        alert.addButton(withTitle: "儲存")
        alert.addButton(withTitle: "取消")
        alert.window.initialFirstResponder = recorder

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        applyHotKey(recorder.shortcut)
    }

    private func applyHotKey(_ newHotKey: HotKeyShortcut) {
        guard newHotKey != currentHotKey else { return }
        let previous = currentHotKey
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        currentHotKey = newHotKey
        let status = registerCurrentHotKey()
        guard status == noErr else {
            currentHotKey = previous
            _ = registerCurrentHotKey()
            showError("快捷鍵 (shortcutDisplayName(newHotKey)) 無法使用，可能已被其他程式占用。原設定 (shortcutDisplayName(previous)) 已保留。")
            return
        }

        saveHotKey(newHotKey)
        toggleMenuItem.title = toggleMenuTitle()
        NSSound(named: "Glass")?.play()
    }

    private func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @objc private func toggleFromMenu() {
        toggleRecording()
    }

    func toggleRecording() {
        guard !isUploading else {
            NSSound.beep()
            return
        }

        if recorder?.isRecording == true {
            stopRecordingAndTranscribe()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard readAPIKey() != nil else {
            showAPIKeyDialog(firstRun: false)
            return
        }

        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            showError("尚未允許麥克風。請到「系統設定 → 隱私權與安全性 → 麥克風」開啟 AI 語音輸入。")
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FreeVoiceType-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let newRecorder = try AVAudioRecorder(url: url, settings: settings)
            newRecorder.delegate = self
            newRecorder.prepareToRecord()
            guard newRecorder.record() else {
                try? FileManager.default.removeItem(at: url)
                showError("無法開始錄音。")
                return
            }
            recorder = newRecorder
            recordingURL = url
            statusItem.button?.image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "正在錄音")
            statusItem.button?.contentTintColor = .systemRed
            NSSound(named: "Tink")?.play()
        } catch {
            try? FileManager.default.removeItem(at: url)
            showError("無法開始錄音：\(error.localizedDescription)")
        }
    }

    private func stopRecordingAndTranscribe() {
        recorder?.stop()
        recorder = nil
        statusItem.button?.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "正在辨識")
        statusItem.button?.contentTintColor = .systemOrange
        NSSound(named: "Pop")?.play()

        guard let url = recordingURL, let apiKey = readAPIKey() else {
            if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
            recordingURL = nil
            resetStatus()
            return
        }
        recordingURL = nil
        activeUploadURL = url
        isUploading = true
        let vocabularyPrompt = vocabularyStore.buildPrompt()
        vocabularyStore.recordPromptUse(entryIDs: vocabularyPrompt.includedEntryIDs)

        transcribe(url: url, apiKey: apiKey, prompt: vocabularyPrompt.text) { result in
            DispatchQueue.main.async {
                self.isUploading = false
                try? FileManager.default.removeItem(at: url)
                self.activeUploadURL = nil
                self.resetStatus()

                switch result {
                case .success(let text):
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        self.showError("沒有辨識到語音，請再試一次。")
                        return
                    }
                    self.copyAndPaste(text)
                case .failure(let error):
                    self.showError(error.localizedDescription)
                }
            }
        }
    }

    private func transcribe(
        url: URL,
        apiKey: String,
        prompt: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let audioData = try Data(contentsOf: url)
                let boundary = "Boundary-\(UUID().uuidString)"
                var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!)
                request.httpMethod = "POST"
                request.timeoutInterval = 90
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

                var body = Data()
                func addField(_ name: String, _ value: String) {
                    body.append("--\(boundary)\r\n".data(using: .utf8)!)
                    body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
                    body.append("\(value)\r\n".data(using: .utf8)!)
                }
                addField("model", "whisper-large-v3")
                addField("language", "zh")
                addField("response_format", "json")
                addField("temperature", "0")
                addField("prompt", prompt)

                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"file\"; filename=\"speech.m4a\"\r\n".data(using: .utf8)!)
                body.append("Content-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
                body.append(audioData)
                body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
                request.httpBody = body

                URLSession.shared.dataTask(with: request) { data, response, error in
                    if let error {
                        completion(.failure(VoiceTypeError.message("雲端辨識失敗：\(error.localizedDescription)")))
                        return
                    }
                    guard let http = response as? HTTPURLResponse, let data else {
                        completion(.failure(VoiceTypeError.message("雲端沒有回傳有效結果。")))
                        return
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                            .flatMap { $0["error"] as? [String: Any] }?
                            .flatMap { $0["message"] as? String }
                        completion(.failure(VoiceTypeError.message(detail ?? "Groq 回傳錯誤（HTTP \(http.statusCode)）。")))
                        return
                    }
                    guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let text = object["text"] as? String else {
                        completion(.failure(VoiceTypeError.message("無法讀取辨識結果。")))
                        return
                    }
                    completion(.success(text))
                }.resume()
            } catch {
                completion(.failure(VoiceTypeError.message("無法讀取錄音：\(error.localizedDescription)")))
            }
        }
    }

    private func copyAndPaste(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard AXIsProcessTrusted() else {
            showError("文字已複製到剪貼簿，但尚未取得「輔助使用」權限，所以無法自動貼上。請開啟權限後再試。")
            openAccessibilitySettings()
            return
        }

        let correctionTarget = pasteCorrectionMonitor.captureFocusedEditableElement()
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        if let correctionTarget {
            pasteCorrectionMonitor.beginMonitoringAfterPaste(
                originalText: text,
                targetElement: correctionTarget
            )
        }
        NSSound(named: "Glass")?.play()
    }

    private func resetStatus() {
        statusItem.button?.image = NSImage(systemSymbolName: "mic", accessibilityDescription: "AI 語音輸入")
        statusItem.button?.contentTintColor = nil
    }

    private func cleanupStaleRecordings() {
        let temporaryDirectory = FileManager.default.temporaryDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files where file.lastPathComponent.hasPrefix("FreeVoiceType-") && file.pathExtension == "m4a" {
            try? FileManager.default.removeItem(at: file)
        }
    }

    @objc private func showAPIKeyFromMenu() {
        showAPIKeyDialog(firstRun: false)
    }

    private func showAPIKeyDialog(firstRun: Bool) {
        NSApp.activate(ignoringOtherApps: true)
        let setupView = APIKeySetupView()
        let alert = NSAlert()
        alert.messageText = firstRun ? "歡迎使用 AI 語音輸入" : "設定／更換 Groq API 金鑰"
        alert.informativeText = "這個 App 使用 Groq Whisper 將語音轉成文字。每位使用者都要使用自己的 Groq API Key。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "安全儲存")
        alert.addButton(withTitle: "稍後設定")
        alert.accessoryView = setupView
        alert.window.initialFirstResponder = setupView.keyField

        if alert.runModal() == .alertFirstButtonReturn {
            let key = setupView.keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard key.hasPrefix("gsk_") && key.count > 20 else {
                showError("這看起來不是有效的 Groq API Key。請確認已完整貼上以 gsk_ 開頭的金鑰。")
                return
            }
            do {
                try saveAPIKey(key)
                NSSound(named: "Glass")?.play()
                if firstRun {
                    let success = NSAlert()
                    success.messageText = "Groq API Key 已安全儲存"
                    success.informativeText = "現在可在任何文字輸入位置按 (shortcutDisplayName(currentHotKey)) 開始錄音，再按一次停止並貼上辨識文字。"
                    success.addButton(withTitle: "開始使用")
                    success.runModal()
                }
            } catch {
                showError("無法把金鑰存入鑰匙圈：\(error.localizedDescription)")
            }
        }
    }

    private func readAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8),
              !key.isEmpty else { return nil }
        return key
    }

    private func saveAPIKey(_ key: String) throws {
        let data = Data(key.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        let updateStatus = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw VoiceTypeError.message("Keychain 錯誤 \(addStatus)") }
        } else if updateStatus != errSecSuccess {
            throw VoiceTypeError.message("Keychain 錯誤 \(updateStatus)")
        }
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func showError(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "AI 語音輸入"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
        resetStatus()
    }
}

enum VoiceTypeError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let value): return value
        }
    }
}

let app = NSApplication.shared
let delegate = VoiceTypeController()
app.delegate = delegate
app.run()
