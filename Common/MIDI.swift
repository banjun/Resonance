import Foundation
import CoreMIDI
import Combine

public final class Client {
    public let source: Source
    public let midiClientRef: MIDIClientRef
    public var thruDestination: Destination? {
        didSet {
            thruOutputPortRef = {
                var outputPort: MIDIPortRef = 0
                let status = MIDIOutputPortCreate(midiClientRef, "Output" as CFString, &outputPort)
                guard status == noErr else { return nil }
                return outputPort
            }()
        }
    }
    public var thruOutputPortRef: MIDIPortRef? {
        didSet {
            if let oldValue = oldValue {
                MIDIPortDispose(oldValue)
            }
        }
    }

    public let packets: PassthroughSubject<Packet, Never>

    public init?(source: Source) {
        self.source = source
        self.packets = .init()
        let packets = self.packets

        var midiClientRef: MIDIClientRef = 0
        var status: OSStatus = noErr
        status = MIDIClientCreateWithBlock((source.name ?? "no name") as CFString, &midiClientRef) { notification in
            let notification = notification.pointee
            NSLog("notification = \(notification)")
            switch notification.messageID {
            case .msgSetupChanged: NSLog("msgSetupChanged: size = \(notification.messageSize)")
            case .msgObjectAdded: NSLog("msgObjectAdded: size = \(notification.messageSize)")
            case .msgObjectRemoved: NSLog("msgObjectRemoved: size = \(notification.messageSize)")
            case .msgPropertyChanged: NSLog("msgPropertyChanged: size = \(notification.messageSize)")
            case .msgThruConnectionsChanged: NSLog("msgThruConnectionsChanged: size = \(notification.messageSize)")
            case .msgSerialPortOwnerChanged: NSLog("msgSerialPortOwnerChanged: size = \(notification.messageSize)")
            case .msgIOError: NSLog("msgIOError: size = \(notification.messageSize)")
            @unknown default: NSLog("@unknown default: size = \(notification.messageSize)")
            }
        }
        guard status == noErr else { return nil }
        self.midiClientRef = midiClientRef

        var inputPortRef: MIDIPortRef = 0
        status = MIDIInputPortCreateWithBlock(midiClientRef, "Input" as CFString, &inputPortRef) { [weak self] pktlist, srcConnRefCon in
            if let thruDestination = self?.thruDestination, let thruOutputPortRef = self?.thruOutputPortRef {
                // manually send to output as we cannot tell whether MIDIThru... API works or not
                MIDISend(thruOutputPortRef, thruDestination.endpointRef, pktlist)
            }

            var packet = pktlist.pointee.packet
            packets.send(Packet(packet))
            (1..<pktlist.pointee.numPackets).forEach { _ in
                packet = MIDIPacketNext(&packet).pointee
                packets.send(Packet(packet))
            }
        }
        guard status == noErr else { return nil }

        status = MIDIPortConnectSource(inputPortRef, source.endpointRef, nil)
        guard status == noErr else { return nil }
    }
}

public struct Source {
    public static func all() -> [Source] {
        let numberOfSources = MIDIGetNumberOfSources()
        if numberOfSources > 0 {
            // normal case
            return (0..<numberOfSources).map {Source(MIDIGetSource($0))}.sorted { a, b in
                guard let a = a.model, let b = b.model else { return true }
                switch (a.contains("USB"), b.contains("USB"), a, b) {
                case (true, false, _, _): return true
                case (false, true, _, _): return false
                case (_, _, let a, let b): return a < b
                }
            }
        }
        // some devices incorrectly report MIDIGetNumberOfSources as zero. it may be different from enumerating sources from devices
        // confirmed on iPad Pro (12.9-inch) (3rd generation) iPadOS 13.4 (17E255)
        // maybe this is caused by unwanted system global status and thus also can be comfirmed by just using GarageBand.
        // the global state can be fixed by stimulating from an app. code below:
        ////// chop
        // MIDINetworkSession.default().isEnabled = true
        // MIDINetworkSession.default().connectionPolicy = .anyone
        // MIDINetworkSession.default().addConnection(MIDINetworkConnection(host: MIDINetworkHost(name: "iPad", address: "localhost", port: 18888)))
        //////  end of chop

        // code for debug log
        NSLog("MIDIGetNumberOfSources() reports zero. we should enumerate devices...")
        let numberOfDevices = MIDIGetNumberOfDevices()
        NSLog("numberOfDevices = \(numberOfDevices)")
        return (0..<numberOfDevices).flatMap { i -> [Source] in
            let device = MIDIGetDevice(i)
            var name: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(device, kMIDIPropertyName, &name)
            NSLog("device[\(i)] = \(device), name = \(String(describing: name?.takeRetainedValue()))")
            let numberOfEntities = MIDIDeviceGetNumberOfEntities(device)
            NSLog("\tnumberOfEntities = \(numberOfEntities)")
            return (0..<numberOfEntities).flatMap { i -> [Source] in
                let entity = MIDIDeviceGetEntity(device,i)
                var name: Unmanaged<CFString>?
                MIDIObjectGetStringProperty(entity, kMIDIPropertyName, &name)
                NSLog("\tentity[\(i)] = \(entity), name = \(String(describing: name?.takeRetainedValue()))")
                let numberOfSources = MIDIEntityGetNumberOfSources(entity)
                NSLog("\t\tnumberOfSources = \(numberOfSources)")
                return (0..<numberOfSources).map { i -> Source in
                    let source = Source(MIDIEntityGetSource(entity, i))
                    NSLog("\t\tsource[\(i)] = \(source)")
                    return source
                }
            }
        }
    }

    public var endpointRef: MIDIEndpointRef

    public var name: String?
    public var displayName: String?
    public var manufacturer: String?
    public var model: String?
    public var receiveChannels: Int32?
    public var transmitChannels: Int32?
    public var image: Data?
    public var offline: Int32?
    public var driverOwner: String?

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
        self.offline = property(kMIDIPropertyOffline)
        self.driverOwner = property(kMIDIPropertyDriverOwner)
    }
}

public struct Destination {
    public static func all() -> [Destination] {
        (0..<MIDIGetNumberOfDestinations()).map {Destination(MIDIGetDestination($0))}
    }

    public var endpointRef: MIDIEndpointRef

    public var name: String?
    public var displayName: String?
    public var manufacturer: String?
    public var model: String?
    public var receiveChannels: Int32?
    public var transmitChannels: Int32?
    public var image: Data?
    public var offline: Int32?
    public var canRoute: String?
    public var driverOwner: String?

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
        self.offline = property(kMIDIPropertyOffline)
        self.canRoute = property(kMIDIPropertyCanRoute)
        self.driverOwner = property(kMIDIPropertyDriverOwner)
    }
}

public struct Packet: Equatable, Hashable {
    public var timeStamp: MIDITimeStamp
    public var data: Event

    /// memberwise init
    public init(timeStamp: MIDITimeStamp, data: Event) {
        self.timeStamp = timeStamp
        self.data = data
    }

    /// init with CoreMIDI packets
    public init(_ midiPacket: MIDIPacket) {
        self.timeStamp = midiPacket.timeStamp

        var midiPacket = midiPacket
        let length = min(Int(midiPacket.length), MemoryLayout.size(ofValue: midiPacket.data))
        var data = [UInt8](repeating: 0, count: length)
        memcpy(&data, &midiPacket.data, length)
        self.data = Event(data)
    }

    /// convenience init eliminating `mach_absolute_time`
    public init(timeStampInSeconds: TimeInterval, data: Event) {
        let timebase: mach_timebase_info_t = .allocate(capacity: 1)
        mach_timebase_info(timebase)
        self.timeStamp = UInt64(timeStampInSeconds * Double(NSEC_PER_SEC) * Double(timebase.pointee.denom) / Double(timebase.pointee.numer))
        self.data = data
    }

    public var timeStampInNanoSeconds: UInt64 {
        let timebase: mach_timebase_info_t = .allocate(capacity: 1)
        mach_timebase_info(timebase)
        return timeStamp * UInt64(timebase.pointee.numer) / UInt64(timebase.pointee.denom)
    }
    public var timeStampInSeconds: TimeInterval {
        Double(timeStampInNanoSeconds) / Double(NSEC_PER_SEC)
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

public struct Note: RawRepresentable, CustomStringConvertible, Equatable, Hashable, ExpressibleByIntegerLiteral {
    public var rawValue: UInt8
    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public init(integerLiteral value: UInt8) {
        self.rawValue = value
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

public final class NetworkSession: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    public static let `default` = NetworkSession()
    public let sessionDidChanges = PassthroughSubject<Set<MIDINetworkConnection>, Never>()
    let midiNetworkSession: MIDINetworkSession
    let browser = NetServiceBrowser()
    private var foundServices: [NetService] = []

    override init() {
        self.midiNetworkSession = .default()
        midiNetworkSession.isEnabled = true
        midiNetworkSession.connectionPolicy = .anyone
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(sessionDidChange(_:)), name: .init(MIDINetworkNotificationSessionDidChange), object: midiNetworkSession)

        browser.delegate = self
        browser.includesPeerToPeer = true
    }

    public func startSearching() {
        // for iOS, in Info.plist, NSBonjourServices = "_apple-midi._udp" and NSLocalNetworkUsageDescription = something are required
        // for macOS, app-sandbox requires com.apple.security.network.client
        browser.searchForServices(ofType: MIDINetworkBonjourServiceType, inDomain: "local.")
    }

    public func stopSearching() {
        browser.stop()
    }

    @objc func sessionDidChange(_ notification: Notification) {
        // NSLog("%@", "midiNetworkSession.sourceEndpoint = \(midiNetworkSession.sourceEndpoint()), midiNetworkSession.destinationEndpoint = \(midiNetworkSession.destinationEndpoint())")
        sessionDidChanges.send(midiNetworkSession.connections())
    }

    public func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        NSLog("%@", "\(#function)")
    }
    public func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        NSLog("%@", "\(#function)")
    }
    public func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        NSLog("%@", "\(#function), errorDict = \(errorDict)")
    }
    public func netServiceBrowser(_ browser: NetServiceBrowser, didFindDomain domainString: String, moreComing: Bool) {
        NSLog("%@", "\(#function), domainString = \(domainString), moreComing = \(moreComing)")
    }
    public func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        NSLog("%@", "\(#function), service = \(service), moreComing = \(moreComing)")
        service.delegate = self
        service.resolve(withTimeout: 30)
        foundServices.append(service)
    }
    public func netServiceDidResolveAddress(_ service: NetService) {
        NSLog("%@", "\(#function), service = \(service)")
        // NOTE: macOS cannot initialize MIDINetworkHost on native nor Catalyst. I think Apple have not implemented yet although availability is 10.15+.
        // workaround on macOS: the user can open Audio MIDI Setup.app and manually setup connections in the MIDI network setup window each time disconnection happens.
        let host = MIDINetworkHost(name: service.name, netService: service)
        let result = midiNetworkSession.addConnection(MIDINetworkConnection(host: host))
        NSLog("%@", "\(#function), host = \(host), addConnection = \(result)")
        foundServices = foundServices.filter {service != $0}
    }
    public func netServiceBrowser(_ browser: NetServiceBrowser, didRemoveDomain domainString: String, moreComing: Bool) {
        // NSLog("%@", "\(#function), domainString = \(domainString), moreComing = \(moreComing)")
    }
    public func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        // NSLog("%@", "\(#function), service = \(service), moreComing = \(moreComing)")
    }
}
