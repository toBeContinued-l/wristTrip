import Foundation

enum ClientLogTimestamp {
    static func now() -> String {
        Date().formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true, timeZone: .gmt))
    }
}
