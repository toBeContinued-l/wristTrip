import Foundation
import Combine

@MainActor
final class TripStore: ObservableObject {
    @Published private(set) var tickets: [Ticket] = []
    @Published private(set) var selectedTicketID: UUID?
    @Published private(set) var stationInfoRevision = 0

    private let defaults: UserDefaults
    private let ticketsKey: String
    private let selectedKey: String
    private let stationInfoClient: TrainStationInfoProviding
    private struct StationInfoTask {
        let id: UUID
        let request: StationInfoRequest
        let task: Task<Void, Never>
    }
    private var stationInfoTasks: [UUID: StationInfoTask] = [:]
    private var stationInfoLastRequestedAt: [UUID: Date] = [:]
    private let stationInfoMinimumInterval: TimeInterval = 60

    init(defaults: UserDefaults = .standard, key: String = "wristTrip.tickets",
         stationInfoClient: TrainStationInfoProviding = APIClient.shared) {
        self.defaults = defaults
        self.ticketsKey = key
        self.selectedKey = "\(key).selectedTicketID"
        self.stationInfoClient = stationInfoClient
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
        refreshStationInfo(for: ticket.id, force: true)
        return ticket
    }

    func update(_ ticket: Ticket) {
        guard let index = tickets.firstIndex(where: { $0.id == ticket.id }) else {
            add(ticket)
            return
        }
        let oldTicket = tickets[index]
        tickets[index] = ticket
        persist()
        if oldTicket.train.caseInsensitiveCompare(ticket.train) != .orderedSame
            || oldTicket.date != ticket.date || oldTicket.from != ticket.from {
            refreshStationInfo(for: ticket.id, force: true)
        } else if ticket.stationInfoUpdatedAt == nil {
            refreshStationInfo(for: ticket.id)
        }
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
        stationInfoTasks[id]?.task.cancel()
        stationInfoTasks[id] = nil
        stationInfoLastRequestedAt[id] = nil
        tickets.removeAll { $0.id == id }
        if selectedTicketID == id { selectedTicketID = nil }
        persist()
    }

    func removeAll() {
        stationInfoTasks.values.forEach { $0.task.cancel() }
        stationInfoTasks.removeAll()
        stationInfoLastRequestedAt.removeAll()
        tickets.removeAll()
        selectedTicketID = nil
        persist()
    }

    func selectForWatch(id: UUID?) {
        selectedTicketID = id
        persist()
    }

    /// Starts a deduplicated, low-frequency live station query. All failures
    /// are intentionally silent here: the saved ticket remains authoritative
    /// until a successful matched response arrives.
    func refreshStationInfo(for ticketID: UUID, force: Bool = false) {
        guard let ticket = tickets.first(where: { $0.id == ticketID }),
              let request = stationInfoRequest(for: ticket) else { return }
        if let current = stationInfoTasks[ticketID] {
            if current.request == request { return }
            current.task.cancel()
            stationInfoTasks[ticketID] = nil
        }
        if !force, let last = stationInfoLastRequestedAt[ticketID],
           Date().timeIntervalSince(last) < stationInfoMinimumInterval { return }
        stationInfoLastRequestedAt[ticketID] = Date()
        let client = stationInfoClient
        let taskID = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let response = try await client.getTrainStationInfo(
                    departureDate: request.date, departureStation: request.station,
                    trainNo: request.train)
                if !Task.isCancelled {
                    self.applyStationInfo(response, to: ticketID,
                                          requestedDate: request.date,
                                          requestedStation: request.station,
                                          requestedTrain: request.train)
                }
            } catch {
                // Parameter and server errors are handled by APIClient's
                // policy. Keeping this path quiet preserves local values.
            }
            if self.stationInfoTasks[ticketID]?.id == taskID {
                self.stationInfoTasks[ticketID] = nil
            }
        }
        stationInfoTasks[ticketID] = StationInfoTask(id: taskID, request: request, task: task)
    }

    func refreshStationInfoAndWait(for ticketID: UUID, force: Bool = true) async {
        refreshStationInfo(for: ticketID, force: force)
        await stationInfoTasks[ticketID]?.task.value
    }

    private struct StationInfoRequest: Equatable {
        let date: String
        let station: String
        let train: String
    }

    private func stationInfoRequest(for ticket: Ticket) -> StationInfoRequest? {
        let station = ticket.from.trimmingCharacters(in: .whitespacesAndNewlines)
        let train = ticket.train.trimmingCharacters(in: .whitespacesAndNewlines)
        let date = ticket.date.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !station.isEmpty, !train.isEmpty, APIClient.isValidDate(date) else { return nil }
        return StationInfoRequest(date: date, station: station, train: train)
    }

    private func applyStationInfo(_ response: TrainStationInfoResponse, to ticketID: UUID,
                                  requestedDate: String, requestedStation: String,
                                  requestedTrain: String) {
        guard response.code == 0, let data = response.data, data.matched,
              let index = tickets.firstIndex(where: { $0.id == ticketID }) else { return }
        var ticket = tickets[index]
        // Ignore a late response for an edited ticket. The next edit starts a
        // new request and must not be overwritten by the old one.
        guard ticket.date.trimmingCharacters(in: .whitespacesAndNewlines) == requestedDate,
              ticket.from.trimmingCharacters(in: .whitespacesAndNewlines) == requestedStation,
              ticket.train.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(requestedTrain) == .orderedSame else { return }
        var changed = false
        let waitingRoom = data.waitingRoom.trimmingCharacters(in: .whitespacesAndNewlines)
        let gate = data.gate.trimmingCharacters(in: .whitespacesAndNewlines)
        if !waitingRoom.isEmpty, ticket.waitingRoom != waitingRoom {
            ticket.waitingRoom = waitingRoom
            changed = true
        }
        if !gate.isEmpty, ticket.gate != gate {
            ticket.gate = gate
            ticket.normalizedGates = Ticket.normalizeGates(gate)
            changed = true
        }
        let checkingPort = data.checkingPort.trimmingCharacters(in: .whitespacesAndNewlines)
        if ticket.checkingPort != checkingPort { ticket.checkingPort = checkingPort; changed = true }
        if ticket.waitingState != data.waitingState { ticket.waitingState = data.waitingState; changed = true }
        if ticket.liveDepartTime != data.departTime { ticket.liveDepartTime = data.departTime; changed = true }
        if ticket.liveDayDiff != data.dayDiff { ticket.liveDayDiff = data.dayDiff; changed = true }
        if changed {
            ticket.stationInfoUpdatedAt = Date()
            ticket.updatedAt = Date()
            tickets[index] = ticket
            persist()
            stationInfoRevision += 1
        }
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
