import Foundation
import AVFoundation

private let kAUMIDISynth = kAudioUnitSubType_MIDISynth // for AUMIDISynth (possibly more compatible but sine wave only?)
private let kDLSMusicDevice = kAudioUnitSubType_DLSSynth // for DLSMusicDevice (supports programs)

final class MIDISynth {
    private let engine = AVAudioEngine()
    private let instrument = AVAudioUnitMIDIInstrument(audioComponentDescription: AudioComponentDescription(componentType: kAudioUnitType_MusicDevice, componentSubType: kDLSMusicDevice, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
    private let eq = AVAudioUnitEQ()
    var name: String { instrument.name }
    var isEnabled: Bool = false {
        didSet {
            if isEnabled {
                do {
                    try engine.start()
                } catch {
                    isEnabled = false
                }
            } else {
                engine.stop()
            }
        }
    }

    init() {
        engine.attach(instrument)
        engine.attach(eq)
        eq.globalGain = 20
        engine.connect(instrument, to: eq, format: nil)
        engine.connect(eq, to: engine.outputNode, format: nil)
    }

    func play(event: Event) {
        guard isEnabled else { return }
        
        switch event {
        case .noteOn(channel: let channel, key: let note, velocity: let velocity):
            instrument.startNote(note.rawValue, withVelocity: velocity, onChannel: channel)
        case .noteOff(channel: let channel, key: let note, velocity: _):
            instrument.stopNote(note.rawValue, onChannel: channel)
        case .programChange(channel: let channel, program: let program):
            instrument.sendProgramChange(program, onChannel: channel)
        default:
            break
        }
    }
}
