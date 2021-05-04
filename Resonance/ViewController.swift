import Cocoa
import Combine
import Common

class ViewController: NSViewController, NSToolbarDelegate, NSCollectionViewDataSource {
    private var midiInputSources: [Source] = [] {
        didSet {
            NSLog("midiInputSources = \(midiInputSources)")
            midiInputPopUp.removeAllItems()
            midiInputPopUp.addItems(withTitles: midiInputSources.map {$0.displayName ?? $0.name ?? $0.model ?? $0.manufacturer ?? "(null)"})
        }
    }
    private var midiOutputDestinations: [Destination] = [] {
        didSet {
            NSLog("midiOutputDestinations = \(midiOutputDestinations)")
            midiOutputPopUp.removeAllItems()
            midiOutputPopUp.addItem(withTitle: "No Output")
            midiOutputPopUp.addItems(withTitles: midiOutputDestinations.map {$0.displayName ?? $0.name ?? $0.model ?? $0.manufacturer ?? "(null)"})
        }
    }
    private var client: Client? {
        didSet {
            updateClient()
        }
    }
    private var cancellables = Set<AnyCancellable>()
    private let eventsView = StickyCollectionView()
    private let keyboard = Keyboard()
    private lazy var keyboardWidthConstraint: NSLayoutConstraint = keyboard.widthAnchor.constraint(equalToConstant: 1024)
    private var keyboardWidthScale: CGFloat = 1 {
        didSet {updateKeyboardScale()}
    }

    private var packets: [Packet] = [] {
        didSet {
            let updatedIdexPaths = (oldValue.count..<packets.count).map {IndexPath(item: $0, section: 0)}
            eventsView.collectionView.insertItems(at: Set(updatedIdexPaths))
            eventsView.scrollToStickyPosition()
        }
    }

    private var activeNotes: [Keyboard.ActiveNote] = [] {
        didSet {
            keyboard.activeNotes = activeNotes
        }
    }

    private let noteRollView = NoteRollView()

    private let midiSynth = MIDISynth()

    override func viewDidLoad() {
        eventsView.collectionView.dataSource = self
        eventsView.collectionView.collectionViewLayout = EventsLayout()

        eventsView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(eventsView)

        noteRollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(noteRollView)

        let keyboardScaleSlider = NSSlider(value: 1, minValue: 1, maxValue: 5, target: self, action: #selector(keyboardScaleSliderValueChanged(_:)))
        keyboardScaleSlider.numberOfTickMarks = 5
        keyboardScaleSlider.isContinuous = true
        keyboardScaleSlider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboardScaleSlider)

        let keyboardScrollView = NSScrollView()
        keyboardScrollView.documentView = keyboard
        keyboardScrollView.verticalScrollElasticity = .none
        keyboardScrollView.translatesAutoresizingMaskIntoConstraints = false
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboardScrollView)

        eventsView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        eventsView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        eventsView.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        eventsView.bottomAnchor.constraint(equalTo: noteRollView.topAnchor).isActive = true
        eventsView.widthAnchor.constraint(greaterThanOrEqualToConstant: 256).isActive = true
        eventsView.heightAnchor.constraint(equalToConstant: 64).isActive = true

        noteRollView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        noteRollView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        noteRollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 256).isActive = true
        noteRollView.bottomAnchor.constraint(equalTo: keyboardScaleSlider.topAnchor, constant: -4).isActive = true

        keyboardScaleSlider.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -8).isActive = true
        keyboardScaleSlider.widthAnchor.constraint(equalToConstant: 128).isActive = true
        keyboardScaleSlider.bottomAnchor.constraint(equalTo: keyboardScrollView.topAnchor, constant: -4).isActive = true

        keyboardScrollView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        keyboardScrollView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        keyboardScrollView.heightAnchor.constraint(equalToConstant: 128).isActive = true
        keyboardScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        keyboard.topAnchor.constraint(equalTo: keyboardScrollView.topAnchor).isActive = true
        keyboard.bottomAnchor.constraint(equalTo: keyboardScrollView.bottomAnchor).isActive = true
        keyboardWidthConstraint.isActive = true
    }

    override func viewDidAppear() {
        super.viewDidAppear()

        let sources = Source.all()
        self.midiInputSources = sources
        self.midiOutputDestinations = Destination.all()
        self.client = sources.first.flatMap {Client(source: $0)}
        
        let toolbar = NSToolbar(identifier: "ViewController")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = true
        view.window?.toolbar = toolbar
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateKeyboardScale()
    }

    private func updateClient() {
        cancellables.removeAll()
        client?.packets.receive(on: DispatchQueue.main).sink { [unowned self] packet in
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

            noteRollView.appendPacket(packet)

            midiSynth.play(event: packet.data)
        }.store(in: &cancellables)
        client?.packets.collect(.byTime(DispatchQueue.main, 0.1)).sink { [unowned self] in
            packets.append(contentsOf: $0)
        }.store(in: &cancellables)
        NSLog("client.source = \(String(describing: client?.source))")
        let title = (client?.source.displayName ?? "No MIDI Source")
        self.title = title
        view.window?.title = title
    }

    private func updateKeyboardScale() {
        keyboardWidthConstraint.constant = view.bounds.width * keyboardWidthScale
    }

    @objc func keyboardScaleSliderValueChanged(_ sender: AnyObject?) {
        guard let slider = sender as? NSControl else { return }
        keyboardWidthScale = CGFloat(slider.floatValue)
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        packets.count
    }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let packet = packets[indexPath.item]
        let item = NSCollectionViewItem()
        let label = NSTextField(labelWithString: String(describing: packet))
        label.font = .monospacedSystemFont(ofSize: label.font!.pointSize, weight: .regular)
        item.view = label
        return item
    }

    private let midiInputToolbarItem = NSToolbarItem(itemIdentifier: .midiInput)
    private let midiInputPopUp = NSPopUpButton(title: "", target: self, action: #selector(ViewController.midiInputDidSelect))
    private let midiOutputToolbarItem = NSToolbarItem(itemIdentifier: .midiOutput)
    private let midiOutputPopUp = NSPopUpButton(title: "", target: self, action: #selector(ViewController.midiOutputDidSelect))
    private let midiSynthToolbarItem = NSToolbarItem(itemIdentifier: .midiSynth)

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .midiInput:
            midiInputToolbarItem.label = "MIDI Input"
            midiInputToolbarItem.target = nil
            midiInputToolbarItem.view = midiInputPopUp
            return midiInputToolbarItem
        case .midiOutput:
            midiOutputToolbarItem.label = "MIDI Output"
            midiOutputToolbarItem.target = nil
            midiOutputToolbarItem.view = midiOutputPopUp
            return midiOutputToolbarItem
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
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.midiInput, .midiOutput, .space, .flexibleSpace, .midiSynth] }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.midiInput, .midiOutput, .space, .midiSynth] }

    @objc private func midiInputDidSelect() {
        let index = midiInputPopUp.indexOfSelectedItem
        guard index < midiInputSources.count,
              let client = Client(source: midiInputSources[index]) else {
            midiInputPopUp.selectItem(at: -1)
            return
        }
        self.client = client

        let destinationIndex = midiOutputPopUp.indexOfSelectedItem - 1
        guard case 0..<midiOutputDestinations.count = destinationIndex else { return }
        client.thruDestination = midiOutputDestinations[destinationIndex]
    }

    @objc private func midiOutputDidSelect() {
        let index = midiOutputPopUp.indexOfSelectedItem - 1
        guard case 0..<midiOutputDestinations.count = index else {
            midiOutputPopUp.selectItem(at: 0)
            return
        }
        client?.thruDestination = midiOutputDestinations[index]
    }

    @objc private func toggleMIDISynth() {
        midiSynth.isEnabled.toggle()
        midiSynthToolbarItem.label = midiSynth.name + (midiSynth.isEnabled ? " Enabled" : " Muted")
    }
}

private extension NSToolbarItem.Identifier {
    static let midiSynth: NSToolbarItem.Identifier = .init("MIDISynth")
    static let midiInput: NSToolbarItem.Identifier = .init("MIDIInput")
    static let midiOutput: NSToolbarItem.Identifier = .init("MIDIOutput")
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
        collectionViewContentSize != newBounds.size
    }
}
