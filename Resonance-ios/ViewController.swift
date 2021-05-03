
import UIKit
import Common
import Combine

final class ViewController: UIViewController {
    private var client: Client?
    private let midiSynth = MIDISynth()
    private var cancellables = Set<AnyCancellable>()

    private lazy var midiSynthButton = UIBarButtonItem(title: "Synth", style: .plain, target: self, action: #selector(toggleMIDISynth))

    private let keyboard = Keyboard()
    private lazy var keyboardWidthConstraint: NSLayoutConstraint = keyboard.widthAnchor.constraint(equalToConstant: 1024)
    private var keyboardWidthScale: CGFloat = 1 {
        didSet {updateKeyboardScale()}
    }
    private var activeNotes: [Keyboard.ActiveNote] = [] {
        didSet {
            keyboard.activeNotes = activeNotes
        }
    }
    
    init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = midiSynthButton

        let keyboardScrollView = UIScrollView()
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        keyboardScrollView.addSubview(keyboard)
        keyboardScrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboardScrollView)

        keyboardScrollView.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        keyboardScrollView.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        keyboardScrollView.heightAnchor.constraint(equalToConstant: 256).isActive = true
        keyboardScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        keyboard.leftAnchor.constraint(equalTo: keyboardScrollView.leftAnchor).isActive = true
        keyboard.rightAnchor.constraint(equalTo: keyboardScrollView.rightAnchor).isActive = true
        keyboard.topAnchor.constraint(equalTo: keyboardScrollView.frameLayoutGuide.topAnchor).isActive = true
        keyboard.bottomAnchor.constraint(equalTo: keyboardScrollView.frameLayoutGuide.bottomAnchor).isActive = true
        keyboardWidthConstraint.isActive = true

        let keyboardScaleGesture = UIPinchGestureRecognizer(target: self, action: #selector(keyboardScaleGesture))
        view.addGestureRecognizer(keyboardScaleGesture)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let sources = Source.all()
        self.client = sources.first.flatMap {Client(source: $0)}
        self.client?.packets.receive(on: DispatchQueue.main).sink { [unowned self] packet in
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
        NSLog("all sources = \(sources)")
        NSLog("client.source = \(String(describing: self.client?.source))")
        title = (client?.source.displayName ?? "No MIDI Source") + " (\(sources.count) sources total)"
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateKeyboardScale()
    }

    private func updateKeyboardScale() {
        keyboardWidthConstraint.constant = view.bounds.width * keyboardWidthScale
    }

    @objc private func toggleMIDISynth() {
        midiSynth.isEnabled.toggle()
        midiSynthButton.title = midiSynth.name + (midiSynth.isEnabled ? " Enabled" : " Muted")
    }

    private var keyboardScaleOnGestureBegin: CGFloat = 1
    @objc func keyboardScaleGesture(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began: keyboardScaleOnGestureBegin = keyboardWidthScale
        case .changed: keyboardWidthScale = min(max(1, keyboardScaleOnGestureBegin * gesture.scale), 5)
        default: break
        }
    }
}
