// Short, no-recording probe of macOS system audio capture. Reports only peak
// level and buffer count; no audio samples or application names are saved.
import CoreAudio
import Foundation

func check(_ status: OSStatus, _ label: String) throws {
    guard status == noErr else { throw NSError(domain: label, code: Int(status)) }
}

let description = CATapDescription(monoGlobalTapButExcludeProcesses: [])
description.name = "Neko Global Audio Probe"
description.isPrivate = true
var tap = AudioObjectID(kAudioObjectUnknown)
try check(AudioHardwareCreateProcessTap(description, &tap), "create process tap")
defer { AudioHardwareDestroyProcessTap(tap) }

let aggregateDescription: [String: Any] = [
    kAudioAggregateDeviceNameKey as String: "Neko Global Audio Probe",
    kAudioAggregateDeviceUIDKey as String: UUID().uuidString,
    kAudioAggregateDeviceIsPrivateKey as String: true,
    kAudioAggregateDeviceTapAutoStartKey as String: true,
    kAudioAggregateDeviceTapListKey as String: [[
        kAudioSubTapUIDKey as String: description.uuid.uuidString,
        kAudioSubTapDriftCompensationKey as String: true,
    ]],
]
var aggregate = AudioObjectID(kAudioObjectUnknown)
try check(AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregate),
          "create aggregate device")
defer { AudioHardwareDestroyAggregateDevice(aggregate) }

var alive = UInt32(0)
var aliveAddress = AudioObjectPropertyAddress(
    mSelector: kAudioDevicePropertyDeviceIsAlive,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain)
for _ in 0..<30 {
    var size = UInt32(MemoryLayout<UInt32>.size)
    let status = AudioObjectGetPropertyData(aggregate, &aliveAddress, 0, nil, &size, &alive)
    if status == noErr && alive != 0 { break }
    Thread.sleep(forTimeInterval: 0.1)
}
guard alive != 0 else { throw NSError(domain: "aggregate not alive", code: 1) }

var format = AudioStreamBasicDescription()
var formatAddress = AudioObjectPropertyAddress(
    mSelector: kAudioDevicePropertyStreamFormat,
    mScope: kAudioObjectPropertyScopeInput,
    mElement: kAudioObjectPropertyElementMain)
var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
try check(AudioObjectGetPropertyData(aggregate, &formatAddress, 0, nil,
                                     &formatSize, &format), "read stream format")
guard format.mFormatID == kAudioFormatLinearPCM,
      (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0,
      format.mBitsPerChannel == 32 else {
    throw NSError(domain: "unexpected stream format", code: 1)
}

let lock = NSLock()
var callbackCount = 0
var peak: Float = 0
var ioProc: AudioDeviceIOProcID?
let queue = DispatchQueue(label: "NekoGlobalAudioProbe.io")
try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, aggregate, queue) {
    _, inputData, _, _, _ in
    let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
    var localPeak: Float = 0
    for buffer in buffers {
        guard let data = buffer.mData else { continue }
        let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
        let samples = data.assumingMemoryBound(to: Float.self)
        for index in 0..<count { localPeak = max(localPeak, abs(samples[index])) }
    }
    lock.lock()
    callbackCount += 1
    peak = max(peak, localPeak)
    lock.unlock()
}, "create IO proc")
guard let ioProc else { throw NSError(domain: "missing IO proc", code: 1) }
defer { AudioDeviceDestroyIOProcID(aggregate, ioProc) }
try check(AudioDeviceStart(aggregate, ioProc), "start tap")
defer { AudioDeviceStop(aggregate, ioProc) }

print("READY sample_rate=\(Int(format.mSampleRate)) channels=\(format.mChannelsPerFrame)")
fflush(stdout)
RunLoop.current.run(until: Date(timeIntervalSinceNow: 10))
lock.lock()
print("RESULT callbacks=\(callbackCount) peak=\(peak)")
lock.unlock()
