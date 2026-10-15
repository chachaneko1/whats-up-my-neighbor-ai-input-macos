import AppKit
import Carbon

final class ShortcutRecorderView: NSView {
    private let shortcutLabel = NSTextField(labelWithString: "")
    private(set) var shortcut: HotKeyShortcut
    /// 使用者是否在這個畫面實際按過組合鍵。用來分辨「沿用舊值」與「刻意不設定」。
    private(set) var didRecord = false

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
        didRecord = true
        updateLabel()
    }

    /// 清除本次錄製，回到「未設定」狀態。
    func reset() {
        didRecord = false
        shortcutLabel.stringValue = "未設定"
    }

    private func updateLabel() {
        shortcutLabel.stringValue = shortcutDisplayName(shortcut)
    }
}

final class APIKeySetupView: NSView {
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

final class LanguageSettingsView: NSView {
    private let primaryPopUp = NSPopUpButton(frame: NSRect(x: 110, y: 148, width: 200, height: 26))
    private let firstPopUp = NSPopUpButton(frame: NSRect(x: 110, y: 116, width: 200, height: 26))
    private let secondPopUp = NSPopUpButton(frame: NSRect(x: 110, y: 84, width: 200, height: 26))
    private let retryCheckbox: NSButton

    init(settings: LanguageSettings) {
        retryCheckbox = NSButton(checkboxWithTitle: "偵測到未允許語言時自動重試一次", target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: 400, height: 186))

        addLabel("主要語言", y: 152)
        addLabel("允許混用 1", y: 120)
        addLabel("允許混用 2", y: 88)

        for option in LanguageOption.allCases {
            primaryPopUp.addItem(withTitle: option.displayName)
        }
        primaryPopUp.selectItem(at: LanguageOption.allCases.firstIndex(of: settings.primary) ?? 0)
        addSubview(primaryPopUp)

        for popUp in [firstPopUp, secondPopUp] {
            popUp.addItem(withTitle: "不使用")
            for option in LanguageOption.allCases {
                popUp.addItem(withTitle: option.displayName)
            }
            addSubview(popUp)
        }
        selectOptional(firstPopUp, settings.additional.first)
        selectOptional(secondPopUp, settings.additional.dropFirst().first)

        retryCheckbox.state = settings.automaticRetryEnabled ? .on : .off
        retryCheckbox.frame = NSRect(x: 0, y: 52, width: 400, height: 20)
        addSubview(retryCheckbox)

        let note = NSTextField(wrappingLabelWithString:
            "語言檢查看的是文字系統，不是語言本身。英文、西班牙文、越南文都寫成拉丁字母，無法互相區分——選其中任一個，效果都等於允許拉丁字母。")
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 11)
        note.frame = NSRect(x: 0, y: 0, width: 400, height: 46)
        addSubview(note)
    }

    required init?(coder: NSCoder) { nil }

    func currentSettings() -> LanguageSettings {
        let primary = LanguageOption.allCases[primaryPopUp.indexOfSelectedItem]
        let additional = [firstPopUp, secondPopUp].compactMap { popUp -> LanguageOption? in
            let index = popUp.indexOfSelectedItem
            guard index > 0 else { return nil }
            return LanguageOption.allCases[index - 1]
        }
        return LanguageSettings(
            primary: primary,
            additional: additional,
            automaticRetryEnabled: retryCheckbox.state == .on
        )
    }

    private func selectOptional(_ popUp: NSPopUpButton, _ option: LanguageOption?) {
        guard let option, let index = LanguageOption.allCases.firstIndex(of: option) else {
            popUp.selectItem(at: 0)
            return
        }
        popUp.selectItem(at: index + 1)
    }

    private func addLabel(_ text: String, y: CGFloat) {
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: 0, y: y, width: 105, height: 18)
        addSubview(label)
    }
}

final class TextSettingsView: NSView {
    private let numeralsCheckbox: NSButton
    private let silencePopUp = NSPopUpButton(frame: NSRect(x: 150, y: 196, width: 160, height: 26))
    private let alternateModePopUp = NSPopUpButton(frame: NSRect(x: 150, y: 140, width: 270, height: 26))
    private let shortcutRecorder: ShortcutRecorderView
    private let clearShortcutButton: NSButton
    private var hasShortcut: Bool

    private let silenceChoices = [0, 3, 5, 10]

    init(convertNumerals: Bool, silenceSeconds: Int, alternateShortcut: HotKeyShortcut?, alternateMode: TextOutputMode) {
        numeralsCheckbox = NSButton(
            checkboxWithTitle: "把中文數字轉成阿拉伯數字（第一百五十九條 → 第159條）",
            target: nil,
            action: nil
        )
        shortcutRecorder = ShortcutRecorderView(shortcut: alternateShortcut ?? defaultHotKey)
        clearShortcutButton = NSButton(title: "清除", target: nil, action: nil)
        hasShortcut = alternateShortcut != nil
        super.init(frame: NSRect(x: 0, y: 0, width: 430, height: 296))

        numeralsCheckbox.state = convertNumerals ? .on : .off
        numeralsCheckbox.frame = NSRect(x: 0, y: 268, width: 430, height: 20)
        addSubview(numeralsCheckbox)
        addNote("只轉換法條、金額與百分比，成語裡的數字不會被動到。", x: 18, y: 248, width: 412)

        addLabel("靜音自動停止", y: 200)
        silencePopUp.addItem(withTitle: "關閉")
        for seconds in silenceChoices.dropFirst() {
            silencePopUp.addItem(withTitle: "\(seconds) 秒")
        }
        silencePopUp.selectItem(at: silenceChoices.firstIndex(of: silenceSeconds) ?? 0)
        addSubview(silencePopUp)
        addNote("錄音最長 5 分鐘，此保護一律啟用。", x: 150, y: 176, width: 280)

        addLabel("第二快捷鍵用", y: 144)
        for mode in TextOutputMode.allCases {
            alternateModePopUp.addItem(withTitle: mode.displayName)
        }
        alternateModePopUp.selectItem(at: TextOutputMode.allCases.firstIndex(of: alternateMode) ?? 0)
        addSubview(alternateModePopUp)

        // ShortcutRecorderView 的內部佈局固定為 360×72，必須給它原本的尺寸。
        shortcutRecorder.frame = NSRect(x: 0, y: 52, width: 360, height: 72)
        if alternateShortcut == nil { shortcutRecorder.reset() }
        addSubview(shortcutRecorder)

        clearShortcutButton.bezelStyle = .rounded
        clearShortcutButton.target = self
        clearShortcutButton.action = #selector(clearShortcut)
        clearShortcutButton.frame = NSRect(x: 364, y: 72, width: 66, height: 32)
        addSubview(clearShortcutButton)

        addNote("第二快捷鍵只影響當次錄音，不改變預設模式。未設定時只有主快捷鍵有作用。", x: 0, y: 8, width: 430, height: 32)
    }

    required init?(coder: NSCoder) { nil }

    var convertNumerals: Bool { numeralsCheckbox.state == .on }

    var silenceSeconds: Int {
        let index = silencePopUp.indexOfSelectedItem
        return index >= 0 && index < silenceChoices.count ? silenceChoices[index] : 0
    }

    var alternateMode: TextOutputMode {
        TextOutputMode.allCases[max(0, alternateModePopUp.indexOfSelectedItem)]
    }

    var alternateShortcut: HotKeyShortcut? {
        guard hasShortcut || shortcutRecorder.didRecord else { return nil }
        return shortcutRecorder.shortcut
    }

    @objc private func clearShortcut() {
        hasShortcut = false
        shortcutRecorder.reset()
    }

    private func addLabel(_ text: String, y: CGFloat) {
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: 0, y: y, width: 145, height: 18)
        addSubview(label)
    }

    private func addNote(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat = 16) {
        let note = NSTextField(wrappingLabelWithString: text)
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 11)
        note.frame = NSRect(x: x, y: y, width: width, height: height)
        addSubview(note)
    }
}

/// iPhone 接力與錄音麥克風的設定。
///
/// 這兩件事放在同一個面板，是因為使用者感受到的是同一個症狀（「它自己連到手機」），
/// 但底下其實是兩個獨立機制：接力模式管的是手機能不能連上來貼字；錄音麥克風管的是
/// macOS 的連續互通麥克風會不會把 Mac 的錄音來源搶走。
final class RelaySettingsView: NSView {
    private let shortcutRecorder: ShortcutRecorderView
    private let clearShortcutButton: NSButton
    private var hasShortcut: Bool
    private let continuityCheckbox: NSButton
    private let devicePopUp = NSPopUpButton(frame: NSRect(x: 110, y: 108, width: 350, height: 26))
    private let devices: [AudioInputDevice]

    init(
        relayShortcut: HotKeyShortcut?,
        preferredDeviceUID: String?,
        allowContinuityMicrophone: Bool,
        devices: [AudioInputDevice]
    ) {
        shortcutRecorder = ShortcutRecorderView(shortcut: relayShortcut ?? defaultRelayHotKey)
        clearShortcutButton = NSButton(title: "清除", target: nil, action: nil)
        hasShortcut = relayShortcut != nil
        continuityCheckbox = NSButton(
            checkboxWithTitle: "允許使用 iPhone 連續互通麥克風錄音",
            target: nil,
            action: nil
        )
        self.devices = devices
        super.init(frame: NSRect(x: 0, y: 0, width: 460, height: 316))

        addNote(
            "接力模式關閉時，Mac 不會廣播、也不接受任何 iPhone 連線，等於只用電腦輸入。"
            + "需要用手機講話時再開啟即可。App 每次啟動一律是關閉狀態。",
            x: 0, y: 272, width: 460, height: 44
        )

        addLabel("接力模式快捷鍵", x: 0, y: 248, width: 460)

        // ShortcutRecorderView 的內部佈局固定為 360×72，必須給它原本的尺寸。
        shortcutRecorder.frame = NSRect(x: 0, y: 170, width: 360, height: 72)
        if relayShortcut == nil { shortcutRecorder.reset() }
        addSubview(shortcutRecorder)

        clearShortcutButton.bezelStyle = .rounded
        clearShortcutButton.target = self
        clearShortcutButton.action = #selector(clearShortcut)
        clearShortcutButton.frame = NSRect(x: 368, y: 190, width: 66, height: 32)
        addSubview(clearShortcutButton)

        addNote("未設定時仍可從選單列切換接力模式。", x: 0, y: 146, width: 460)

        addLabel("錄音麥克風", x: 0, y: 112, width: 105)
        devicePopUp.addItem(withTitle: "自動（排除 iPhone）")
        for device in devices {
            let suffix = AudioInputPolicy.isContinuityCapture(device.transportType) ? "（iPhone 連續互通）" : ""
            devicePopUp.addItem(withTitle: device.name + suffix)
        }
        if let preferredDeviceUID,
           let index = devices.firstIndex(where: { $0.uid == preferredDeviceUID }) {
            devicePopUp.selectItem(at: index + 1)
        } else {
            devicePopUp.selectItem(at: 0)
        }
        addSubview(devicePopUp)
        addNote(
            "「自動」會沿用系統目前的輸入裝置，但排除 iPhone。AirPods 與 USB 麥克風不受影響。",
            x: 110, y: 78, width: 350, height: 26
        )

        continuityCheckbox.state = allowContinuityMicrophone ? .on : .off
        continuityCheckbox.frame = NSRect(x: 0, y: 52, width: 460, height: 20)
        addSubview(continuityCheckbox)
        addNote(
            "連續互通麥克風是 macOS 的功能，手機 App 沒開、手機鎖屏、手機在別的房間都會出現在裝置清單裡。"
            + "勾選後 Mac 錄音可能會被隔空轉到 iPhone 上，通常只會錄到靜音。",
            x: 18, y: 0, width: 442, height: 46
        )
    }

    required init?(coder: NSCoder) { nil }

    var relayShortcut: HotKeyShortcut? {
        guard hasShortcut || shortcutRecorder.didRecord else { return nil }
        return shortcutRecorder.shortcut
    }

    /// 回傳 nil 代表「自動」，交給 `AudioInputPolicy` 決定。
    var preferredDeviceUID: String? {
        let index = devicePopUp.indexOfSelectedItem
        guard index > 0, index - 1 < devices.count else { return nil }
        return devices[index - 1].uid
    }

    var allowContinuityMicrophone: Bool { continuityCheckbox.state == .on }

    @objc private func clearShortcut() {
        hasShortcut = false
        shortcutRecorder.reset()
    }

    private func addLabel(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat) {
        let label = NSTextField(labelWithString: text)
        label.frame = NSRect(x: x, y: y, width: width, height: 18)
        addSubview(label)
    }

    private func addNote(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat = 20) {
        let note = NSTextField(wrappingLabelWithString: text)
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 11)
        note.frame = NSRect(x: x, y: y, width: width, height: height)
        addSubview(note)
    }
}
