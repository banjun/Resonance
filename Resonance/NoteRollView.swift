import Cocoa
import Common

final class NoteRollView: NSView, NSCollectionViewDataSource {
    /// assuming 120 BPM, i.e. 2 beats / sec, 0.5 sec lays out in 20pt.
    var scalePointPerBeat: CGFloat = 20 {
        didSet {
            rollLayout.scalePointPerBeat = scalePointPerBeat
        }
    }
    /// mach_absolute_time comes from MIDIPacket
    var timeOrigin: TimeInterval = 0

    private var notes: [Note] = [] {
        didSet {
            // for now assume appending only
//            let insertedIndexPaths = (oldValue.count..<notes.count).map {IndexPath(item: $0, section: 0)}
//            collectionView.insertItems(at: Set(insertedIndexPaths))
            // TODO: reload item if a note is closed by noteOff
            collectionView.reloadData()
        }
    }

    struct Note {
        var channel: Int
        var velocity: CGFloat // 0-1
        var note: Int
        var start: TimeInterval
        var end: TimeInterval?
    }

    private let scrollView = NSScrollView()
    private let collectionView = NSCollectionView()
    private let rollLayout: RollLayout

    init() {
        self.rollLayout = RollLayout()
        super.init(frame: .zero)
        wantsLayer = true
        layer!.backgroundColor = NSColor.systemBlue.cgColor

        collectionView.collectionViewLayout = rollLayout
        rollLayout.noteForIndexPath = { [unowned self] indexPath in
            self.notes[indexPath.item]
        }
        collectionView.dataSource = self
        collectionView.register(NoteCell.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier(rawValue: "Note"))

        scrollView.documentView = collectionView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        scrollView.leftAnchor.constraint(equalTo: leftAnchor).isActive = true
        scrollView.rightAnchor.constraint(equalTo: rightAnchor).isActive = true
        scrollView.topAnchor.constraint(equalTo: topAnchor).isActive = true
        scrollView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
    }
    required init?(coder: NSCoder) {fatalError()}

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        notes.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "Note"), for: indexPath)
    }

    func appendPacket(_ packet: Packet) {
        if timeOrigin == 0 {
            timeOrigin = packet.timeStampInSeconds
        }

        switch packet.data {
        case .noteOff(channel: let channel, key: let note, velocity: _),
             .noteOn(channel: let channel, key: let note, velocity: 0):
            guard let lastNoteIndex = (notes.lastIndex {$0.channel == Int(channel) && $0.note == note.rawValue}) else { break }
            notes[lastNoteIndex].end = packet.timeStampInSeconds
        case .noteOn(channel: let channel, key: let note, velocity: let velocity):
            notes.append(Note(channel: Int(channel), velocity: CGFloat(velocity) / 127, note: Int(note.rawValue), start: packet.timeStampInSeconds, end: nil))
        case .programChange(channel: _, program: _): break
        case .controlChange(channel: _, message: let message):
            switch message {
            case .allNotesOff, .damperPedalOnOff, .localControlOff, .localControlOn, .monoModeOn, .omniModeOn, .omniModeOff, .polyModeOn, .portamentoOnOff,.sustenutoOnOff,.softPedalOnOff,.unknown: break
            }
        case .unknown: break
        }
    }
}

private class NoteCell: NSCollectionViewItem {
    let contentView = NoteCellView()
    override init(nibName nibNameOrNil: NSNib.Name?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nil, bundle: nil)
        view = contentView
    }
    required init?(coder: NSCoder) {fatalError()}
}
private class NoteCellView: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer!.backgroundColor = NSColor.systemGreen.cgColor
        layer!.borderColor = NSColor.gray.cgColor
        layer!.borderWidth = 1
        layer!.cornerRadius = 2
        layer!.masksToBounds = true
    }
    required init?(coder: NSCoder) {fatalError()}
}

private class RollLayout: NSCollectionViewLayout {
    private var attributes: [NSCollectionViewLayoutAttributes] = []
    var noteForIndexPath: ((IndexPath) -> NoteRollView.Note)?
    var scalePointPerBeat: CGFloat = 40 {
        didSet {
            invalidateLayout()
        }
    }

    override func prepare() {
        super.prepare()

        let area = collectionViewContentSize

        if let collectionView = collectionView, collectionView.numberOfSections > 0 {
            let indexPaths = (0..<collectionView.numberOfItems(inSection: 0)).map {IndexPath(item: $0, section: 0)}
            let notes = indexPaths.map {noteForIndexPath?($0)}

            let keys: CGFloat = 88
            let noteNumberOffset = -21
            let noteWidth = area.width / keys
            let earliestNoteStart = CGFloat(notes.compactMap {$0}.min {$0.start < $1.start}?.start ?? 0)

            attributes = zip(indexPaths, notes).compactMap {indexPath, note in note.map {(indexPath, $0)}}.map { indexPath, note in
                let a = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
                a.frame = .init(
                    x: CGFloat(note.note + noteNumberOffset) * noteWidth,
                    y: (CGFloat(note.start) - earliestNoteStart) * scalePointPerBeat,
                    width: noteWidth,
                    height: CGFloat((note.end ?? 100) - note.start) * scalePointPerBeat)
                return a
            }
        } else {
            attributes.removeAll()
        }
    }

    override var collectionViewContentSize: NSSize {
        guard let collectionView = collectionView, collectionView.numberOfSections > 0 else { return .zero }
        return .init(width: collectionView.bounds.width, height: 20000)
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

import SwiftUI
struct NoteRollViewRepresentable<View: NSView>: NSViewRepresentable {
    let view: View
    func makeNSView(context: Context) -> View {
        view
    }
    func updateNSView(_ nsView: View, context: Context) {
    }
}
struct NoteRollView_Preview: PreviewProvider {
    static var previews: NoteRollViewRepresentable<NoteRollView> {
        NoteRollViewRepresentable<NoteRollView>(view: {
            let v = NoteRollView()
            v.appendPacket(Packet(timeStampInSeconds: 10, data: .noteOn(channel: 0, key: 60, velocity: 64)))
            v.appendPacket(Packet(timeStampInSeconds: 11, data: .noteOff(channel: 0, key: 60, velocity: 64)))
            v.appendPacket(Packet(timeStampInSeconds: 11, data: .noteOn(channel: 0, key: 62, velocity: 64)))
            v.appendPacket(Packet(timeStampInSeconds: 12, data: .noteOff(channel: 0, key: 62, velocity: 64)))
            v.appendPacket(Packet(timeStampInSeconds: 12, data: .noteOn(channel: 0, key: 64, velocity: 64)))
            v.appendPacket(Packet(timeStampInSeconds: 13, data: .noteOff(channel: 0, key: 64, velocity: 64)))
            v.appendPacket(Packet(timeStampInSeconds: 13, data: .noteOn(channel: 0, key: 65, velocity: 64)))
            v.appendPacket(Packet(timeStampInSeconds: 14, data: .noteOff(channel: 0, key: 65, velocity: 64)))
            v.appendPacket(Packet(timeStampInSeconds: 14, data: .noteOn(channel: 0, key: 67, velocity: 64)))
            v.appendPacket(Packet(timeStampInSeconds: 15, data: .noteOff(channel: 0, key: 67, velocity: 64)))
            v.appendPacket(Packet(timeStampInSeconds: 20, data: .noteOn(channel: 0, key: 64, velocity: 64)))
            return v
        }())
    }
}
