import Foundation

/// Rules shared by the iPhone app, Live Activity widget and Watch app.
/// These values describe the planned journey only; they never claim railway
/// operational status such as a delay, boarding call or platform change.
enum TripScheduleStatus: String, Codable, Hashable {
    case upcoming = "待出发"
    case boarding = "临近发车"
    case onboard = "已发车"
    case arrived = "已到站"
}

struct TripDisplayedLeg: Equatable, Codable {
    let station: String
    let time: Date
}

enum TripScheduleRules {
    static let automaticDisplayLeadTime: TimeInterval = 3 * 60 * 60
    static let boardingLeadTime: TimeInterval = 30 * 60
    static let activityMaximumDuration: TimeInterval = 8 * 60 * 60

    static func status(departure: Date?, arrival: Date?, now: Date = Date(),
                       boardingWindow: TimeInterval = boardingLeadTime) -> TripScheduleStatus {
        guard let departure else { return .upcoming }
        if now < departure.addingTimeInterval(-boardingWindow) { return .upcoming }
        if now < departure { return .boarding }
        guard let arrival else { return .onboard }
        return now < arrival ? .onboard : .arrived
    }

    static func displayedLeg(departure: Date, arrival: Date, origin: String,
                             destination: String, now: Date = Date()) -> TripDisplayedLeg {
        now >= departure
            ? TripDisplayedLeg(station: destination, time: arrival)
            : TripDisplayedLeg(station: origin, time: departure)
    }

    static func automaticStart(departure: Date) -> Date {
        departure.addingTimeInterval(-automaticDisplayLeadTime)
    }

    static func isValidJourney(train: String, origin: String, destination: String,
                               departure: Date?, arrival: Date?) -> Bool {
        let requiredText = [train, origin, destination]
            .allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard requiredText, let departure, let arrival else { return false }
        return arrival > departure
    }
}
