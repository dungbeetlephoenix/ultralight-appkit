import Foundation

struct AnalysisResult: Codable {
    var bassEnergy: Float       // 0-1 normalized
    var midEnergy: Float
    var trebleEnergy: Float
    var spectralCentroid: Float // Hz
    var dynamicRange: Float     // dB
    var peakLevel: Float        // dB
    var suggestedEQ: EQProfile

    // Detection flags
    var isBassHeavy: Bool
    var isBright: Bool
    var isCompressed: Bool
    var isClipping: Bool
    var isDynamic: Bool
    var isThin: Bool
    var isMuddy: Bool

    /// Human-readable reason string matching the Electron app's style
    var reason: String {
        var parts: [String] = []
        if isBassHeavy { parts.append("Bass-heavy") }
        if isThin { parts.append("Thin") }
        if isMuddy { parts.append("Muddy mids") }
        if isBright { parts.append("Bright mix") }
        if isCompressed { parts.append("Compressed") }
        if isDynamic { parts.append("Good dynamics") }
        if isClipping { parts.append("⚠ Clipping") }
        return parts.isEmpty ? "Balanced mix" : parts.joined(separator: " · ")
    }
}

extension AnalysisResult {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: JSONKey.self)
        bassEnergy = try values.decode(Float.self, forKey: JSONKey("bassEnergy"))
        midEnergy = try values.decode(Float.self, forKey: JSONKey("midEnergy"))
        trebleEnergy = try values.decode(Float.self, forKey: JSONKey("trebleEnergy"))
        spectralCentroid = try values.decode(Float.self, forKey: JSONKey("spectralCentroid"))
        dynamicRange = try values.decode(Float.self, forKey: JSONKey("dynamicRange"))
        peakLevel = try values.decode(Float.self, forKey: JSONKey("peakLevel"))
        suggestedEQ = try values.decode(EQProfile.self, forKey: JSONKey("suggestedEQ"))
        isBassHeavy = try values.decode(Bool.self, forKey: JSONKey("isBassHeavy"))
        isBright = try values.decode(Bool.self, forKey: JSONKey("isBright"))
        isCompressed = try values.decode(Bool.self, forKey: JSONKey("isCompressed"))
        isClipping = try values.decode(Bool.self, forKey: JSONKey("isClipping"))
        isDynamic = try values.decode(Bool.self, forKey: JSONKey("isDynamic"))
        isThin = try values.decode(Bool.self, forKey: JSONKey("isThin"))
        isMuddy = try values.decode(Bool.self, forKey: JSONKey("isMuddy"))
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: JSONKey.self)
        try values.encode(bassEnergy, forKey: JSONKey("bassEnergy"))
        try values.encode(midEnergy, forKey: JSONKey("midEnergy"))
        try values.encode(trebleEnergy, forKey: JSONKey("trebleEnergy"))
        try values.encode(spectralCentroid, forKey: JSONKey("spectralCentroid"))
        try values.encode(dynamicRange, forKey: JSONKey("dynamicRange"))
        try values.encode(peakLevel, forKey: JSONKey("peakLevel"))
        try values.encode(suggestedEQ, forKey: JSONKey("suggestedEQ"))
        try values.encode(isBassHeavy, forKey: JSONKey("isBassHeavy"))
        try values.encode(isBright, forKey: JSONKey("isBright"))
        try values.encode(isCompressed, forKey: JSONKey("isCompressed"))
        try values.encode(isClipping, forKey: JSONKey("isClipping"))
        try values.encode(isDynamic, forKey: JSONKey("isDynamic"))
        try values.encode(isThin, forKey: JSONKey("isThin"))
        try values.encode(isMuddy, forKey: JSONKey("isMuddy"))
    }
}
