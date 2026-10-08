import Foundation

/// The complete, privacy-limited state sent to the paired watch. Both targets compile this file.
struct WatchTicketSnapshot: Codable {
    static let schemaVersion = 1

    let schemaVersion: Int
    let id: UUID
    let generatedAt: Date
    let selectedTicketID: UUID?
    let tickets: [WatchTicket]

    init(selectedTicketID: UUID?, tickets: [WatchTicket]) {
        self.schemaVersion = Self.schemaVersion
        self.id = UUID()
        self.generatedAt = Date()
        self.selectedTicketID = selectedTicketID
        self.tickets = tickets
    }
}

struct WatchTicket: Identifiable, Codable {
    let id: UUID
    let train: String
    let departureAt: Date
    let arrivalAt: Date?
    let timezoneIdentifier: String
    let origin: String
    let destination: String
    let carriage: String
    let seat: String
    let seatClass: String?
    let fare: String?
    let waitingRoom: String
    let gate: String
    let sourceText: String
    let fieldSources: [String: String]
    let updatedAt: Date

    var timezone: TimeZone {
        TimeZone(identifier: timezoneIdentifier) ?? TimeZone(identifier: "Asia/Shanghai")!
    }

    func status(at now: Date) -> String {
        if now < departureAt.addingTimeInterval(-30 * 60) { return "待出发" }
        if now < departureAt { return "临近发车" }
        guard let arrivalAt else { return "已发车" }
        return now < arrivalAt ? "已发车" : "已到站"
    }

    static func display(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

struct WatchSyncAcknowledgement: Codable {
    let schemaVersion: Int
    let snapshotID: UUID
    let storedAt: Date
}
