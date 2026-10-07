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
        frequency = try values.read(Float.self, "frequency")
        gain = try values.read(Float.self, "gain")
        bandwidth = try values.read(Float.self, "bandwidth")
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: JSONKey.self)
        try values.write(frequency, "frequency")
        try values.write(gain, "gain")
        try values.write(bandwidth, "bandwidth")
    }
}

extension EQProfile {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: JSONKey.self)
        bands = try values.read([EQBand].self, "bands")
        preamp = try values.read(Float.self, "preamp")
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: JSONKey.self)
        try values.write(bands, "bands")
        try values.write(preamp, "preamp")
    }
}

extension KeyedDecodingContainer where Key == JSONKey {
    func read<Value: Decodable>(_ type: Value.Type, _ key: String) throws -> Value {
        try decode(type, forKey: JSONKey(key))
    }
}
extension KeyedEncodingContainer where Key == JSONKey {
    mutating func write<Value: Encodable>(_ value: Value, _ key: String) throws {
        try encode(value, forKey: JSONKey(key))
    }
}
