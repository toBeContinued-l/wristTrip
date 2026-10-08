import Foundation

enum SharedImageInbox {
    static let groupIdentifier = "group.com.clenson.WristTrip"

    enum InboxError: LocalizedError {
        case unavailable
        case invalidImage

        var errorDescription: String? {
            switch self {
            case .unavailable: "共享图片目录不可用，请检查 App Group 配置"
            case .invalidImage: "分享内容不是可识别的图片"
            }
        }
    }

    private static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?
            .appendingPathComponent("SharedImages", isDirectory: true)
    }

    @discardableResult
    static func save(_ data: Data) throws -> URL {
        guard let directory else { throw InboxError.unavailable }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("image")
        try data.write(to: destination, options: .atomic)
        return destination
    }

    static func pendingImageURLs() -> [URL] {
        guard let directory,
              let urls = try? FileManager.default.contentsOfDirectory(at: directory,
                  includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]) else { return [] }
        return urls.filter { $0.pathExtension == "image" }.sorted {
            let first = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let second = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return first < second
        }
    }

    static func remove(_ url: URL) {
        guard let directory, url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
