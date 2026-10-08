import Foundation
import Combine

@MainActor
final class TripStore: ObservableObject {
    @Published private(set) var tickets: [Ticket] = []
    @Published private(set) var selectedTicketID: UUID?

    private let defaults: UserDefaults
    private let ticketsKey: String
    private let selectedKey: String

    init(defaults: UserDefaults = .standard, key: String = "wristTrip.tickets") {
        self.defaults = defaults
        self.ticketsKey = key
        self.selectedKey = "\(key).selectedTicketID"
        load()
    }

    func load() {
        if let data = defaults.data(forKey: ticketsKey),
           let decoded = try? JSONDecoder().decode([Ticket].self, from: data) {
            tickets = decoded
        } else {
            tickets = []
        }
        if let rawID = defaults.string(forKey: selectedKey) {
            selectedTicketID = UUID(uuidString: rawID)
        }
        pruneSelection()
    }

    @discardableResult
    func add(_ ticket: Ticket) -> Ticket {
        tickets.append(ticket)
        persist()
        return ticket
    }

    func update(_ ticket: Ticket) {
        guard let index = tickets.firstIndex(where: { $0.id == ticket.id }) else {
            add(ticket)
            return
        }
        tickets[index] = ticket
        persist()
    }

    /// Finds an imported ticket with the same train, departure instant, and origin station.
    /// Callers can ask the user whether to update it or save another record.
    func duplicate(of ticket: Ticket) -> Ticket? {
        tickets.first { existing in
            existing.id != ticket.id && existing.train.caseInsensitiveCompare(ticket.train) == .orderedSame
                && existing.from == ticket.from && existing.plannedDepartureAt == ticket.plannedDepartureAt
        }
    }

    func delete(id: UUID) {
        tickets.removeAll { $0.id == id }
        if selectedTicketID == id { selectedTicketID = nil }
        persist()
    }

    func removeAll() {
        tickets.removeAll()
        selectedTicketID = nil
        persist()
    }

    func selectForWatch(id: UUID?) {
        selectedTicketID = id
        persist()
    }

    func sortedTickets() -> [Ticket] {
        tickets.sorted { lhs, rhs in
            switch (lhs.plannedDepartureAt, rhs.plannedDepartureAt) {
            case let (left?, right?): return left < right
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs.date < rhs.date
            }
        }
    }

    /// Chooses the explicitly pinned watch ticket first, then an active ticket, then the nearest future ticket.
    func currentTicket(at now: Date = Date()) -> Ticket? {
        if let selectedTicketID,
           let selected = tickets.first(where: { $0.id == selectedTicketID && $0.status(at: now) != .arrived }) {
            return selected
        }
        let active = tickets
            .filter { ticket in
                guard let departure = ticket.plannedDepartureAt, let arrival = ticket.plannedArrivalAt else { return false }
                return departure <= now && now < arrival
            }
            .sorted { ($0.plannedDepartureAt ?? .distantFuture) < ($1.plannedDepartureAt ?? .distantFuture) }
        if let active = active.first { return active }
        return tickets
            .filter { ($0.plannedDepartureAt ?? .distantPast) > now }
            .min { ($0.plannedDepartureAt ?? .distantFuture) < ($1.plannedDepartureAt ?? .distantFuture) }
    }

    func hasConflict(_ ticket: Ticket) -> Bool {
        conflictingTickets(for: ticket).isEmpty == false
    }

    func conflictingTickets(for ticket: Ticket) -> [Ticket] {
        guard let departure = ticket.plannedDepartureAt, let arrival = ticket.plannedArrivalAt else { return [] }
        return tickets.filter { other in
            guard other.id != ticket.id, let otherDeparture = other.plannedDepartureAt, let otherArrival = other.plannedArrivalAt else { return false }
            return departure < otherArrival && otherDeparture < arrival
        }
    }

    private func pruneSelection() {
        if let selectedTicketID, tickets.contains(where: { $0.id == selectedTicketID }) == false {
            self.selectedTicketID = nil
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(tickets) else { return }
        defaults.set(data, forKey: ticketsKey)
        if let selectedTicketID {
            defaults.set(selectedTicketID.uuidString, forKey: selectedKey)
        } else {
            defaults.removeObject(forKey: selectedKey)
        }
    }
}
