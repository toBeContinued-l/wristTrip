import ActivityKit
import Foundation

struct TripActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let plannedStatus: String
        // Optional so activities created before the gate field remain decodable.
        var gate: String? = nil
        var waitingRoom: String? = nil
        /// The route leg calculated by the iPhone at the last refresh. The
        /// iPhone widget keeps the ticket route fixed; the fields remain for
        /// compatibility with older activity payloads and the shared model.
        var displayedStation: String? = nil
        var displayedTime: Date? = nil
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
