import Foundation

enum ClientLogTimestamp {
    static func now() -> String { format(Date()) }

    static func format(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(
            includingFractionalSeconds: true, timeZone: TimeZone(identifier: "Asia/Shanghai")!))
    }
}
