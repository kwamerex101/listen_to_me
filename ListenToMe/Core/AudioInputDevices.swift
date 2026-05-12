import CoreAudio
import Foundation

struct AudioInputDevice: Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

enum AudioInputDevices {
    static func available() -> [AudioInputDevice] {
        var size: UInt32 = 0
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size
        )
        guard status == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids
        )
        guard status == noErr else { return [] }

        return ids.compactMap { id -> AudioInputDevice? in
            guard hasInputChannels(id) else { return nil }
            guard let uid = stringProperty(id, kAudioDevicePropertyDeviceUID) else { return nil }
            let name = stringProperty(id, kAudioObjectPropertyName) ?? uid
            return AudioInputDevice(id: id, uid: uid, name: name)
        }
    }

    static func systemDefault() -> AudioDeviceID? {
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id
        )
        return status == noErr && id != 0 ? id : nil
    }

    static func resolve(uid: String) -> AudioDeviceID? {
        let cfUID = uid as CFString
        var id: AudioDeviceID = kAudioObjectUnknown
        let cfPtr = UnsafeMutablePointer<CFString>.allocate(capacity: 1)
        cfPtr.initialize(to: cfUID)
        defer { cfPtr.deinitialize(count: 1); cfPtr.deallocate() }
        let idPtr = UnsafeMutablePointer<AudioDeviceID>.allocate(capacity: 1)
        idPtr.initialize(to: kAudioObjectUnknown)
        defer { idPtr.deinitialize(count: 1); idPtr.deallocate() }
        var translation = AudioValueTranslation(
            mInputData: UnsafeMutableRawPointer(cfPtr),
            mInputDataSize: UInt32(MemoryLayout<CFString>.size),
            mOutputData: UnsafeMutableRawPointer(idPtr),
            mOutputDataSize: UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        var size = UInt32(MemoryLayout<AudioValueTranslation>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDeviceForUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &translation
        )
        id = idPtr.pointee
        guard status == noErr, id != kAudioObjectUnknown, id != 0 else { return nil }
        return id
    }

    private static func hasInputChannels(_ id: AudioDeviceID) -> Bool {
        var size: UInt32 = 0
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else {
            return false
        }
        let buf = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buf.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, buf) == noErr else { return false }
        let list = buf.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        for b in buffers where b.mNumberChannels > 0 { return true }
        return false
    }

    private static func stringProperty(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var cfStr: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &cfStr)
        guard status == noErr, let value = cfStr?.takeRetainedValue() else { return nil }
        return value as String
    }
}
