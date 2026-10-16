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
    /// Status and displayed leg are persisted with each refresh so the watch
    /// can render the same snapshot that was calculated on iPhone offline.
    let plannedStatus: String
    let displayedStation: String
    let displayedTime: Date

    private enum CodingKeys: String, CodingKey {
        case id, train, departureAt, arrivalAt, timezoneIdentifier, origin, destination
        case carriage, seat, seatClass, fare, waitingRoom, gate, sourceText, fieldSources
        case updatedAt, plannedStatus, displayedStation, displayedTime
    }

    init(id: UUID, train: String, departureAt: Date, arrivalAt: Date?, timezoneIdentifier: String,
         origin: String, destination: String, carriage: String, seat: String, seatClass: String?,
         fare: String?, waitingRoom: String, gate: String, sourceText: String,
         fieldSources: [String: String], updatedAt: Date, plannedStatus: String? = nil,
         displayedStation: String? = nil, displayedTime: Date? = nil) {
        self.id = id
        self.train = train
        self.departureAt = departureAt
        self.arrivalAt = arrivalAt
        self.timezoneIdentifier = timezoneIdentifier
        self.origin = origin
        self.destination = destination
        self.carriage = carriage
        self.seat = seat
        self.seatClass = seatClass
        self.fare = fare
        self.waitingRoom = waitingRoom
        self.gate = gate
        self.sourceText = sourceText
        self.fieldSources = fieldSources
        self.updatedAt = updatedAt
        let status = TripScheduleRules.status(departure: departureAt, arrival: arrivalAt)
        let leg = TripScheduleRules.displayedLeg(departure: departureAt,
                                                  arrival: arrivalAt ?? departureAt,
                                                  origin: origin, destination: destination)
        self.plannedStatus = plannedStatus ?? status.rawValue
        self.displayedStation = displayedStation ?? leg.station
        self.displayedTime = displayedTime ?? leg.time
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        train = try values.decode(String.self, forKey: .train)
        departureAt = try values.decode(Date.self, forKey: .departureAt)
        arrivalAt = try values.decodeIfPresent(Date.self, forKey: .arrivalAt)
        timezoneIdentifier = try values.decode(String.self, forKey: .timezoneIdentifier)
        origin = try values.decode(String.self, forKey: .origin)
        destination = try values.decode(String.self, forKey: .destination)
        carriage = try values.decode(String.self, forKey: .carriage)
        seat = try values.decode(String.self, forKey: .seat)
        seatClass = try values.decodeIfPresent(String.self, forKey: .seatClass)
        fare = try values.decodeIfPresent(String.self, forKey: .fare)
        waitingRoom = try values.decode(String.self, forKey: .waitingRoom)
        gate = try values.decode(String.self, forKey: .gate)
        sourceText = try values.decode(String.self, forKey: .sourceText)
        fieldSources = try values.decode([String: String].self, forKey: .fieldSources)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        let status = TripScheduleRules.status(departure: departureAt, arrival: arrivalAt)
        let leg = TripScheduleRules.displayedLeg(departure: departureAt,
                                                  arrival: arrivalAt ?? departureAt,
                                                  origin: origin, destination: destination)
        plannedStatus = try values.decodeIfPresent(String.self, forKey: .plannedStatus) ?? status.rawValue
        displayedStation = try values.decodeIfPresent(String.self, forKey: .displayedStation) ?? leg.station
        displayedTime = try values.decodeIfPresent(Date.self, forKey: .displayedTime) ?? leg.time
    }

    var timezone: TimeZone {
        TimeZone(identifier: timezoneIdentifier) ?? TimeZone(identifier: "Asia/Shanghai")!
    }

    func status(at now: Date) -> String {
        TripScheduleRules.status(departure: departureAt, arrival: arrivalAt, now: now).rawValue
    }

    func displayedLeg(at now: Date) -> TripDisplayedLeg {
        TripScheduleRules.displayedLeg(departure: departureAt, arrival: arrivalAt ?? departureAt,
                                       origin: origin, destination: destination, now: now)
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
