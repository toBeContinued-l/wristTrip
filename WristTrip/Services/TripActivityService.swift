import ActivityKit
import Foundation

enum TripActivityResult {
    case started(UUID)
    case updated(UUID)
    case ended
    case noEligibleTicket
    case draft
    case notInWindow(Date)
    case arrived
    case timeLimitReached
    case disabled
    case demoActive
}

/// Call from the iPhone app after ticket edits and when it becomes active.
/// Future starts and guaranteed scheduled transitions require a push service.
struct TripActivityService {
    static func startDemo(ticket: Ticket, now: Date = Date()) async throws -> TripActivityResult {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return .disabled }
        await endAll()
        let expiresAt = now.addingTimeInterval(15 * 60)
        let attributes = TripActivityAttributes(
            ticketID: ticket.id, train: ticket.train.isEmpty ? "演示车次" : ticket.train,
            origin: ticket.from.isEmpty ? "出发站" : ticket.from,
            destination: ticket.to.isEmpty ? "到达站" : ticket.to,
            departureAt: now, arrivalAt: expiresAt,
            timezoneIdentifier: ticket.originalTimezoneIdentifier,
            carriage: ticket.carriage, seat: ticket.seat, seatClass: ticket.seatClass,
            fare: ticket.fare, demoExpiresAt: expiresAt
        )
        let content = ActivityContent(
            state: TripActivityAttributes.ContentState(plannedStatus: "演示"),
            staleDate: expiresAt
        )
        _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
        return .demoActive
    }

    static func endAll() async {
        for activity in Activity<TripActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    static func refresh(tickets: [Ticket], selectedTicketID: UUID?, requestedTicketID: UUID? = nil, now: Date = Date()) async throws -> TripActivityResult {
        let activities = Activity<TripActivityAttributes>.activities
        if let demo = activities.first(where: { ($0.attributes.demoExpiresAt ?? .distantPast) > now }) {
            for activity in activities where activity.id != demo.id {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            return .demoActive
        }
        let selected = ticketForActivity(tickets: tickets, selectedTicketID: selectedTicketID, now: now)

        for activity in activities where activity.attributes.ticketID != selected?.id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard let selected,
              let departure = selected.plannedDepartureAt,
              let arrival = selected.plannedArrivalAt else {
            if let requested = tickets.first(where: { $0.id == requestedTicketID }) {
                if requested.isDraft || requested.plannedArrivalAt == nil { return .draft }
                if let start = requested.startAt, now < start { return .notInWindow(start) }
                if let arrival = requested.plannedArrivalAt, now >= arrival { return .arrived }
                return .timeLimitReached
            }
            return activities.isEmpty ? .noEligibleTicket : .ended
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return .disabled }

        let state = TripActivityAttributes.ContentState(plannedStatus: selected.status(at: now).rawValue)
        let nextBoundary = now < departure ? departure : arrival
        let content = ActivityContent(state: state, staleDate: nextBoundary)
        let matching = activities.filter { $0.attributes.matches(selected) }
        for activity in activities where activity.attributes.ticketID == selected.id && activity.id != matching.first?.id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        if let existing = matching.first {
            await existing.update(content)
            return .updated(selected.id)
        }
        let attributes = TripActivityAttributes(
            ticketID: selected.id, train: selected.train, origin: selected.from,
            destination: selected.to, departureAt: departure, arrivalAt: arrival,
            timezoneIdentifier: selected.originalTimezoneIdentifier,
            carriage: selected.carriage, seat: selected.seat, seatClass: selected.seatClass,
            fare: selected.fare, demoExpiresAt: nil
        )
        _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
        return .started(selected.id)
    }

    static func ticketForActivity(tickets: [Ticket], selectedTicketID: UUID?, now: Date) -> Ticket? {
        let eligible = tickets.filter { ticket in
            guard !ticket.isDraft, let departure = ticket.plannedDepartureAt,
                  let arrival = ticket.plannedArrivalAt else { return false }
            let start = departure.addingTimeInterval(-3 * 60 * 60)
            return start <= now && now < min(arrival, start.addingTimeInterval(8 * 60 * 60))
        }
        // An ongoing journey wins over the next train, even when that next train
        // entered its three-hour window or was selected in the watch app.
        let active = eligible.filter { ($0.plannedDepartureAt ?? .distantFuture) <= now }
        let candidates = active.isEmpty ? eligible : active
        return candidates.first { $0.id == selectedTicketID }
            ?? candidates.min { ($0.plannedDepartureAt ?? .distantFuture) < ($1.plannedDepartureAt ?? .distantFuture) }
    }
}

private extension TripActivityAttributes {
    func matches(_ ticket: Ticket) -> Bool {
        demoExpiresAt == nil && ticketID == ticket.id && train == ticket.train && origin == ticket.from
            && destination == ticket.to && departureAt == ticket.plannedDepartureAt
            && arrivalAt == ticket.plannedArrivalAt
            && timezoneIdentifier == ticket.originalTimezoneIdentifier
            && carriage == ticket.carriage && seat == ticket.seat
            && seatClass == ticket.seatClass
            && fare == ticket.fare
    }
}
