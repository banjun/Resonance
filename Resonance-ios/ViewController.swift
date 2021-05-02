
import UIKit
import Common
import Combine

final class ViewController: UIViewController {
    private var client: Client?
    private let midiSynth = MIDISynth()
    private var cancellables = Set<AnyCancellable>()

    private lazy var midiSynthButton = UIBarButtonItem(title: "Synth", style: .plain, target: self, action: #selector(toggleMIDISynth))
    
    init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = midiSynthButton
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let sources = Source.all()
        self.client = sources.first.flatMap {Client(source: $0)}
        self.client?.packets.receive(on: DispatchQueue.main).sink { [unowned self] packet in
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
