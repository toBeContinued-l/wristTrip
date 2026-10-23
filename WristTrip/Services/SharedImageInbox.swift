import Foundation

enum SharedImageInbox {
    static let groupIdentifier = "group.com.clenson.wristrail"

    enum InboxError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            switch self {
            case .unavailable: "共享图片目录不可用，请检查 App Group 配置"
            }
        }
    }

    private static var directory: URL {
        get throws {
            guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else {
                throw InboxError.unavailable
            }
            return container.appendingPathComponent("SharedImages", isDirectory: true)
        }
    }

    @discardableResult
    static func save(_ data: Data) throws -> URL {
        let directory = try directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("image")
        try data.write(to: destination, options: .atomic)
        return destination
    }

    static func pendingImageURLs() throws -> [URL] {
        let directory = try directory
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])
        return urls.filter { $0.pathExtension == "image" }.sorted {
            let first = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let second = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return first > second
        }
    }

    static func remove(_ url: URL) throws {
        let directory = try directory
        guard url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else { return }
        try FileManager.default.removeItem(at: url)
    }
}
