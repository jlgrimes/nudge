import Foundation

struct NudgeSnapshot: Codable, Equatable, Sendable {
    var nudges: [NudgeItem]
    var fallbackDays: Int
    var isFocusMode: Bool

    init(nudges: [NudgeItem], fallbackDays: Int, isFocusMode: Bool) {
        self.nudges = nudges
        self.fallbackDays = min(max(fallbackDays, 1), 7)
        self.isFocusMode = isFocusMode
    }
}

struct NudgePersistence: Sendable {
    let fileURL: URL

    static let live: NudgePersistence = {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return NudgePersistence(
            fileURL: baseURL
                .appendingPathComponent("Nudge", isDirectory: true)
                .appendingPathComponent("state.json", isDirectory: false)
        )
    }()

    func load() -> NudgeSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(NudgeSnapshot.self, from: data)
        } catch {
            NSLog("Nudge could not load its saved state: %@", error.localizedDescription)
            return nil
        }
    }

    func save(_ snapshot: NudgeSnapshot) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }
}
