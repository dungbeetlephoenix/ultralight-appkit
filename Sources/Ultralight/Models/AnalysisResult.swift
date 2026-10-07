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
        bassEnergy = try values.read(Float.self, "bassEnergy")
        midEnergy = try values.read(Float.self, "midEnergy")
        trebleEnergy = try values.read(Float.self, "trebleEnergy")
        spectralCentroid = try values.read(Float.self, "spectralCentroid")
        dynamicRange = try values.read(Float.self, "dynamicRange")
        peakLevel = try values.read(Float.self, "peakLevel")
        suggestedEQ = try values.read(EQProfile.self, "suggestedEQ")
        isBassHeavy = try values.read(Bool.self, "isBassHeavy")
        isBright = try values.read(Bool.self, "isBright")
        isCompressed = try values.read(Bool.self, "isCompressed")
        isClipping = try values.read(Bool.self, "isClipping")
        isDynamic = try values.read(Bool.self, "isDynamic")
        isThin = try values.read(Bool.self, "isThin")
        isMuddy = try values.read(Bool.self, "isMuddy")
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: JSONKey.self)
        try values.write(bassEnergy, "bassEnergy")
        try values.write(midEnergy, "midEnergy")
        try values.write(trebleEnergy, "trebleEnergy")
        try values.write(spectralCentroid, "spectralCentroid")
        try values.write(dynamicRange, "dynamicRange")
        try values.write(peakLevel, "peakLevel")
        try values.write(suggestedEQ, "suggestedEQ")
        try values.write(isBassHeavy, "isBassHeavy")
        try values.write(isBright, "isBright")
        try values.write(isCompressed, "isCompressed")
        try values.write(isClipping, "isClipping")
        try values.write(isDynamic, "isDynamic")
        try values.write(isThin, "isThin")
        try values.write(isMuddy, "isMuddy")
    }
}
