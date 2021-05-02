import Cocoa
import Common

final class Keyboard: NSView {
    private let whiteKeysStackView = NSStackView()
    private let blackKeysStackView = NSStackView()
    private let keyViews: [NSView & KeyboardNoteViewType] // indices matches MIDI note number
    var activeNotes: [ActiveNote] = [] {
        didSet {
            keyViews.enumerated().forEach { index, kv in
                if let note = (activeNotes.first {$0.note.rawValue == index + 21}) {
                    kv.highlightNote(channel: note.channel, velocity: note.velocity)
                } else {
                    kv.reset()
                }
            }
        }
    }

    struct ActiveNote {
        var channel: UInt8
        var note: Note
        var velocity: UInt8
    }

    init() {
        self.keyViews = [
            [WhiteKeyView(), BlackKeyView(), WhiteKeyView()],
            [WhiteKeyView(), BlackKeyView(), WhiteKeyView(), BlackKeyView(), WhiteKeyView()],
            [WhiteKeyView(), BlackKeyView(), WhiteKeyView(), BlackKeyView(), WhiteKeyView(), BlackKeyView(), WhiteKeyView()],
            [WhiteKeyView(), BlackKeyView(), WhiteKeyView(), BlackKeyView(), WhiteKeyView()],
            [WhiteKeyView(), BlackKeyView(), WhiteKeyView(), BlackKeyView(), WhiteKeyView(), BlackKeyView(), WhiteKeyView()],
            [WhiteKeyView(), BlackKeyView(), WhiteKeyView(), BlackKeyView(), WhiteKeyView()],
            [WhiteKeyView(), BlackKeyView(), WhiteKeyView(), BlackKeyView(), WhiteKeyView(), BlackKeyView(), WhiteKeyView()],
            [WhiteKeyView(), BlackKeyView(), WhiteKeyView(), BlackKeyView(), WhiteKeyView()],
            [WhiteKeyView(), BlackKeyView(), WhiteKeyView(), BlackKeyView(), WhiteKeyView(), BlackKeyView(), WhiteKeyView()],
            [WhiteKeyView(), BlackKeyView(), WhiteKeyView(), BlackKeyView(), WhiteKeyView()],
            [WhiteKeyView(), BlackKeyView(), WhiteKeyView(), BlackKeyView(), WhiteKeyView(), BlackKeyView(), WhiteKeyView()],
            [WhiteKeyView(), BlackKeyView(), WhiteKeyView(), BlackKeyView(), WhiteKeyView()],
            [WhiteKeyView(), BlackKeyView(), WhiteKeyView(), BlackKeyView(), WhiteKeyView(), BlackKeyView(), WhiteKeyView()],
            [WhiteKeyView(), BlackKeyView(), WhiteKeyView(), BlackKeyView(), WhiteKeyView()],
            [WhiteKeyView(), BlackKeyView(), WhiteKeyView(), BlackKeyView(), WhiteKeyView(), BlackKeyView(), WhiteKeyView()],
            [WhiteKeyView()],
        ].flatMap {$0}
        super.init(frame: .zero)

        wantsLayer = true
        layer!.backgroundColor = NSColor.darkGray.cgColor

        whiteKeysStackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(whiteKeysStackView)
        whiteKeysStackView.leftAnchor.constraint(equalTo: leftAnchor, constant: 1).isActive = true
        whiteKeysStackView.rightAnchor.constraint(equalTo: rightAnchor, constant: -1).isActive = true
        whiteKeysStackView.topAnchor.constraint(equalTo: topAnchor).isActive = true
        whiteKeysStackView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true

        blackKeysStackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blackKeysStackView)
        blackKeysStackView.leftAnchor.constraint(equalTo: leftAnchor, constant: 1).isActive = true
        blackKeysStackView.rightAnchor.constraint(equalTo: rightAnchor, constant: -1).isActive = true
        blackKeysStackView.topAnchor.constraint(equalTo: topAnchor).isActive = true
        blackKeysStackView.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.66).isActive = true
        blackKeysStackView.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor).isActive = true

        whiteKeysStackView.orientation = .horizontal
        whiteKeysStackView.distribution = .fillEqually
        whiteKeysStackView.spacing = 1
        keyViews.compactMap {$0 as? WhiteKeyView}.forEach {
            whiteKeysStackView.addArrangedSubview($0)
        }

        blackKeysStackView.orientation = .horizontal
        blackKeysStackView.distribution = .fillProportionally
        blackKeysStackView.spacing = 0
        var blackKeyViewsPool = keyViews.compactMap {$0 as? BlackKeyView}
        func blackKeyBlackPortion() -> NSView {
            blackKeyViewsPool.removeFirst()
        }
        func oneBlackKeysSection() -> NSView {
            let stackView = ProportionalStackView()
            stackView.overriddenIntrinsicContentSize.width = 2
            stackView.orientation = .horizontal
            stackView.distribution = .fillEqually
            stackView.spacing = 1
            stackView.addArrangedSubview(NSView())
            stackView.addArrangedSubview(blackKeyBlackPortion())
            stackView.addArrangedSubview(NSView())
            return stackView
        }
        func twoBlackKeysSection() -> NSView {
            let stackView = ProportionalStackView()
            stackView.overriddenIntrinsicContentSize.width = 3
            stackView.orientation = .horizontal
            stackView.distribution = .fillEqually
            stackView.spacing = 1
            stackView.addArrangedSubview(NSView())
            stackView.addArrangedSubview(blackKeyBlackPortion())
            stackView.addArrangedSubview(NSView())
            stackView.addArrangedSubview(blackKeyBlackPortion())
            stackView.addArrangedSubview(NSView())
            return stackView
        }
        func threeBlackKeysSection() -> NSView {
            let stackView = ProportionalStackView()
            stackView.overriddenIntrinsicContentSize.width = 4
            stackView.orientation = .horizontal
            stackView.distribution = .fillEqually
            stackView.spacing = 1
            stackView.addArrangedSubview(NSView())
            stackView.addArrangedSubview(blackKeyBlackPortion())
            stackView.addArrangedSubview(NSView())
            stackView.addArrangedSubview(blackKeyBlackPortion())
            stackView.addArrangedSubview(NSView())
            stackView.addArrangedSubview(blackKeyBlackPortion())
            stackView.addArrangedSubview(NSView())
            return stackView
        }
        func noBlackKeysSection() -> NSView {
            let stackView = ProportionalStackView()
            stackView.overriddenIntrinsicContentSize.width = 1
            stackView.orientation = .horizontal
            stackView.distribution = .fillEqually
            stackView.spacing = 1
            stackView.addArrangedSubview(NSView())
            return stackView
        }

        blackKeysStackView.addArrangedSubview(oneBlackKeysSection())
        (0..<7).forEach { _ in
            blackKeysStackView.addArrangedSubview(twoBlackKeysSection())
            blackKeysStackView.addArrangedSubview(threeBlackKeysSection())
        }
        blackKeysStackView.addArrangedSubview(noBlackKeysSection())
    }

    final class ProportionalStackView: NSStackView {
        var overriddenIntrinsicContentSize: NSSize = NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        override var intrinsicContentSize: NSSize {
            overriddenIntrinsicContentSize
        }
    }

    private func keyView(for note: Note) -> NSView? {
        note.rawValue < keyViews.count ? keyViews[Int(note.rawValue)] : nil
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    final class WhiteKeyView: NSView, KeyboardNoteViewType {
        let backgroundColor = NSColor.white
        let highlightColor = NSColor.systemGreen

        init() {
            super.init(frame: .zero)
            wantsLayer = true
            reset()
        }
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func reset() {
            layer!.backgroundColor = backgroundColor.cgColor
            layer!.borderWidth = 0
        }
        func highlightNote(channel: UInt8, velocity: UInt8) {
            layer!.borderColor = highlightColor.cgColor
            layer!.backgroundColor = backgroundColor.blended(withFraction: CGFloat(velocity) / 127, of: highlightColor)?.cgColor
            layer!.borderWidth = 2
        }
    }

    final class BlackKeyView: NSView, KeyboardNoteViewType {
        let backgroundColor = NSColor.init(white: 0.1, alpha: 1)
        let highlightColor = NSColor.systemGreen

        init() {
            super.init(frame: .zero)
            wantsLayer = true
            reset()
        }
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func reset() {
            layer!.backgroundColor = backgroundColor.cgColor
            layer!.borderWidth = 0
        }
        func highlightNote(channel: UInt8, velocity: UInt8) {
            layer!.borderColor = highlightColor.cgColor
            layer!.backgroundColor = backgroundColor.blended(withFraction: CGFloat(velocity) / 127, of: highlightColor)?.cgColor
            layer!.borderWidth = 2
        }
    }
}

protocol KeyboardNoteViewType {
    func reset()
    func highlightNote(channel: UInt8, velocity: UInt8)
}
