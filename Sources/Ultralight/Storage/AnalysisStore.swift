import Foundation

enum AnalysisStore {
    private static var fileURL: URL {
        ConfigStore.dataDirectory.appendingPathComponent("analysis-cache.json")
    }

    private static var cache: [String: AnalysisResult] = {
        guard let data = try? Data(contentsOf: fileURL),
              let results = try? JSONDecoder().decode([String: AnalysisResult].self, from: data) else {
            return [:]
        }
        return results
    }()

    static func result(for hash: String) -> AnalysisResult? {
        cache[hash]
    }

    static func save(result: AnalysisResult, for hash: String) {
        cache[hash] = result
        persist()
    }

    private static func persist() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
