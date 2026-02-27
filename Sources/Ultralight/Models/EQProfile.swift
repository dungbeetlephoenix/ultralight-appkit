import Foundation

struct EQBand: Codable, Hashable {
    var frequency: Float    // Hz
    var gain: Float         // dB, -12 to +12
    var bandwidth: Float    // octaves

    static let defaultBands: [EQBand] = [
        EQBand(frequency: 60, gain: 0, bandwidth: 1.0),
        EQBand(frequency: 170, gain: 0, bandwidth: 1.0),
        EQBand(frequency: 310, gain: 0, bandwidth: 1.0),
        EQBand(frequency: 600, gain: 0, bandwidth: 1.0),
        EQBand(frequency: 1000, gain: 0, bandwidth: 1.0),
        EQBand(frequency: 3000, gain: 0, bandwidth: 1.0),
        EQBand(frequency: 6000, gain: 0, bandwidth: 1.0),
        EQBand(frequency: 12000, gain: 0, bandwidth: 1.0),
    ]
}

struct EQProfile: Codable, Hashable {
    var bands: [EQBand]
    var preamp: Float       // dB

    static let flat = EQProfile(bands: EQBand.defaultBands, preamp: 0)

    var isFlat: Bool {
        preamp == 0 && bands.allSatisfy { $0.gain == 0 }
    }
}
