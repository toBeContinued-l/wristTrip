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
        selectedTicketID = defaults.string(forKey: selectedKey).flatMap(UUID.init(uuidString:))
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

    /// Prefer the order number; use the route and departure instant for tickets without one.
    func duplicate(of ticket: Ticket) -> Ticket? {
        let order = ticket.orderNumber.replacingOccurrences(of: " ", with: "").uppercased()
        return tickets.first { existing in
            guard existing.id != ticket.id else { return false }
            let existingOrder = existing.orderNumber.replacingOccurrences(of: " ", with: "").uppercased()
            if !order.isEmpty && !existingOrder.isEmpty { return order == existingOrder }
            return existing.train.caseInsensitiveCompare(ticket.train) == .orderedSame
                && existing.from == ticket.from && existing.plannedDepartureAt != nil
                && existing.plannedDepartureAt == ticket.plannedDepartureAt
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

    @discardableResult
    func refreshStatuses(at now: Date) -> Bool {
        var updated = tickets
        var changed = false
        var arrivedTicketIDs = Set<UUID>()
        for index in updated.indices {
            let status = updated[index].status(at: now)
            if updated[index].status != status {
                if status == .arrived {
                    arrivedTicketIDs.insert(updated[index].id)
                }
                updated[index].status = status
                changed = true
            }
        }
        let selectedTicketArrived = selectedTicketID.map { selectedID in
            updated.first(where: { $0.id == selectedID })?.status == .arrived
        } ?? false
        if selectedTicketArrived || (selectedTicketID == nil && !arrivedTicketIDs.isEmpty) {
            // Persist the next Watch choice at the arrival boundary. The
            // arrived ticket remains in history; only the active selection moves.
            let nextSelection = Self.nextWatchTicketID(in: updated, at: now)
            if self.selectedTicketID != nextSelection {
                self.selectedTicketID = nextSelection
                changed = true
            }
        }
        if changed {
            tickets = updated
            persist()
        }
        return changed
    }

    private static func nextWatchTicketID(in tickets: [Ticket], at now: Date) -> UUID? {
        let eligible = tickets.filter { ticket in
            guard ticket.isValidJourney, let start = ticket.startAt,
                  let arrival = ticket.plannedArrivalAt else { return false }
            // Arrival handoff is automatic only inside the three-hour
            // display window. A farther future journey must not overwrite a
            // cleared Watch selection before its own window begins.
            return start <= now && now < arrival
        }
        let active = eligible.filter { ticket in
            guard let departure = ticket.plannedDepartureAt else { return false }
            return departure <= now && now < (ticket.plannedArrivalAt ?? .distantFuture)
        }
        return (active.isEmpty ? eligible : active)
            .min { ($0.plannedDepartureAt ?? .distantFuture) < ($1.plannedDepartureAt ?? .distantFuture) }?.id
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
