import Foundation
import os

private let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "Hangar",
    category: "ConfigStore"
)

actor ConfigStore {
    private let fileURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("Hangar", isDirectory: true)
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        self.fileURL = appFolder.appendingPathComponent("snippets.json")
    }

    func load() -> [SidebarItem] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([SidebarItem].self, from: data)
        } catch {
            logger.error("Failed to load snippets: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func save(_ items: [SidebarItem]) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(items)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Failed to save snippets: \(error.localizedDescription, privacy: .public)")
        }
    }
}
