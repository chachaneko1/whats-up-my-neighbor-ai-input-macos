import Foundation

/// 這些測試守的是一件事：macOS 把系統預設輸入切到 iPhone 時，錄音不可以跟著
/// 跑到 iPhone 上；但除此之外的任何裝置選擇都必須維持原本行為。
@main
enum AudioInputPolicyTests {
    // 實機上量到的真實值，避免測試用假的 transport type 自我安慰。
    static let builtIn = AudioInputPolicy.builtIn
    static let ccwd = AudioInputPolicy.continuityCaptureWired
    static let ccwl = AudioInputPolicy.continuityCaptureWireless
    static let ccap = AudioInputPolicy.continuityCaptureLegacy
    static let virt: UInt32 = 0x7669_7274 // 'virt'
    static let usb: UInt32 = 0x7573_6220 // 'usb '
    static let bluetooth: UInt32 = 0x626C_7565 // 'blue'

    static func device(
        _ uid: String,
        _ transport: UInt32,
        isDefault: Bool = false
    ) -> AudioInputDevice {
        AudioInputDevice(uid: uid, name: uid, transportType: transport, isSystemDefault: isDefault)
    }

    static func select(
        _ devices: [AudioInputDevice],
        preferredUID: String? = nil,
        allowContinuityCapture: Bool = false
    ) -> String? {
        AudioInputPolicy.selectDevice(
            from: devices,
            preferredUID: preferredUID,
            allowContinuityCapture: allowContinuityCapture
        )?.uid
    }

    static func main() {
        testTransportConstantsMatchRealHardware()
        testContinuityDetection()
        testContinuityDefaultFallsBackToBuiltIn()
        testNonContinuityDefaultIsLeftAlone()
        testAllowContinuityOptOut()
        testPreferredDevice()
        testDegenerateDeviceLists()
        print("AudioInputPolicyTests passed")
    }

    /// 常數若打錯，整個防護會靜默失效——偵測不到 iPhone，行為就跟沒改一樣。
    /// 這裡用實機 `kAudioDevicePropertyTransportType` 量到的四字碼反推驗證。
    static func testTransportConstantsMatchRealHardware() {
        func fourCC(_ value: UInt32) -> String {
            let bytes = [
                UInt8((value >> 24) & 0xFF),
                UInt8((value >> 16) & 0xFF),
                UInt8((value >> 8) & 0xFF),
                UInt8(value & 0xFF)
            ]
            return String(bytes: bytes, encoding: .ascii) ?? ""
        }
        precondition(fourCC(ccwd) == "ccwd", "連續互通（有線）的 transport type 不是 ccwd")
        precondition(fourCC(ccwl) == "ccwl", "連續互通（無線）的 transport type 不是 ccwl")
        precondition(fourCC(ccap) == "ccap", "舊版連續互通的 transport type 不是 ccap")
        precondition(fourCC(builtIn) == "bltn", "內建麥克風的 transport type 不是 bltn")
    }

    static func testContinuityDetection() {
        precondition(AudioInputPolicy.isContinuityCapture(ccwd))
        precondition(AudioInputPolicy.isContinuityCapture(ccwl))
        precondition(AudioInputPolicy.isContinuityCapture(ccap))
        precondition(!AudioInputPolicy.isContinuityCapture(builtIn))
        precondition(!AudioInputPolicy.isContinuityCapture(usb))
        precondition(!AudioInputPolicy.isContinuityCapture(bluetooth))
        precondition(!AudioInputPolicy.isContinuityCapture(virt))
    }

    /// 這是整個修正的核心情境：使用者回報的「收不到音」。
    static func testContinuityDefaultFallsBackToBuiltIn() {
        // 有線連續互通（實機觀察到的 ccwd）。
        let wired = [
            device("BuiltInMicrophoneDevice", builtIn),
            device("F494DEED-E8C5-4DA4-9B80-B72D00000003", ccwd, isDefault: true)
        ]
        precondition(select(wired) == "BuiltInMicrophoneDevice", "系統預設是 iPhone（有線）時必須退回內建麥克風")

        // 無線連續互通：手機放在別的房間也會發生。
        let wireless = [
            device("BuiltInMicrophoneDevice", builtIn),
            device("iphone-wireless", ccwl, isDefault: true)
        ]
        precondition(select(wireless) == "BuiltInMicrophoneDevice", "系統預設是 iPhone（無線）時必須退回內建麥克風")

        // 舊系統回報的 ccap。
        let legacy = [
            device("BuiltInMicrophoneDevice", builtIn),
            device("iphone-legacy", ccap, isDefault: true)
        ]
        precondition(select(legacy) == "BuiltInMicrophoneDevice", "舊版連續互通值也必須退回內建麥克風")
    }

    /// 反向保護：這次修正不可以動到任何正常的 Mac 端輸入裝置。
    static func testNonContinuityDefaultIsLeftAlone() {
        let builtInDefault = [
            device("BuiltInMicrophoneDevice", builtIn, isDefault: true),
            device("iphone", ccwd)
        ]
        precondition(select(builtInDefault) == "BuiltInMicrophoneDevice")

        // AirPods 情境：藍牙裝置是使用者刻意選的，不能被強制切回內建。
        let airPods = [
            device("BuiltInMicrophoneDevice", builtIn),
            device("AirPods-Pro", bluetooth, isDefault: true),
            device("iphone", ccwd)
        ]
        precondition(select(airPods) == "AirPods-Pro", "AirPods 不可以被誤判成 iPhone 而被切走")

        // USB 麥克風同理。
        let usbMic = [
            device("BuiltInMicrophoneDevice", builtIn),
            device("Yeti", usb, isDefault: true)
        ]
        precondition(select(usbMic) == "Yeti", "USB 麥克風必須維持既有行為")

        // 虛擬裝置（BlackHole／Teams）也是使用者刻意選的，不介入。
        let virtualDevice = [
            device("BuiltInMicrophoneDevice", builtIn),
            device("BlackHole2ch_UID", virt, isDefault: true)
        ]
        precondition(select(virtualDevice) == "BlackHole2ch_UID")
    }

    /// 使用者明確勾選「允許使用 iPhone 連續互通麥克風」時，完全不介入。
    static func testAllowContinuityOptOut() {
        let devices = [
            device("BuiltInMicrophoneDevice", builtIn),
            device("iphone", ccwd, isDefault: true)
        ]
        precondition(
            select(devices, allowContinuityCapture: true) == "iphone",
            "明確允許時必須尊重系統預設"
        )
        precondition(
            select(devices, allowContinuityCapture: false) == "BuiltInMicrophoneDevice",
            "未允許時必須退回內建麥克風"
        )
    }

    static func testPreferredDevice() {
        let devices = [
            device("BuiltInMicrophoneDevice", builtIn, isDefault: true),
            device("Yeti", usb),
            device("iphone", ccwd)
        ]
        precondition(select(devices, preferredUID: "Yeti") == "Yeti", "指定的固定裝置必須優先")

        // 拔掉 USB 麥克風後不可以完全不能錄音，要自動退回自動規則。
        let unplugged = [
            device("BuiltInMicrophoneDevice", builtIn, isDefault: true),
            device("iphone", ccwd)
        ]
        precondition(
            select(unplugged, preferredUID: "Yeti") == "BuiltInMicrophoneDevice",
            "指定裝置被拔除時必須退回自動規則"
        )

        // 指定裝置不存在，且系統預設剛好被切到 iPhone：仍要退回內建。
        let unpluggedWithContinuityDefault = [
            device("BuiltInMicrophoneDevice", builtIn),
            device("iphone", ccwd, isDefault: true)
        ]
        precondition(
            select(unpluggedWithContinuityDefault, preferredUID: "Yeti") == "BuiltInMicrophoneDevice",
            "退回自動規則時仍必須排除 iPhone"
        )
    }

    static func testDegenerateDeviceLists() {
        // 沒有內建麥克風的機型（例如接外接螢幕的 Mac mini）。
        let noBuiltIn = [
            device("Display-Mic", usb),
            device("iphone", ccwd, isDefault: true)
        ]
        precondition(select(noBuiltIn) == "Display-Mic", "沒有內建麥克風時要退回其他非 iPhone 裝置")

        // 完全沒有裝置。
        precondition(select([]) == nil, "沒有任何裝置時必須回傳 nil")

        // 只剩下 iPhone 可用，而且未允許：寧可回傳 nil 讓呼叫端顯示錯誤，
        // 也不要默默錄一段靜音。
        let onlyContinuity = [device("iphone", ccwd, isDefault: true)]
        precondition(select(onlyContinuity) == nil, "只有 iPhone 可用且未允許時必須回傳 nil")
        precondition(
            select(onlyContinuity, allowContinuityCapture: true) == "iphone",
            "只有 iPhone 可用但明確允許時應該可以錄"
        )

        // 沒有任何裝置被標記為系統預設時不可以當掉。
        let noDefault = [
            device("BuiltInMicrophoneDevice", builtIn),
            device("Yeti", usb)
        ]
        precondition(select(noDefault) == "BuiltInMicrophoneDevice", "沒有系統預設時要挑得出裝置")
    }
}
