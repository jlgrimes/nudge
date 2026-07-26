import Foundation

struct InstalledApplicationDescriptor: Identifiable, Hashable, Codable, Sendable {
    let bundleIdentifier: String
    let name: String
    let applicationURL: URL

    var id: String { bundleIdentifier }
}

protocol InstalledApplicationProviding: Sendable {
    func applications() async -> [InstalledApplicationDescriptor]
}

actor InstalledApplicationCatalog: InstalledApplicationProviding {
    static let live = InstalledApplicationCatalog()

    private let searchRoots: [URL]
    private var cachedApplications: [InstalledApplicationDescriptor]?

    init(searchRoots: [URL] = InstalledApplicationCatalog.defaultSearchRoots) {
        self.searchRoots = searchRoots
    }

    func applications() async -> [InstalledApplicationDescriptor] {
        if let cachedApplications {
            return cachedApplications
        }

        let discovered = discoverApplications()
        cachedApplications = discovered
        return discovered
    }

    func refresh() async -> [InstalledApplicationDescriptor] {
        let discovered = discoverApplications()
        cachedApplications = discovered
        return discovered
    }

    private func discoverApplications() -> [InstalledApplicationDescriptor] {
        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey]
        var byBundleIdentifier: [String: InstalledApplicationDescriptor] = [:]

        for root in searchRoots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
            ) else { continue }

            while let candidate = enumerator.nextObject() as? URL {
                guard candidate.pathExtension.lowercased() == "app" else { continue }
                enumerator.skipDescendants()

                guard
                    let bundle = Bundle(url: candidate),
                    let bundleIdentifier = bundle.bundleIdentifier,
                    !bundleIdentifier.isEmpty
                else { continue }

                let displayName = (
                    bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ) ?? (
                    bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ) ?? candidate.deletingPathExtension().lastPathComponent

                let descriptor = InstalledApplicationDescriptor(
                    bundleIdentifier: bundleIdentifier,
                    name: displayName,
                    applicationURL: candidate.standardizedFileURL
                )

                // Earlier roots take precedence, so ~/Applications may override a
                // system-wide copy with the same bundle identifier.
                if byBundleIdentifier[bundleIdentifier] == nil {
                    byBundleIdentifier[bundleIdentifier] = descriptor
                }
            }
        }

        return byBundleIdentifier.values.sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            if comparison == .orderedSame {
                return $0.bundleIdentifier < $1.bundleIdentifier
            }
            return comparison == .orderedAscending
        }
    }

    static var defaultSearchRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true)
        ]
    }
}

struct StaticInstalledApplicationCatalog: InstalledApplicationProviding {
    let values: [InstalledApplicationDescriptor]

    func applications() async -> [InstalledApplicationDescriptor] {
        values
    }
}
