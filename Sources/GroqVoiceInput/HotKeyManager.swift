import Foundation
import Carbon

struct HotKeyShortcut: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
}

let defaultHotKey = HotKeyShortcut(
    keyCode: UInt32(kVK_UpArrow),
    modifiers: UInt32(optionKey)
)

/// 切換 iPhone 接力模式的預設快捷鍵。
///
/// 沿用主快捷鍵的 ↑ 好記，但用 ⌃⌥ 而不是 ⌥⇧：`⌥⇧↑` 是 macOS 標準的「向上延伸
/// 選取」，被 `RegisterEventHotKey` 全域攔截後，每個 App 的文字選取都會壞掉。
let defaultRelayHotKey = HotKeyShortcut(
    keyCode: UInt32(kVK_UpArrow),
    modifiers: UInt32(controlKey) | UInt32(optionKey)
)

/// Opens the clipboard picker without replacing the standard paste shortcut.
let defaultClipboardHotKey = HotKeyShortcut(
    keyCode: UInt32(kVK_ANSI_V),
    modifiers: UInt32(controlKey) | UInt32(optionKey)
)

func shortcutDisplayName(_ shortcut: HotKeyShortcut) -> String {
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

private let hotKeySignature: OSType = 0x56545950 // VTYP

private let managedHotKeyHandler: EventHandlerUPP = { _, event, userData in
    guard let userData else { return noErr }
    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
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
    let pressedID = status == noErr ? identifier.id : HotKeyManager.primaryID
    DispatchQueue.main.async { [weak manager] in
        manager?.onPress?(pressedID)
    }
    return noErr
}

/// Owns Carbon registrations. The controller retains shortcut conflict/recovery policy.
/// Install, register and tear down on the main thread, alongside the AppKit lifecycle.
// 系統架構設計理由：
// 採用 macOS Carbon 的 RegisterEventHotKey API，而非 NSEvent 全域事件監聽（Global Event Monitor）。
// 為什麼這樣設計：
// 1. Carbon RegisterEventHotKey 為系統級熱鍵註冊，不需要「輔助使用（Accessibility）」監聽權限即可觸發；
//    這使初次安裝的使用者按下快捷鍵時，能立刻被 App 捕捉並順暢彈出權限導引視窗。
// 2. 只有在需要向目標視窗合成 ⌘V 貼上時才真正需要 Accessibility 權限。
final class HotKeyManager {
    static let primaryID: UInt32 = 1
    static let alternateID: UInt32 = 2
    static let relayID: UInt32 = 3
    static let clipboardID: UInt32 = 4

    fileprivate var onPress: ((UInt32) -> Void)?
    private var eventHandlerRef: EventHandlerRef?
    private var registrations: [UInt32: EventHotKeyRef] = [:]

    @discardableResult
    func installHandler(onPress: @escaping (UInt32) -> Void) -> OSStatus {
        self.onPress = onPress
        guard eventHandlerRef == nil else { return noErr }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            managedHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        if status != noErr { self.onPress = nil }
        return status
    }

    /// nil explicitly clears this registration; a failed replacement stays unregistered.
    // 註冊安全約定：
    // 每次註冊新快捷鍵時，若該 id 已有舊註冊，必須先透過 UnregisterEventHotKey 卸載，避免 Carbon 資源洩漏。
    // 若傳入 nil 則代表明確清除該快捷鍵；若新註冊失敗（如已被其他 App 占用），該 id 保持未註冊狀態並傳回錯誤碼。
    @discardableResult
    func register(shortcut: HotKeyShortcut?, id: UInt32) -> OSStatus {
        if let previous = registrations.removeValue(forKey: id) {
            UnregisterEventHotKey(previous)
        }
        guard let shortcut else { return noErr }
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            EventHotKeyID(signature: hotKeySignature, id: id),
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if status == noErr, let reference {
            registrations[id] = reference
        }
        return status
    }

    /// Also removes the event handler and callback, so queued callbacks cannot fire later.
    func unregisterAll() {
        for reference in registrations.values {
            UnregisterEventHotKey(reference)
        }
        registrations.removeAll()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
        onPress = nil
    }

    deinit {
        unregisterAll()
    }
}
