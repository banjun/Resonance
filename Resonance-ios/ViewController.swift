import UIKit
import Common
import Combine

final class ViewController: UIViewController {
    @Published private var client: Client?
    private let midiSynth = MIDISynth()
    private var cancellables = Set<AnyCancellable>()

    @Published private var midiInputSources: [Source] = []
    @Published private var selectedSource: Source?
    @Published private var midiOutputDestinations: [Destination] = []
    @Published private var selectedDestination: Destination?
    private lazy var inputSelectButton = UIBarButtonItem(title: nil, style: .plain, target: nil, action: nil)
    private lazy var outputSelectButton = UIBarButtonItem(title: nil, style: .plain, target: self, action: nil)
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
        navigationItem.leftBarButtonItems = [inputSelectButton, outputSelectButton]
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

        $midiInputSources.sink {NSLog("all sources = \($0)")}.store(in: &cancellables)
        $midiOutputDestinations.sink {NSLog("all destinations = \($0)")}.store(in: &cancellables)

        $midiInputSources.combineLatest($selectedSource).sink { [unowned self] sources, source in
            let sourceName = source?.displayName ?? "No Input"
            if #available(iOS 14, *) {
                self.inputSelectButton.menu = UIMenu(title: ["MIDI Input", selectedSource.map {$0.displayName ?? String(describing: $0)}].compactMap {$0}.joined(separator: ": "), children: sources.map { source in
                    UIAction(title: source.displayName ?? String(describing: source)) { [unowned self] _ in
                        self.selectedSource = source
                    }
                })
            } else {
                self.inputSelectButton.target = self
                self.inputSelectButton.action = #selector(inputMenuDidSelect)
            }
            self.inputSelectButton.title = sourceName
        }.store(in: &cancellables)

        $midiOutputDestinations.combineLatest($selectedDestination).sink { [unowned self] destinations, destination in
            let destinationName = destination?.displayName ?? "No Output"
            if #available(iOS 14, *) {
                self.outputSelectButton.menu = UIMenu(
                    title: ["MIDI Output", selectedDestination.map {$0.displayName ?? String(describing: $0)}].compactMap {$0}.joined(separator: ": "),
                    children: [
                        [UIAction(title: "No Output") { [unowned self] _ in
                            self.selectedDestination = nil
                        }],
                        destinations.map { destination in
                            UIAction(title: destination.displayName ?? String(describing: destination)) { [unowned self] _ in
                                self.selectedDestination = destination
                            }
                        }
                    ].flatMap {$0})
            } else {
                self.outputSelectButton.target = self
                self.outputSelectButton.action = #selector(outputMenuDidSelect)
            }
            self.outputSelectButton.title = destinationName
        }.store(in: &cancellables)

        $client.sink { [unowned self] client in
            NSLog("client.source = \(String(describing: client?.source))")
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

                self.midiSynth.play(event: packet.data)
            }.store(in: &cancellables)
        }.store(in: &cancellables)

        $selectedSource.combineLatest($selectedDestination).sink { [unowned self] source, destination in
            if source?.endpointRef != self.client?.source.endpointRef {
                self.client = source.flatMap {Client(source: $0)}
            }
            self.client?.thruDestination = destination
        }.store(in: &cancellables)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        midiInputSources = Source.all()
        selectedSource = midiInputSources.first
        midiOutputDestinations = Destination.all()
        NetworkSession.default.startSearching()
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            NetworkSession.default.stopSearching()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateKeyboardScale()
    }

    private func updateKeyboardScale() {
        keyboardWidthConstraint.constant = view.bounds.width * keyboardWidthScale
    }

    @objc private func inputMenuDidSelect() {
        let sheet = UIAlertController(title: ["MIDI Input", selectedSource.map {$0.displayName ?? String(describing: $0)}].compactMap {$0}.joined(separator: ": "), message: nil, preferredStyle: .actionSheet)
        midiInputSources.map { source in
            UIAlertAction(title: source.displayName ?? String(describing: source), style: .default) { [unowned self] _ in
                self.selectedSource = source
            }
        }.forEach {
            sheet.addAction($0)
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        sheet.popoverPresentationController?.barButtonItem = inputSelectButton
        present(sheet, animated: true)
    }

    @objc private func outputMenuDidSelect() {
        let sheet = UIAlertController(title: ["MIDI Output", selectedDestination.map {$0.displayName ?? String(describing: $0)}].compactMap {$0}.joined(separator: ": "), message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "No Output", style: .default) {[unowned self] _ in self.selectedDestination = nil})
        midiOutputDestinations.map { destination in
            UIAlertAction(title: destination.displayName ?? String(describing: destination), style: .default) { [unowned self] _ in
                self.selectedDestination = destination
            }
        }.forEach {
            sheet.addAction($0)
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        sheet.popoverPresentationController?.barButtonItem = outputSelectButton
        present(sheet, animated: true)
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
