import Foundation

struct AnalysisResult: Codable, Hashable {
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
