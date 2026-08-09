import CoreAudio
import Foundation

/// 列舉這台 Mac 目前可用的錄音輸入裝置。
///
/// 這是 `AudioInputPolicy` 的 I/O 薄層：只負責把 CoreAudio 的狀態讀成純資料，
/// 決策一律交給 policy，決策才能單獨編譯測試。
///
/// 之所以要走 CoreAudio 而不是只用 AVFoundation：`AVCaptureDevice` 認不出
/// 連續互通裝置——iPhone 的麥克風在它眼裡就是一個普通的 `.microphone`，
/// 只有 CoreAudio 的 `kAudioDevicePropertyTransportType` 分得出來。
enum AudioInputDevices {
    static func current() -> [AudioInputDevice] {
        let defaultUID = defaultInputDeviceUID()
        return allDeviceIDs().compactMap { id in
            // 只保留真的有輸入聲道的裝置，排除喇叭之類的純輸出裝置。
            guard inputChannelCount(id) > 0,
                  let uid = stringProperty(kAudioDevicePropertyDeviceUID, from: id) else { return nil }
            return AudioInputDevice(
                uid: uid,
                name: stringProperty(kAudioObjectPropertyName, from: id) ?? uid,
                transportType: transportType(id),
                isSystemDefault: uid == defaultUID
            )
        }
    }

    /// 依目前設定選出這次錄音要用的裝置。回傳 nil 表示沒有可用的輸入裝置。
    static func selected(preferredUID: String?, allowContinuityCapture: Bool) -> AudioInputDevice? {
        AudioInputPolicy.selectDevice(
            from: current(),
            preferredUID: preferredUID,
            allowContinuityCapture: allowContinuityCapture
        )
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return [] }

        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr else { return [] }
        return ids
    }

    private static func defaultInputDeviceUID() -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        ) == noErr, deviceID != AudioDeviceID(kAudioObjectUnknown) else { return nil }
        return stringProperty(kAudioDevicePropertyDeviceUID, from: deviceID)
    }

    /// CoreAudio 回傳的 CFString 是 +1 retain，必須用 `Unmanaged` 承接再
    /// `takeRetainedValue()`。直接宣告 `var value: CFString` 讓 CoreAudio 覆寫，
    /// 會讓 Swift 把一個物件參考當成純記憶體處理而洩漏或當掉。
    private static func stringProperty(
        _ selector: AudioObjectPropertySelector,
        from id: AudioDeviceID
    ) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(id, &address, 0, nil, &size, UnsafeMutableRawPointer($0))
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func transportType(_ id: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport) == noErr else { return 0 }
        return transport
    }

    private static func inputChannelCount(_ id: AudioDeviceID) -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }

        let buffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, buffer) == noErr else { return 0 }

        let list = UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }
}
