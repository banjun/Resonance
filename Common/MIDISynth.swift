import Foundation
import AVFoundation

private let kAUMIDISynth = kAudioUnitSubType_MIDISynth
private let componentSubType: UInt32 = {
    #if os(macOS)
    return kAudioUnitSubType_DLSSynth // for DLSMusicDevice (supports programs)
    #else
    return kAudioUnitSubType_MIDISynth // for AUMIDISynth (possibly more compatible but sine wave only?)
    #endif
}()

public final class MIDISynth {
    private let engine = AVAudioEngine()
    private let instrument = AVAudioUnitMIDIInstrument(audioComponentDescription: AudioComponentDescription(componentType: kAudioUnitType_MusicDevice, componentSubType: componentSubType, componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0))
    private let eq = AVAudioUnitEQ()
    public var name: String { instrument.name }
    public var isEnabled: Bool = false {
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

    public init() {
        engine.attach(instrument)
        engine.attach(eq)
        eq.globalGain = 20
        engine.connect(instrument, to: eq, format: nil)
        engine.connect(eq, to: engine.outputNode, format: nil)

        // NOTE for non-macOS runtime:
        // the dls file can be found in the system folder.
        // its license is unknown.
        // cp /System/Library/Components/CoreAudio.component/Contents/Resources/gs_instruments.dls Resonance-ios/gs_instruments.dls
        if var soundBankURL = Bundle.main.url(forResource: "gs_instruments", withExtension: "dls", subdirectory: "SystemResource") {
            AudioUnitSetProperty(instrument.audioUnit, kMusicDeviceProperty_SoundBankURL, kAudioUnitScope_Global, 0, &soundBankURL, UInt32(MemoryLayout.size(ofValue: soundBankURL)))
        }
    }

    public func play(event: Event) {
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
