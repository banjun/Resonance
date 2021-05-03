import Foundation
import CoreMIDI
import Combine

public final class Client {
    public let source: Source
    public let midiClientRef: MIDIClientRef
    public let inputPortRef: MIDIPortRef

    public let packets: PassthroughSubject<Packet, Never>

    public init?(source: Source) {
        self.source = source
        self.packets = .init()
        let packets = self.packets

        var midiClientRef: MIDIClientRef = 0
        var status: OSStatus = noErr
        status = MIDIClientCreateWithBlock((source.name ?? "no name") as CFString, &midiClientRef) { notification in
            NSLog("notification = \(notification.pointee)")
        }
        guard status == noErr else { return nil }
        self.midiClientRef = midiClientRef

        var inputPortRef: MIDIPortRef = 0
        status = MIDIInputPortCreateWithBlock(midiClientRef, "Input" as CFString, &inputPortRef) { pktlist, srcConnRefCon in
            var packet = pktlist.pointee.packet
            packets.send(Packet(packet))
            (1..<pktlist.pointee.numPackets).forEach { _ in
                packet = MIDIPacketNext(&packet).pointee
                packets.send(Packet(packet))
            }
        }
        guard status == noErr else { return nil }
        self.inputPortRef = inputPortRef

        status = MIDIPortConnectSource(inputPortRef, source.endpointRef, nil)
        guard status == noErr else { return nil }
    }
}

public struct Source {
    public static func all() -> [Source] {
        (0..<MIDIGetNumberOfSources()).map {Source(MIDIGetSource($0))}.sorted { a, b in
            (a.model ?? "") < (b.model ?? "")
        }.reversed()
    }

    public var endpointRef: MIDIEndpointRef

    public var name: String?
    public var displayName: String?
    public var manufacturer: String?
    public var model: String?
    public var receiveChannels: Int32?
    public var transmitChannels: Int32?
    public var image: Data?

    public init(_ endpointRef: MIDIEndpointRef) {
        self.endpointRef = endpointRef

        func property(_ key: CFString) -> String? {
            var value: Unmanaged<CFString>?
            let status = MIDIObjectGetStringProperty(endpointRef, key, &value)
            return status == noErr ? value?.takeRetainedValue() as String? : nil
        }

        func property(_ key: CFString) -> Int32? {
            var value: Int32 = 0
            let status = MIDIObjectGetIntegerProperty(endpointRef, key, &value)
            return status == noErr ? value : nil
        }

        func property(_ key: CFString) -> Data? {
            var value: Unmanaged<CFData>?
            let status = MIDIObjectGetDataProperty(endpointRef, key, &value)
            return status == noErr ? value?.takeRetainedValue() as Data? : nil
        }

        self.name = property(kMIDIPropertyName)
        self.displayName = property(kMIDIPropertyDisplayName)
        self.manufacturer = property(kMIDIPropertyManufacturer)
        self.model = property(kMIDIPropertyModel)
        self.receiveChannels = property(kMIDIPropertyReceiveChannels)
        self.transmitChannels = property(kMIDIPropertyTransmitChannels)
        self.image = property(kMIDIPropertyImage)
    }
}

public struct Packet: Equatable, Hashable {
    public var timeStamp: MIDITimeStamp
    public var data: Event

    public init(_ midiPacket: MIDIPacket) {
        self.timeStamp = midiPacket.timeStamp

        var midiPacket = midiPacket
        var data = [UInt8](repeating: 0, count: Int(midiPacket.length))
        memcpy(&data, &midiPacket.data, Int(midiPacket.length))
        self.data = Event(data)
    }
}

public enum Event: Equatable, Hashable {
    case noteOff(channel: UInt8, key: Note, velocity: UInt8)
    case noteOn(channel: UInt8, key: Note, velocity: UInt8)
    case controlChange(channel: UInt8, message: ControllerMessage)
    case programChange(channel: UInt8, program: UInt8)
    case unknown([UInt8])

    public enum ControllerMessage: Equatable, Hashable {
        case damperPedalOnOff(value: UInt8)
        case portamentoOnOff(value: UInt8)
        case sustenutoOnOff(value: UInt8)
        case softPedalOnOff(value: UInt8)
        case localControlOff
        case localControlOn
        case allNotesOff
        case omniModeOff
        case omniModeOn
        case monoModeOn(value: UInt8)
        case polyModeOn
        case unknown(control: UInt8, value: UInt8)

        init(control: UInt8, value: UInt8) {
            switch (control, value) {
            case (64, let value): self = .damperPedalOnOff(value: value)
            case (65, let value): self = .portamentoOnOff(value: value)
            case (66, let value): self = .sustenutoOnOff(value: value)
            case (67, let value): self = .softPedalOnOff(value: value)
            case (122, 0): self = .localControlOff
            case (122, 127): self = .localControlOn
            case (123, 0): self = .allNotesOff
            case (124, 0): self = .omniModeOff
            case (125, 0): self = .omniModeOn
            case (126, let m): self = .monoModeOn(value: m)
            case (127, 0): self = .polyModeOn
            default:
                self = .unknown(control: control, value: value)
            }
        }
    }

    public init(_ data: [UInt8]) {
        guard let first = data.first else {
            self = .unknown(data)
            return
        }

        switch ((first & 0xF0) >> 4, first & 0x0F) {
        case (0b1000, let channel):
            guard data.count == 3 else { self = .unknown(data); return }
            self = .noteOff(channel: channel, key: Note(rawValue: data[1]), velocity: data[2])
        case (0b1001, let channel):
            guard data.count == 3 else { self = .unknown(data); return }
            self = .noteOn(channel: channel, key: Note(rawValue: data[1]), velocity: data[2])
        case (0b1011, let channel):
            guard data.count == 3 else { self = .unknown(data); return }
            self = .controlChange(channel: channel, message: ControllerMessage(control: data[1], value: data[2]))
        case (0b1100, let channel):
            guard data.count == 2 else { self = .unknown(data); return }
            self = .programChange(channel: channel, program: data[1])
        default:
            self = .unknown(data)
        }
    }
}

public struct Note: RawRepresentable, CustomStringConvertible, Equatable, Hashable {
    public var rawValue: UInt8
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public var octave: Int {
        Int(rawValue / 12) - 1
    }

    public var labelInSharps: String {
        let labels = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        return labels[Int(rawValue) % labels.count]
    }

    public var labelInFlats: String {
        let labels = ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"]
        return labels[Int(rawValue) % labels.count]
    }

    public var description: String {
       labelInSharps + String(octave)
    }
}
