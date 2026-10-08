import ActivityKit
import Foundation

struct TripActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let plannedStatus: String
    }

    let ticketID: UUID
    let train: String
    let origin: String
    let destination: String
    let departureAt: Date
    let arrivalAt: Date
    let timezoneIdentifier: String
    let carriage: String
    let seat: String
    let seatClass: String
    let fare: String
}
