import Cocoa
import Combine
import Common

class ViewController: NSViewController, NSToolbarDelegate {
    private var client: Client?
    private var cancellables = Set<AnyCancellable>()
    private let eventsView = StickyCollectionView()
    private lazy var packetsDataSource = NSCollectionViewDiffableDataSource<String, Packet>.init(collectionView: eventsView.collectionView) { eventsView, IndexPath, packet in
        let item = NSCollectionViewItem()
        let label = NSTextField(labelWithString: String(describing: packet))
        label.font = .monospacedSystemFont(ofSize: label.font!.pointSize, weight: .regular)
        item.view = label
        return item
    }
    private let keyboard = Keyboard()

    private var packets: [Packet] = [] {
        didSet {
            let packets = packets
            var snapshot = NSDiffableDataSourceSnapshot<String, Packet>()
            snapshot.appendSections(["Event"])
            snapshot.appendItems(packets)
            packetsDataSource.apply(snapshot, animatingDifferences: true)
            eventsView.scrollToStickyPosition()
        }
    }

    private var activeNotes: [Keyboard.ActiveNote] = [] {
        didSet {
            keyboard.activeNotes = activeNotes
        }
    }

    private let midiSynth = MIDISynth()

    override func viewDidLoad() {
        eventsView.collectionView.collectionViewLayout = EventsLayout()

        eventsView.translatesAutoresizingMaskIntoConstraints = false
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(eventsView)
        view.addSubview(keyboard)

        eventsView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        eventsView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        eventsView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        eventsView.bottomAnchor.constraint(equalTo: keyboard.topAnchor).isActive = true
        eventsView.widthAnchor.constraint(greaterThanOrEqualToConstant: 256).isActive = true
        eventsView.heightAnchor.constraint(greaterThanOrEqualToConstant: 256).isActive = true

        keyboard.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        keyboard.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        keyboard.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor).isActive = true
        keyboard.heightAnchor.constraint(equalToConstant: 128).isActive = true
        keyboard.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        let sources = Source.all()
        self.client = sources.first.flatMap {Client(source: $0)}
        self.client?.packets.receive(on: DispatchQueue.main).sink { [unowned self] packet in
            packets.append(packet)

            switch packet.data {
            case .controlChange(channel: let channel, message: .allNotesOff):
                activeNotes = activeNotes.filter {!($0.channel == channel)}
            case .noteOff(channel: let channel, key: let note, velocity: _):
                activeNotes = activeNotes.filter {!($0.channel == channel && $0.note == note)}
            case .noteOn(channel: let channel, key: let note, velocity: let velocity):
                activeNotes = activeNotes.filter {!($0.channel == channel && $0.note == note)}
                    + [Keyboard.ActiveNote(channel: channel, note: note, velocity: velocity)]
            default:
                break
            }

            midiSynth.play(event: packet.data)
        }.store(in: &cancellables)
        NSLog("client.source = \(String(describing: self.client?.source))")
        let title = (client?.source.displayName ?? "No MIDI Source") + " (\(sources.count) sources total)"
        self.title = title
        view.window?.title = title

        let toolbar = NSToolbar()
        toolbar.delegate = self
        toolbar.insertItem(withItemIdentifier: NSToolbarItem.Identifier.flexibleSpace, at: 0)
        toolbar.insertItem(withItemIdentifier: NSToolbarItem.Identifier(rawValue: "MIDISynth"), at: 1)
        view.window?.toolbar = toolbar
    }

    let midiSynthToolbarItem = NSToolbarItem(itemIdentifier: .midiSynth)

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .midiSynth:
            midiSynthToolbarItem.image = NSImage(named: NSImage.slideshowTemplateName)
            midiSynthToolbarItem.label = midiSynth.name + " Muted"
            midiSynthToolbarItem.target = nil
            midiSynthToolbarItem.action = #selector(ViewController.toggleMIDISynth)
            return midiSynthToolbarItem
        default:
            return .init(itemIdentifier: itemIdentifier)
        }
    }
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.midiSynth] }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.midiSynth] }

    @objc private func toggleMIDISynth() {
        midiSynth.isEnabled.toggle()
        midiSynthToolbarItem.label = midiSynth.name + (midiSynth.isEnabled ? " Enabled" : " Muted")
    }
}

private extension NSToolbarItem.Identifier {
    static let midiSynth: NSToolbarItem.Identifier = .init("MIDISynth")
}

final class EventsLayout: NSCollectionViewLayout {
    let itemHeight: CGFloat = 20
    private var attributes: [NSCollectionViewLayoutAttributes] = []

    override func prepare() {
        super.prepare()

        if let collectionView = collectionView, collectionView.numberOfSections > 0 {
            attributes = (0..<collectionView.numberOfItems(inSection: 0)).map {
                let a = NSCollectionViewLayoutAttributes(forItemWith: IndexPath(item: $0, section: 0))
                a.frame = .init(x: 0, y: itemHeight * CGFloat($0), width: collectionViewContentSize.width, height: itemHeight)
                return a
            }
        } else {
            attributes.removeAll()
        }
    }

    override var collectionViewContentSize: NSSize {
        guard let collectionView = collectionView, collectionView.numberOfSections > 0 else { return .zero }
        return .init(width: collectionView.bounds.width, height: itemHeight * CGFloat(collectionView.numberOfItems(inSection: 0)))
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        attributes.filter {$0.frame.intersects(rect)}
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        attributes[indexPath.item]
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        true
    }
}
