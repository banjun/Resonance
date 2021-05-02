#if os(macOS)
import Cocoa
public typealias View = NSView
public typealias StackView = NSStackView
public typealias Color = NSColor
extension View {
    var backgroundLayer: CALayer! {layer}
}
#elseif os(iOS)
import UIKit
public typealias View = UIView
public typealias StackView = UIStackView
public typealias Color = UIColor
extension UIView {
    var wantsLayer: Bool {
        get {true}
        set {}
    }
    var backgroundLayer: CALayer! {layer}
}
extension UIStackView {
    var orientation: NSLayoutConstraint.Axis {
        get {axis}
        set {axis = newValue}
    }
}
#endif

public final class Keyboard: View {
    private let whiteKeysStackView = StackView()
    private let blackKeysStackView = StackView()
    private let keyViews: [View & KeyboardNoteViewType] // indices matches MIDI note number
    public var activeNotes: [ActiveNote] = [] {
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

    public struct ActiveNote {
        public var channel: UInt8
        public var note: Note
        public var velocity: UInt8

        public init(channel: UInt8, note: Note, velocity: UInt8) {
            self.channel = channel
            self.note = note
            self.velocity = velocity
        }
    }

    public init() {
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
        #if os(macOS)
        layer!.backgroundColor = Color.darkGray.cgColor
        #elseif os(iOS)
        backgroundColor = Color.darkGray
        #endif

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
        blackKeysStackView.distribution = .fillProportionally // NSStackView can handle 2:3:4:1 but UIStackView cannot precisely handle them. a workaround is to use 200:300:400:100 and defaultLow compression resistances.
        blackKeysStackView.spacing = 0
        var blackKeyViewsPool = keyViews.compactMap {$0 as? BlackKeyView}
        func blackKeyBlackPortion() -> View {
            blackKeyViewsPool.removeFirst()
        }
        func oneBlackKeysSection() -> View {
            let stackView = ProportionalStackView(intrinsicContentSizeWidth: 200)
            stackView.orientation = .horizontal
            stackView.distribution = .fillEqually
            stackView.spacing = 1
            stackView.addArrangedSubview(View())
            stackView.addArrangedSubview(blackKeyBlackPortion())
            stackView.addArrangedSubview(View())
            return stackView
        }
        func twoBlackKeysSection() -> View {
            let stackView = ProportionalStackView(intrinsicContentSizeWidth: 300)
            stackView.orientation = .horizontal
            stackView.distribution = .fillEqually
            stackView.spacing = 1
            stackView.addArrangedSubview(View())
            stackView.addArrangedSubview(blackKeyBlackPortion())
            stackView.addArrangedSubview(View())
            stackView.addArrangedSubview(blackKeyBlackPortion())
            stackView.addArrangedSubview(View())
            return stackView
        }
        func threeBlackKeysSection() -> View {
            let stackView = ProportionalStackView(intrinsicContentSizeWidth: 400)
            stackView.orientation = .horizontal
            stackView.distribution = .fillEqually
            stackView.spacing = 1
            stackView.addArrangedSubview(View())
            stackView.addArrangedSubview(blackKeyBlackPortion())
            stackView.addArrangedSubview(View())
            stackView.addArrangedSubview(blackKeyBlackPortion())
            stackView.addArrangedSubview(View())
            stackView.addArrangedSubview(blackKeyBlackPortion())
            stackView.addArrangedSubview(View())
            return stackView
        }
        func noBlackKeysSection() -> View {
            let stackView = ProportionalStackView(intrinsicContentSizeWidth: 100)
            stackView.orientation = .horizontal
            stackView.distribution = .fillEqually
            stackView.spacing = 1
            stackView.addArrangedSubview(View())
            return stackView
        }

        blackKeysStackView.addArrangedSubview(oneBlackKeysSection())
        (0..<7).forEach { _ in
            blackKeysStackView.addArrangedSubview(twoBlackKeysSection())
            blackKeysStackView.addArrangedSubview(threeBlackKeysSection())
        }
        blackKeysStackView.addArrangedSubview(noBlackKeysSection())
    }

    final class ProportionalStackView: StackView {
        init(intrinsicContentSizeWidth: CGFloat) {
            super.init(frame: .zero)
            overriddenIntrinsicContentSize.width = intrinsicContentSizeWidth
            setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        required init(coder: NSCoder) {fatalError()}
        var overriddenIntrinsicContentSize: CGSize = CGSize(width: View.noIntrinsicMetric, height: View.noIntrinsicMetric)
        override var intrinsicContentSize: CGSize {
            overriddenIntrinsicContentSize
        }
    }

    private func keyView(for note: Note) -> View? {
        note.rawValue < keyViews.count ? keyViews[Int(note.rawValue)] : nil
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    final class WhiteKeyView: View, KeyboardNoteViewType {
        static let backgroundColor = Color.white
        static let highlightColor = Color.systemGreen

        private let highlightView = View()

        init() {
            super.init(frame: .zero)
            wantsLayer = true
            highlightView.wantsLayer = true
            backgroundLayer.backgroundColor = Self.backgroundColor.cgColor
            highlightView.backgroundLayer.backgroundColor = Self.highlightColor.cgColor
            addSubview(highlightView)
            highlightView.translatesAutoresizingMaskIntoConstraints = false
            highlightView.leftAnchor.constraint(equalTo: leftAnchor).isActive = true
            highlightView.rightAnchor.constraint(equalTo: rightAnchor).isActive = true
            highlightView.topAnchor.constraint(equalTo: topAnchor).isActive = true
            highlightView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
            reset()
        }
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func reset() {
            highlightView.backgroundLayer.opacity = 0
            backgroundLayer.borderWidth = 0
        }
        func highlightNote(channel: UInt8, velocity: UInt8) {
            highlightView.backgroundLayer.opacity = Float(velocity) / 127
            backgroundLayer.borderColor = Self.highlightColor.cgColor
            backgroundLayer.borderWidth = 2
        }
    }

    final class BlackKeyView: View, KeyboardNoteViewType {
        static let backgroundColor = Color.init(white: 0.1, alpha: 1)
        static let highlightColor = Color.systemGreen

        private let highlightView = View()

        init() {
            super.init(frame: .zero)
            wantsLayer = true
            highlightView.wantsLayer = true
            backgroundLayer.backgroundColor = Self.backgroundColor.cgColor
            highlightView.backgroundLayer.backgroundColor = Self.highlightColor.cgColor
            addSubview(highlightView)
            highlightView.translatesAutoresizingMaskIntoConstraints = false
            highlightView.leftAnchor.constraint(equalTo: leftAnchor).isActive = true
            highlightView.rightAnchor.constraint(equalTo: rightAnchor).isActive = true
            highlightView.topAnchor.constraint(equalTo: topAnchor).isActive = true
            highlightView.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
            reset()
        }
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func reset() {
            highlightView.backgroundLayer.opacity = 0
            backgroundLayer.borderWidth = 0
        }
        func highlightNote(channel: UInt8, velocity: UInt8) {
            highlightView.backgroundLayer.opacity = Float(velocity) / 127
            backgroundLayer.borderColor = Self.highlightColor.cgColor
            backgroundLayer.borderWidth = 2
        }
    }
}

protocol KeyboardNoteViewType {
    func reset()
    func highlightNote(channel: UInt8, velocity: UInt8)
}
