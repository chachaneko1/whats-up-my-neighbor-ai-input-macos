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
private let textOutputModeDefaultsKey = "textOutputMode"
private let alternateHotKeyCodeDefaultsKey = "alternateHotKeyCode"
private let alternateHotKeyModifiersDefaultsKey = "alternateHotKeyModifiers"
private let alternateOutputModeDefaultsKey = "alternateOutputMode"
private let primaryLanguageDefaultsKey = "primaryLanguage"
private let additionalLanguagesDefaultsKey = "additionalLanguages"
private let automaticLanguageRetryDefaultsKey = "automaticLanguageRetry"
private let convertChineseNumeralsDefaultsKey = "convertChineseNumerals"
private let silenceAutoStopSecondsDefaultsKey = "silenceAutoStopSeconds"
private let relayHotKeyCodeDefaultsKey = "relayHotKeyCode"
private let relayHotKeyModifiersDefaultsKey = "relayHotKeyModifiers"
private let preferredInputDeviceUIDDefaultsKey = "preferredInputDeviceUID"
private let allowContinuityMicrophoneDefaultsKey = "allowContinuityMicrophone"

/// 三組快捷鍵的識別碼，用來在事件處理器裡分辨是哪一個被按下。
private let primaryHotKeyID: UInt32 = 1
private let alternateHotKeyID: UInt32 = 2
private let relayHotKeyID: UInt32 = 3

/// 最長錄音時間。純保護機制，不可能誤停，用來防止忘記按第二次快捷鍵。
private let maximumRecordingDuration: TimeInterval = 300

/// 靜音偵測的取樣間隔與音量門檻（dBFS）。
private let meteringInterval: TimeInterval = 0.2
private let silenceThresholdDecibels: Float = -45

/// 同一段錄音允許的額外 Groq 請求上限（未允許語言重試 1 次 ＋ 備用金鑰重試 1 次）。
/// 避免多個重試機制互相觸發成迴圈。
private let maximumExtraRequestsPerRecording = 2

/// 辨識失敗後暫留錄音的時間上限，與多金鑰備援的暫存規則一致。
private let recordingRetentionInterval: TimeInterval = 120

private struct HotKeyShortcut: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
}

private let defaultHotKey = HotKeyShortcut(
    keyCode: UInt32(kVK_UpArrow),
    modifiers: UInt32(optionKey)
)

/// 切換 iPhone 接力模式的預設快捷鍵。
///
/// 沿用主快捷鍵的 ↑ 好記，但用 ⌃⌥ 而不是 ⌥⇧：`⌥⇧↑` 是 macOS 標準的「向上延伸
/// 選取」，被 `RegisterEventHotKey` 全域攔截後，每個 App 的文字選取都會壞掉。
private let defaultRelayHotKey = HotKeyShortcut(
    keyCode: UInt32(kVK_UpArrow),
    modifiers: UInt32(controlKey) | UInt32(optionKey)
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
    result += names[shortcut.keyCode] ?? "KeyCode \(shortcut.keyCode)"
    return result
}

private final class ShortcutRecorderView: NSView {
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

private final class LanguageSettingsView: NSView {
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

private final class TextSettingsView: NSView {
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
private final class RelaySettingsView: NSView {
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

private var sharedController: VoiceTypeController?

private let hotKeyHandler: EventHandlerUPP = { _, event, _ in
    // 讀出是哪一個快捷鍵被按下，才能分辨主快捷鍵與第二快捷鍵。
    var identifier = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier
    )
    let pressedID = status == noErr ? identifier.id : primaryHotKeyID
    DispatchQueue.main.async {
        if pressedID == relayHotKeyID {
            sharedController?.toggleRelayMode()
        } else {
            sharedController?.toggleRecording(useAlternateMode: pressedID == alternateHotKeyID)
        }
    }
    return noErr
}

final class VoiceTypeController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var toggleMenuItem: NSMenuItem!
    private var remoteConnectionMenuItem: NSMenuItem!
    private var remoteTargetMenuItem: NSMenuItem!
    private var relayMenuItem: NSMenuItem!
    private var modeMenuItems: [TextOutputMode: NSMenuItem] = [:]
    private var hotKeyRef: EventHotKeyRef?
    private var alternateHotKeyRef: EventHotKeyRef?
    private var relayHotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var currentHotKey = defaultHotKey
    private var alternateHotKey: HotKeyShortcut?
    private var relayHotKey: HotKeyShortcut? = defaultRelayHotKey
    private var alternateOutputMode: TextOutputMode = .concise
    private var languageSettings = LanguageSettings.default
    private var convertChineseNumerals = false
    /// 0 表示關閉。關閉是預設值，因為思考中的停頓會被誤判成講完了。
    private var silenceAutoStopSeconds = 0
    /// 本次執行期間的金鑰快取，只存在記憶體。見 `readAPIKey()` 的說明。
    private var cachedAPIKey: String?
    private var meteringTimer: Timer?
    private var recordingStartedAt: Date?
    private var lastLoudAt: Date?
    /// 本次錄音實際採用的模式。第二快捷鍵只影響當次，不改變儲存的偏好。
    private var activeOutputMode: TextOutputMode = .verbatim
    private let micRecorder = PinnedMicrophoneRecorder()
    /// 使用者指定的固定錄音裝置。nil 表示「自動」，由 `AudioInputPolicy` 決定。
    private var preferredInputDeviceUID: String?
    /// 是否允許用 iPhone 的連續互通麥克風錄音。預設不允許，這正是「收不到音」的來源。
    private var allowContinuityMicrophone = false
    /// iPhone 接力模式是否開啟。
    ///
    /// 刻意不寫入 `UserDefaults`：使用者回報的問題就是「它常常自己連到手機」，
    /// 所以每次啟動一律從關閉開始，不讓上次忘記關的狀態延續到下次。
    private var isRelayModeEnabled = false
    private var recordingURL: URL?
    private var activeUploadURL: URL?
    private var isUploading = false
    private var textOutputMode: TextOutputMode = .verbatim
    /// 辨識失敗後暫留、等待使用者決定是否重新辨識的錄音。
    private var pendingRetryURL: URL?
    /// 本段錄音已使用的額外請求次數，上限 `maximumExtraRequestsPerRecording`。
    private var extraRequestCount = 0
    private let remoteBridge = MacRemoteBridge()
    private let remoteTargetController = RemoteTargetController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        sharedController = self
        cleanupStaleRecordings()
        currentHotKey = loadHotKey()
        textOutputMode = loadTextOutputMode()
        activeOutputMode = textOutputMode
        languageSettings = loadLanguageSettings()
        loadTextSettings()
        loadRelaySettings()
        configureStatusItem()
        registerHotKey()
        requestPermissions()
        configureRecorder()
        configureRemoteInput()

        if readAPIKey() == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.showAPIKeyDialog(firstRun: true)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        micRecorder.shutdown()
        if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
        if let activeUploadURL { try? FileManager.default.removeItem(at: activeUploadURL) }
        if let pendingRetryURL { try? FileManager.default.removeItem(at: pendingRetryURL) }
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let alternateHotKeyRef { UnregisterEventHotKey(alternateHotKeyRef) }
        if let relayHotKeyRef { UnregisterEventHotKey(relayHotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
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

        let modeItem = NSMenuItem(title: "文字輸出模式", action: nil, keyEquivalent: "")
        let modeMenu = NSMenu()
        for mode in TextOutputMode.allCases {
            let item = NSMenuItem(
                title: mode.displayName,
                action: #selector(selectOutputMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode.rawValue
            modeMenu.addItem(item)
            modeMenuItems[mode] = item
        }
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)
        updateTextOutputModeMenu()

        let languageItem = NSMenuItem(title: "語言設定…", action: #selector(showLanguageDialog), keyEquivalent: "")
        languageItem.target = self
        menu.addItem(languageItem)

        let textSettingsItem = NSMenuItem(title: "文字與錄音設定…", action: #selector(showTextSettingsDialog), keyEquivalent: "")
        textSettingsItem.target = self
        menu.addItem(textSettingsItem)

        let shortcutItem = NSMenuItem(title: "設定快捷鍵…", action: #selector(showHotKeyDialog), keyEquivalent: "")
        shortcutItem.target = self
        menu.addItem(shortcutItem)

        let keyItem = NSMenuItem(title: "設定／更換 Groq API 金鑰…", action: #selector(showAPIKeyFromMenu), keyEquivalent: "")
        keyItem.target = self
        menu.addItem(keyItem)

        let permissionsItem = NSMenuItem(title: "開啟輔助使用權限設定…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        permissionsItem.target = self
        menu.addItem(permissionsItem)

        menu.addItem(NSMenuItem.separator())
        relayMenuItem = NSMenuItem(
            title: relayMenuTitle(),
            action: #selector(toggleRelayFromMenu),
            keyEquivalent: ""
        )
        relayMenuItem.target = self
        menu.addItem(relayMenuItem)

        remoteConnectionMenuItem = NSMenuItem(title: "iPhone 遠端：準備中…", action: nil, keyEquivalent: "")
        remoteConnectionMenuItem.isEnabled = false
        menu.addItem(remoteConnectionMenuItem)

        remoteTargetMenuItem = NSMenuItem(title: "尚未鎖定輸入框", action: nil, keyEquivalent: "")
        remoteTargetMenuItem.isEnabled = false
        menu.addItem(remoteTargetMenuItem)

        let relaySettingsItem = NSMenuItem(
            title: "iPhone 接力與麥克風設定…",
            action: #selector(showRelaySettingsDialog),
            keyEquivalent: ""
        )
        relaySettingsItem.target = self
        menu.addItem(relaySettingsItem)

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
        updateRelayMenu()
    }

    private func configureRemoteInput() {
        remoteBridge.onConnectionChange = { [weak self] status in
            self?.remoteConnectionMenuItem.title = "iPhone 遠端：\(status)"
        }
        remoteBridge.onPairingComplete = { [weak self] phoneName in
            guard let self else { return }
            self.remoteConnectionMenuItem.title = "iPhone 遠端：已配對 \(phoneName)"
            NSSound(named: "Glass")?.play()
        }
        remoteBridge.onMessage = { [weak self] message in
            guard let self else { return }
            self.remoteTargetController.handle(message) { [weak self] response in
                self?.remoteBridge.send(response) ?? false
            }
        }
        remoteTargetController.onTargetChange = { [weak self] status in
            self?.remoteTargetMenuItem.title = status
        }
        // 這裡刻意不呼叫 remoteBridge.start()。以前它在啟動時就無條件開始廣播，
        // 而且對已配對的手機是零確認自動接受，等於 App 一開就永遠在等手機連進來。
        // 現在只有使用者明確開啟接力模式時才會開始廣播。
    }

    /// 把錄音器的三個非同步回呼接到 UI 與轉錄流程上。
    ///
    /// 改用 `AVCaptureSession` 之後，開始與結束都不再是同步完成的，這個方法就是
    /// 兩者的銜接點。細節見 `PinnedMicrophoneRecorder` 的說明。
    private func configureRecorder() {
        micRecorder.onRecordingStarted = { [weak self] in
            guard let self else { return }
            self.startMetering()
            self.statusItem.button?.image = NSImage(
                systemSymbolName: "record.circle.fill",
                accessibilityDescription: "正在錄音"
            )
            self.statusItem.button?.contentTintColor = .systemRed
            // 提示音刻意留到這一刻才播。使用者的既有習慣是「聽到 Tink 就開始講」，
            // 若在按下快捷鍵當下就播，錄音裝置還沒就緒，第一個字會被吃掉。
            NSSound(named: "Tink")?.play()
        }

        micRecorder.onStartFailed = { [weak self] error in
            guard let self else { return }
            if let url = self.recordingURL {
                try? FileManager.default.removeItem(at: url)
                self.recordingURL = nil
            }
            self.showError("無法開始錄音：\(error.localizedDescription)")
        }

        micRecorder.onRecordingFinished = { [weak self] url, error in
            self?.handleRecordingFinished(url: url, error: error)
        }
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

        // 配對必須讓 iPhone 找得到這台 Mac，而那需要 Mac 正在廣播。接力模式預設
        // 是關的，如果不在這裡暫時開啟，iPhone 會永遠掃不到 Mac，配對功能等於整個
        // 壞掉——而且因為平常不會重新配對，這種壞法可能很久以後才被發現。
        let relayModeBeforePairing = isRelayModeEnabled
        if !relayModeBeforePairing { setRelayMode(enabled: true, playSound: false) }
        remoteBridge.beginPairing(code: code)

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "配對 iPhone"
        var informativeText = "請在 iPhone 的「Mac 連線」中選擇這台 Mac，輸入配對碼：\n\n\(code)\n\n配對碼 5 分鐘後失效。"
        if !relayModeBeforePairing {
            informativeText += "\n\n配對期間會暫時開啟接力模式。關閉這個視窗後會恢復原狀，"
                + "之後要用 iPhone 輸入時，請按 \(shortcutDisplayName(relayHotKey ?? defaultRelayHotKey)) 或從選單列開啟接力模式。"
        }
        alert.informativeText = informativeText
        alert.alertStyle = .informational
        alert.addButton(withTitle: "完成")
        alert.runModal()

        remoteBridge.endPairing()
        // 一律還原成使用者原本選擇的狀態。配對成功就自動留在接力模式，正是這次要
        // 消除的「沒同意就連上手機」，所以寧可讓使用者自己再按一次。
        if !relayModeBeforePairing { setRelayMode(enabled: false, playSound: false) }
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

    // MARK: - iPhone 接力模式

    func toggleRelayMode() {
        setRelayMode(enabled: !isRelayModeEnabled)
    }

    @objc private func toggleRelayFromMenu() {
        toggleRelayMode()
    }

    /// 開關接力模式。
    ///
    /// 關閉時不只是停止廣播，還會斷開已連線的 iPhone 並清掉已鎖定的輸入框。
    /// 少了後兩步，「關閉」就只是不再接受新連線，既有連線仍能繼續貼字。
    private func setRelayMode(enabled: Bool, playSound: Bool = true) {
        guard isRelayModeEnabled != enabled else { return }
        isRelayModeEnabled = enabled

        if enabled {
            remoteBridge.start()
        } else {
            remoteTargetController.clearTarget()
            remoteBridge.stop()
        }
        updateRelayMenu()
        if playSound { NSSound(named: enabled ? "Glass" : "Pop")?.play() }
    }

    private func relayMenuTitle() -> String {
        guard let relayHotKey else { return "iPhone 接力模式" }
        return "iPhone 接力模式（\(shortcutDisplayName(relayHotKey))）"
    }

    private func updateRelayMenu() {
        relayMenuItem.state = isRelayModeEnabled ? .on : .off
        relayMenuItem.title = relayMenuTitle()
        if !isRelayModeEnabled {
            remoteConnectionMenuItem.title = "iPhone 遠端：已停用"
            remoteTargetMenuItem.title = "尚未鎖定輸入框"
        }
        resetStatus()
    }

    private func loadRelaySettings() {
        let defaults = UserDefaults.standard
        preferredInputDeviceUID = defaults.string(forKey: preferredInputDeviceUIDDefaultsKey)
        allowContinuityMicrophone = defaults.bool(forKey: allowContinuityMicrophoneDefaultsKey)

        // 鍵值不存在代表從未設定過，給預設快捷鍵；modifiers 為 0 則是使用者按過
        // 「清除」的明確標記（快捷鍵至少要有一個修飾鍵，0 不可能是有效值）。
        // 少了這個區分，清除過的快捷鍵下次啟動就會自己跑回來。
        guard defaults.object(forKey: relayHotKeyCodeDefaultsKey) != nil,
              defaults.object(forKey: relayHotKeyModifiersDefaultsKey) != nil else {
            relayHotKey = defaultRelayHotKey
            return
        }
        let modifiers = UInt32(defaults.integer(forKey: relayHotKeyModifiersDefaultsKey))
        relayHotKey = modifiers == 0 ? nil : HotKeyShortcut(
            keyCode: UInt32(defaults.integer(forKey: relayHotKeyCodeDefaultsKey)),
            modifiers: modifiers
        )
    }

    @objc private func showRelaySettingsDialog() {
        NSApp.activate(ignoringOtherApps: true)
        let view = RelaySettingsView(
            relayShortcut: relayHotKey,
            preferredDeviceUID: preferredInputDeviceUID,
            allowContinuityMicrophone: allowContinuityMicrophone,
            devices: AudioInputDevices.current()
        )
        let alert = NSAlert()
        alert.messageText = "iPhone 接力與麥克風設定"
        alert.alertStyle = .informational
        alert.accessoryView = view
        alert.addButton(withTitle: "儲存")
        alert.addButton(withTitle: "取消")

        guard alert.runModal() == .alertFirstButtonReturn else {
            NSApp.hide(nil)
            return
        }

        let defaults = UserDefaults.standard
        preferredInputDeviceUID = view.preferredDeviceUID
        allowContinuityMicrophone = view.allowContinuityMicrophone
        if let preferredInputDeviceUID {
            defaults.set(preferredInputDeviceUID, forKey: preferredInputDeviceUIDDefaultsKey)
        } else {
            defaults.removeObject(forKey: preferredInputDeviceUIDDefaultsKey)
        }
        defaults.set(allowContinuityMicrophone, forKey: allowContinuityMicrophoneDefaultsKey)

        relayHotKey = view.relayShortcut
        saveRelayHotKey()
        if registerRelayHotKey() != noErr {
            relayHotKey = nil
            registerRelayHotKey()
            saveRelayHotKey()
            showError("接力模式快捷鍵無法註冊，可能已被其他程式占用。仍可從選單列切換接力模式。")
        }
        updateRelayMenu()
        NSApp.hide(nil)
    }

    private func saveRelayHotKey() {
        let defaults = UserDefaults.standard
        defaults.set(Int(relayHotKey?.keyCode ?? 0), forKey: relayHotKeyCodeDefaultsKey)
        defaults.set(Int(relayHotKey?.modifiers ?? 0), forKey: relayHotKeyModifiersDefaultsKey)
    }

    /// 註冊接力模式快捷鍵。沒有設定時只是解除註冊，不視為錯誤。
    @discardableResult
    private func registerRelayHotKey() -> OSStatus {
        if let relayHotKeyRef {
            UnregisterEventHotKey(relayHotKeyRef)
            self.relayHotKeyRef = nil
        }
        guard let relayHotKey else { return noErr }
        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: relayHotKeyID)
        return RegisterEventHotKey(
            relayHotKey.keyCode,
            relayHotKey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &relayHotKeyRef
        )
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

        // 接力快捷鍵註冊失敗不是致命問題（選單列仍可切換），但也不能讓選單顯示一個
        // 按下去沒反應的組合鍵，所以直接視為未設定，讓使用者自己去改一個沒衝突的。
        // 選單標題在 configureStatusItem() 就已經寫好了，這裡必須重新整理一次。
        if registerRelayHotKey() != noErr {
            relayHotKey = nil
            registerRelayHotKey()
            updateRelayMenu()
        }

        if installStatus != noErr || registerStatus != noErr {
            showError("無法註冊快捷鍵 \(shortcutDisplayName(currentHotKey))。可能已被其他程式使用。")
        }
    }

    private func registerCurrentHotKey() -> OSStatus {
        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: primaryHotKeyID)
        let status = RegisterEventHotKey(
            currentHotKey.keyCode,
            currentHotKey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        registerAlternateHotKey()
        return status
    }

    /// 註冊第二快捷鍵。沒有設定時只是解除註冊，不視為錯誤。
    @discardableResult
    private func registerAlternateHotKey() -> OSStatus {
        if let alternateHotKeyRef {
            UnregisterEventHotKey(alternateHotKeyRef)
            self.alternateHotKeyRef = nil
        }
        guard let alternateHotKey else { return noErr }
        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: alternateHotKeyID)
        return RegisterEventHotKey(
            alternateHotKey.keyCode,
            alternateHotKey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &alternateHotKeyRef
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

    /// 預設為純逐字，與 v1.1.0 以前完全不做後處理的行為一致。
    /// 0.1 版的 `lightCleanup` 會被讀成 `standard`，不讓既有設定被靜默重設。
    private func loadTextOutputMode() -> TextOutputMode {
        TextOutputMode.fromStoredValue(
            UserDefaults.standard.string(forKey: textOutputModeDefaultsKey)
        ) ?? .verbatim
    }

    private func setTextOutputMode(_ mode: TextOutputMode) {
        textOutputMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: textOutputModeDefaultsKey)
        updateTextOutputModeMenu()
    }

    private func updateTextOutputModeMenu() {
        for (mode, item) in modeMenuItems {
            item.state = mode == textOutputMode ? .on : .off
        }
    }

    @objc private func selectOutputMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = TextOutputMode(rawValue: raw) else { return }
        setTextOutputMode(mode)
    }

    // MARK: - 語言設定

    private func loadLanguageSettings() -> LanguageSettings {
        let defaults = UserDefaults.standard
        guard let primaryRaw = defaults.string(forKey: primaryLanguageDefaultsKey),
              let primary = LanguageOption(rawValue: primaryRaw) else {
            return .default
        }
        let additional = (defaults.stringArray(forKey: additionalLanguagesDefaultsKey) ?? [])
            .compactMap(LanguageOption.init(rawValue:))
        let retry = defaults.object(forKey: automaticLanguageRetryDefaultsKey) as? Bool ?? true
        return LanguageSettings(primary: primary, additional: additional, automaticRetryEnabled: retry)
    }

    private func saveLanguageSettings(_ settings: LanguageSettings) {
        let defaults = UserDefaults.standard
        defaults.set(settings.primary.rawValue, forKey: primaryLanguageDefaultsKey)
        defaults.set(settings.additional.map(\.rawValue), forKey: additionalLanguagesDefaultsKey)
        defaults.set(settings.automaticRetryEnabled, forKey: automaticLanguageRetryDefaultsKey)
        languageSettings = settings
    }

    @objc private func showLanguageDialog() {
        NSApp.activate(ignoringOtherApps: true)
        let view = LanguageSettingsView(settings: languageSettings)
        let alert = NSAlert()
        alert.messageText = "語言設定"
        alert.informativeText = "最多三種語言：一個主要語言，加上最多兩個允許混用的語言。"
        alert.alertStyle = .informational
        alert.accessoryView = view
        alert.addButton(withTitle: "儲存")
        alert.addButton(withTitle: "取消")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        saveLanguageSettings(view.currentSettings())
        NSApp.hide(nil)
    }

    // MARK: - 文字與錄音設定

    private func loadTextSettings() {
        let defaults = UserDefaults.standard
        convertChineseNumerals = defaults.bool(forKey: convertChineseNumeralsDefaultsKey)
        silenceAutoStopSeconds = defaults.integer(forKey: silenceAutoStopSecondsDefaultsKey)
        alternateOutputMode = TextOutputMode.fromStoredValue(
            defaults.string(forKey: alternateOutputModeDefaultsKey)
        ) ?? .concise
        guard defaults.object(forKey: alternateHotKeyCodeDefaultsKey) != nil,
              defaults.object(forKey: alternateHotKeyModifiersDefaultsKey) != nil else {
            alternateHotKey = nil
            return
        }
        alternateHotKey = HotKeyShortcut(
            keyCode: UInt32(defaults.integer(forKey: alternateHotKeyCodeDefaultsKey)),
            modifiers: UInt32(defaults.integer(forKey: alternateHotKeyModifiersDefaultsKey))
        )
    }

    @objc private func showTextSettingsDialog() {
        NSApp.activate(ignoringOtherApps: true)
        let view = TextSettingsView(
            convertNumerals: convertChineseNumerals,
            silenceSeconds: silenceAutoStopSeconds,
            alternateShortcut: alternateHotKey,
            alternateMode: alternateOutputMode
        )
        let alert = NSAlert()
        alert.messageText = "文字與錄音設定"
        alert.alertStyle = .informational
        alert.accessoryView = view
        alert.addButton(withTitle: "儲存")
        alert.addButton(withTitle: "取消")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let defaults = UserDefaults.standard
        convertChineseNumerals = view.convertNumerals
        silenceAutoStopSeconds = view.silenceSeconds
        alternateOutputMode = view.alternateMode
        defaults.set(convertChineseNumerals, forKey: convertChineseNumeralsDefaultsKey)
        defaults.set(silenceAutoStopSeconds, forKey: silenceAutoStopSecondsDefaultsKey)
        defaults.set(alternateOutputMode.rawValue, forKey: alternateOutputModeDefaultsKey)

        if let shortcut = view.alternateShortcut {
            alternateHotKey = shortcut
            defaults.set(Int(shortcut.keyCode), forKey: alternateHotKeyCodeDefaultsKey)
            defaults.set(Int(shortcut.modifiers), forKey: alternateHotKeyModifiersDefaultsKey)
        } else {
            alternateHotKey = nil
            defaults.removeObject(forKey: alternateHotKeyCodeDefaultsKey)
            defaults.removeObject(forKey: alternateHotKeyModifiersDefaultsKey)
        }
        if registerAlternateHotKey() != noErr {
            showError("第二快捷鍵無法註冊，可能已被其他程式占用。")
        }
        NSApp.hide(nil)
    }

    private func toggleMenuTitle() -> String {
        "開始／停止錄音（\(shortcutDisplayName(currentHotKey))）"
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
            showError("快捷鍵 \(shortcutDisplayName(newHotKey)) 無法使用，可能已被其他程式占用。原設定 \(shortcutDisplayName(previous)) 已保留。")
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

    func toggleRecording(useAlternateMode: Bool = false) {
        guard !isUploading else {
            NSSound.beep()
            return
        }

        if micRecorder.isRecording {
            stopRecording()
        } else if micRecorder.isBusy {
            // 錄音裝置還在啟動中（AVCaptureSession 要 100–300ms）。這時再按一次
            // 快捷鍵不能當成「停止」，否則會停掉一段還沒開始的錄音。
            NSSound.beep()
        } else {
            // 第二快捷鍵只影響這一次錄音，不改變儲存的偏好。
            activeOutputMode = useAlternateMode ? alternateOutputMode : textOutputMode
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

        // 明確挑一個裝置，而不是讓系統決定。macOS 會在 iPhone 靠近時把預設輸入
        // 切到連續互通麥克風，那時候錄到的是一段靜音，手機還會被隔空叫醒。
        guard let device = AudioInputDevices.selected(
            preferredUID: preferredInputDeviceUID,
            allowContinuityCapture: allowContinuityMicrophone
        ) else {
            showError(
                "找不到可用的麥克風。目前唯一的輸入裝置是 iPhone 的連續互通麥克風，"
                + "用它錄音通常只會收到靜音。請接上其他麥克風，或在「iPhone 接力與麥克風設定…」中允許使用它。"
            )
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FreeVoiceType-\(UUID().uuidString).m4a")
        recordingURL = url
        // 開始是非同步的：狀態列圖示與提示音都留到 onRecordingStarted 才更新。
        micRecorder.start(deviceUID: device.uid, url: url)
    }

    /// 錄音期間定時檢查兩件事：是否超過最長錄音時間，以及是否已靜音夠久。
    private func startMetering() {
        recordingStartedAt = Date()
        lastLoudAt = Date()
        meteringTimer?.invalidate()
        meteringTimer = Timer.scheduledTimer(withTimeInterval: meteringInterval, repeats: true) { [weak self] _ in
            self?.checkRecordingLimits()
        }
    }

    private func stopMetering() {
        meteringTimer?.invalidate()
        meteringTimer = nil
        recordingStartedAt = nil
        lastLoudAt = nil
    }

    private func checkRecordingLimits() {
        guard micRecorder.isRecording else { return }

        // 最長錄音保護：永遠啟用，防止忘記按第二次快捷鍵而一直錄下去。
        if let startedAt = recordingStartedAt, Date().timeIntervalSince(startedAt) >= maximumRecordingDuration {
            stopRecording()
            return
        }

        // 靜音自動停止：預設關閉，因為思考中的停頓會被誤判成講完了。
        // `averagePowerLevel` 與 AVAudioRecorder 的 `averagePower` 同樣是 dBFS，
        // 所以門檻值與這段判斷都沿用改版前的行為。
        guard silenceAutoStopSeconds > 0 else { return }
        if micRecorder.averagePowerLevel > silenceThresholdDecibels {
            lastLoudAt = Date()
            return
        }
        if let lastLoudAt, Date().timeIntervalSince(lastLoudAt) >= TimeInterval(silenceAutoStopSeconds) {
            stopRecording()
        }
    }

    /// 按下停止。
    ///
    /// 這裡刻意不做上傳。`AVCaptureAudioFileOutput` 在 `stopRecording()` 之後還會
    /// 在背景把剩下的資料寫完，此刻的檔案是不完整的，直接上傳會送出半個音檔而讓
    /// Groq 回報「沒有辨識到語音」。實際的上傳在 `handleRecordingFinished(url:error:)`。
    private func stopRecording() {
        stopMetering()
        statusItem.button?.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "正在辨識")
        statusItem.button?.contentTintColor = .systemOrange
        NSSound(named: "Pop")?.play()
        micRecorder.stop()
    }

    /// 音檔已完整寫入磁碟，這時候才能上傳。
    private func handleRecordingFinished(url: URL, error: Error?) {
        // 錄音也可能不是由 stopRecording() 結束的（裝置被拔掉、系統中斷等），
        // 那條路徑不會經過 stopMetering()，計時器會一直空轉下去。
        stopMetering()
        recordingURL = nil

        if let error {
            try? FileManager.default.removeItem(at: url)
            resetStatus()
            showError("錄音未能完成：\(error.localizedDescription)")
            return
        }

        guard let apiKey = readAPIKey() else {
            try? FileManager.default.removeItem(at: url)
            resetStatus()
            return
        }

        activeUploadURL = url
        isUploading = true
        extraRequestCount = 0

        transcribe(url: url, apiKey: apiKey) { result in
            DispatchQueue.main.async {
                self.handleTranscription(result, url: url, apiKey: apiKey)
            }
        }
    }

    /// 轉錄結果的統一處理入口。
    ///
    /// 順序是「語言檢查 → 後處理 → 貼上」。錄音在成功貼上前一律不刪除，
    /// 讓 API 失敗、網路中斷或語言誤判時都不必重講。
    private func handleTranscription(_ result: Result<String, Error>, url: URL, apiKey: String) {
        isUploading = false
        activeUploadURL = nil
        resetStatus()

        switch result {
        case .failure(let error):
            retainRecording(url, message: "\(error.localizedDescription)\n\n錄音已保留，可以直接重新辨識，不用重講。")
        case .success(let text):
            let transcript = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !transcript.isEmpty else {
                discardRecording(url)
                showError("沒有辨識到語音，請再試一次。")
                return
            }
            guard !LanguagePolicy.shouldIntercept(transcript, settings: languageSettings) else {
                retryWithChineseHint(url: url, apiKey: apiKey)
                return
            }
            deliver(transcript, url: url)
        }
    }

    /// 未允許語言：用同一段音檔重試一次，並指定中文。不切換金鑰。
    private func retryWithChineseHint(url: URL, apiKey: String) {
        guard extraRequestCount < maximumExtraRequestsPerRecording else {
            retainRecording(url, message: "這段語音未能正確辨識。錄音已保留，你可以重新辨識或再次錄音。")
            return
        }
        extraRequestCount += 1
        isUploading = true
        activeUploadURL = url
        statusItem.button?.image = NSImage(
            systemSymbolName: "arrow.clockwise.circle",
            accessibilityDescription: "重新辨識"
        )
        statusItem.button?.contentTintColor = .systemOrange

        transcribe(url: url, apiKey: apiKey, reinforce: true) { result in
            DispatchQueue.main.async {
                self.isUploading = false
                self.activeUploadURL = nil
                self.resetStatus()

                let retried = (try? result.get())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !retried.isEmpty, !LanguagePolicy.shouldIntercept(retried, settings: self.languageSettings) else {
                    self.retainRecording(
                        url,
                        message: "這段語音未能正確辨識。錄音已保留，你可以重新辨識或再次錄音。"
                    )
                    return
                }
                self.deliver(retried, url: url)
            }
        }
    }

    /// 套用後處理並貼上。後處理失敗時降級為原始轉錄，不讓整次語音輸入失敗。
    private func deliver(_ transcript: String, url: URL) {
        let processed = TextPostProcessor.process(
            transcript,
            mode: activeOutputMode,
            applyChineseRules: languageSettings.primary.usesChineseTextRules,
            convertChineseNumerals: convertChineseNumerals
        )
        let cleanupSucceeded = !processed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        discardRecording(url)
        copyAndPaste(cleanupSucceeded ? processed : transcript)
        if !cleanupSucceeded {
            showError("語音已成功轉錄，但文字清理暫時未完成。目前先使用原始轉錄。")
        }
    }

    /// 保留錄音並詢問是否重新辨識。逾時或使用者捨棄後刪除。
    private func retainRecording(_ url: URL, message: String) {
        pendingRetryURL = url
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "語音辨識未完成"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "重新辨識")
        alert.addButton(withTitle: "捨棄錄音")

        guard alert.runModal() == .alertFirstButtonReturn else {
            discardRecording(url)
            return
        }
        guard let apiKey = readAPIKey() else {
            discardRecording(url)
            showAPIKeyDialog(firstRun: false)
            return
        }

        // 使用者明確要求重試，視為新的一次嘗試，重設自動重試計數。
        extraRequestCount = 0
        pendingRetryURL = nil
        activeUploadURL = url
        isUploading = true
        statusItem.button?.image = NSImage(
            systemSymbolName: "ellipsis.circle",
            accessibilityDescription: "正在辨識"
        )
        statusItem.button?.contentTintColor = .systemOrange
        transcribe(url: url, apiKey: apiKey, reinforce: true) { result in
            DispatchQueue.main.async {
                self.isUploading = false
                self.activeUploadURL = nil
                self.resetStatus()

                let retried = (try? result.get())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !retried.isEmpty else {
                    // 不再重複詢問，避免無限彈窗；錄音仍保留到逾時。
                    self.pendingRetryURL = url
                    self.scheduleRetentionCleanup(for: url)
                    self.showError("重新辨識仍未成功。錄音會再保留兩分鐘，你也可以直接重新錄音。")
                    return
                }
                self.deliver(retried, url: url)
            }
        }
    }

    private func discardRecording(_ url: URL) {
        if pendingRetryURL == url { pendingRetryURL = nil }
        try? FileManager.default.removeItem(at: url)
    }

    private func scheduleRetentionCleanup(for url: URL) {
        DispatchQueue.main.asyncAfter(deadline: .now() + recordingRetentionInterval) { [weak self] in
            guard let self, self.pendingRetryURL == url else { return }
            self.discardRecording(url)
        }
    }

    /// 介面 A 的轉錄入口，實際工作交給共用核心 `GroqTranscriptionClient`。
    ///
    /// 這裡固定用 `.plain`（`response_format=json`）：介面 A 從按快捷鍵到貼上是
    /// 延遲敏感路徑，而它不需要時間戳或把握度，沒有理由承擔 `verbose_json`
    /// 的額外回應體積。逐字稿工作台（介面 B）才會用 `.verbose`。
    private func transcribe(
        url: URL,
        apiKey: String,
        reinforce: Bool = false,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let primaryLanguage = languageSettings.primary
        let allowed = languageSettings.allowedLanguages.map(\.displayName).joined(separator: "、")
        let reinforceHint = "這段錄音的語言是\(primaryLanguage.displayName)，可能混合少量\(allowed)。請只輸出這些語言。"
        let basePrompt = primaryLanguage.transcriptionPrompt
        // 重試時加強主要語言的提示，處理第一次辨識出非預期語言的情況。
        let prompt = reinforce ? reinforceHint + basePrompt : basePrompt

        DispatchQueue.global(qos: .userInitiated).async {
            GroqTranscriptionClient.transcribe(
                audioURL: url,
                apiKey: apiKey,
                language: primaryLanguage.rawValue,
                prompt: prompt,
                format: .plain
            ) { result in
                completion(result.map(\.text))
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

        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        NSSound(named: "Glass")?.play()
    }

    /// 回到待機圖示。接力模式開啟時用不同的符號，讓使用者一眼看得出手機現在連得上來。
    private func resetStatus() {
        let description = isRelayModeEnabled ? "AI 語音輸入（iPhone 接力已開啟）" : "AI 語音輸入"
        let symbol = isRelayModeEnabled ? "mic.badge.plus" : "mic"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
            ?? NSImage(systemSymbolName: "mic", accessibilityDescription: description)
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
                    success.informativeText = "現在可在任何文字輸入位置按 \(shortcutDisplayName(currentHotKey)) 開始錄音，再按一次停止並貼上辨識文字。"
                    success.addButton(withTitle: "開始使用")
                    success.runModal()
                }
            } catch {
                showError("無法把金鑰存入鑰匙圈：\(error.localizedDescription)")
            }
        }
    }

    /// 讀取金鑰，成功後在本次執行期間快取。
    ///
    /// 這個 App 使用 ad-hoc 簽章，每次重新建置的程式碼身分（CDHash）都不同，
    /// 鑰匙圈會把它當成另一個程式而要求使用者授權。原本每段錄音會讀兩次
    /// （開始錄音檢查一次、上傳前再讀一次），授權提示因此出現得很頻繁。
    /// 快取後每次啟動最多只會問一次。
    ///
    /// 只快取成功的結果：讀取失敗或使用者取消授權時不寫入快取，下次會重新嘗試。
    /// 快取僅存在記憶體，不寫入任何檔案；金鑰更新時由 `saveAPIKey` 覆蓋。
    private func readAPIKey() -> String? {
        if let cachedAPIKey { return cachedAPIKey }

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
        cachedAPIKey = key
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
            guard addStatus == errSecSuccess else {
                cachedAPIKey = nil
                throw VoiceTypeError.message("Keychain 錯誤 \(addStatus)")
            }
        } else if updateStatus != errSecSuccess {
            cachedAPIKey = nil
            throw VoiceTypeError.message("Keychain 錯誤 \(updateStatus)")
        }
        // 使用者更換金鑰後，快取必須立刻跟上，否則會繼續用舊金鑰直到重啟。
        cachedAPIKey = key
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

// `VoiceTypeError` 已移到 GroqTranscriptionClient.swift，讓共用核心能單獨編譯與測試。

let app = NSApplication.shared
let delegate = VoiceTypeController()
app.delegate = delegate
app.run()
