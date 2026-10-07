import Foundation

struct EQBand: Codable {
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

struct EQProfile: Codable {
    var bands: [EQBand]
    var preamp: Float       // dB

    static let flat = EQProfile(bands: EQBand.defaultBands, preamp: 0)

    var isFlat: Bool {
        preamp == 0 && bands.allSatisfy { $0.gain == 0 }
    }
}

// Shared string keys avoid one generated key-enum implementation per JSON model.
struct JSONKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

extension EQBand {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: JSONKey.self)
        frequency = try values.decode(Float.self, forKey: JSONKey("frequency"))
        gain = try values.decode(Float.self, forKey: JSONKey("gain"))
        bandwidth = try values.decode(Float.self, forKey: JSONKey("bandwidth"))
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: JSONKey.self)
        try values.encode(frequency, forKey: JSONKey("frequency"))
        try values.encode(gain, forKey: JSONKey("gain"))
        try values.encode(bandwidth, forKey: JSONKey("bandwidth"))
    }
}

extension EQProfile {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: JSONKey.self)
        bands = try values.decode([EQBand].self, forKey: JSONKey("bands"))
        preamp = try values.decode(Float.self, forKey: JSONKey("preamp"))
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: JSONKey.self)
        try values.encode(bands, forKey: JSONKey("bands"))
        try values.encode(preamp, forKey: JSONKey("preamp"))
    }
}
