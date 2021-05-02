
import UIKit
import Common
import Combine

final class ViewController: UIViewController {
    private var client: Client?
    private let midiSynth = MIDISynth()
    private var cancellables = Set<AnyCancellable>()

    private lazy var midiSynthButton = UIBarButtonItem(title: "Synth", style: .plain, target: self, action: #selector(toggleMIDISynth))

    private let keyboard = Keyboard()
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

        view.addSubview(keyboard)
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        keyboard.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
        keyboard.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        keyboard.topAnchor.constraint(equalTo: view.bottomAnchor, constant: -128).isActive = true
        keyboard.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
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

    @objc private func toggleMIDISynth() {
        midiSynth.isEnabled.toggle()
        midiSynthButton.title = midiSynth.name + (midiSynth.isEnabled ? " Enabled" : " Muted")
    }
}
