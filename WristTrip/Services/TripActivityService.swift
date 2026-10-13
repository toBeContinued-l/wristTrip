import ActivityKit
import Foundation
import OSLog

enum TripActivityResult {
    case started(UUID)
    case updated(UUID)
    case ended
    case noEligibleTicket
    case draft
    case arrived
    case restartedAfterTimeLimit(UUID)
    case disabled
    case notInAutomaticWindow(Date)
}

/// Refresh local activities after ticket edits and when the iPhone app becomes active.
struct TripActivityService {
    private static let logger = Logger(subsystem: "com.clenson.WristTrip", category: "LiveActivity")

    enum ManualActivityEndReason: Equatable {
        case arrived
        case timeLimitReached
    }

    private struct ManualActivityPin: Codable {
        let ticketID: UUID
        let startedAt: Date
    }

    private struct AutomaticActivityPin: Codable {
        let ticketID: UUID
        let startedAt: Date
    }

    private static let manualActivityPinKey = "wristTrip.manualActivityPin"
    private static let automaticActivityPinKey = "wristTrip.automaticActivityPin"
    private static let manualActivityMaximumDuration: TimeInterval = 8 * 60 * 60

    static func endAll() async {
        UserDefaults.standard.removeObject(forKey: manualActivityPinKey)
        UserDefaults.standard.removeObject(forKey: automaticActivityPinKey)
        for activity in Activity<TripActivityAttributes>.activities {
            Task { @MainActor in ActivityPushTokenService.shared.stopObserving(activityID: activity.id) }
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    static func refresh(tickets: [Ticket], selectedTicketID: UUID?, requestedTicketID: UUID? = nil,
                        now: Date = Date(), handoffTicketID: UUID? = nil) async throws -> TripActivityResult {
        let activities = Activity<TripActivityAttributes>.activities
        var manualPin = loadManualActivityPin()
        var automaticPin = loadAutomaticActivityPin()
        var renewingAfterTimeLimit = false
        var endedAtArrival = false
        if let requested = tickets.first(where: { $0.id == requestedTicketID }),
           !requested.isDraft, let arrival = requested.plannedArrivalAt, now < arrival {
            manualPin = ManualActivityPin(ticketID: requested.id, startedAt: now)
            saveManualActivityPin(manualPin)
        }
        if requestedTicketID != nil {
            // A user-selected activity replaces the automatic renewal chain;
            // leaving the old pin would schedule a stale eight-hour restart.
            automaticPin = nil
            saveAutomaticActivityPin(nil)
        }
        if let pin = manualPin {
            if let pinnedTicket = tickets.first(where: { $0.id == pin.ticketID }),
               let arrival = pinnedTicket.plannedArrivalAt {
                if let reason = manualActivityEndReason(startedAt: pin.startedAt, arrivalAt: arrival, now: now) {
                    for activity in activities where activity.attributes.ticketID == pin.ticketID {
                        await activity.end(nil, dismissalPolicy: .immediate)
                    }
                    if reason == .arrived {
                        manualPin = nil
                        saveManualActivityPin(nil)
                        endedAtArrival = true
                    } else {
                        manualPin = ManualActivityPin(ticketID: pin.ticketID, startedAt: now)
                        saveManualActivityPin(manualPin)
                        renewingAfterTimeLimit = true
                    }
                }
            } else {
                for activity in activities where activity.attributes.ticketID == pin.ticketID {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
                manualPin = nil
                saveManualActivityPin(nil)
            }
        }

        // ActivityKit limits a single activity to eight hours. Keep the
        // selected journey alive by ending the old activity and starting a
        // fresh one at each local fallback boundary while the train is still
        // in progress. The pin also moves the next local boundary forward.
        if manualPin == nil, let pin = automaticPin {
            if let pinnedTicket = tickets.first(where: { $0.id == pin.ticketID }),
               let arrival = pinnedTicket.plannedArrivalAt {
                if now >= arrival {
                    automaticPin = nil
                    saveAutomaticActivityPin(nil)
                } else if now >= pin.startedAt.addingTimeInterval(manualActivityMaximumDuration) {
                    for activity in activities where activity.attributes.ticketID == pin.ticketID {
                        await activity.end(nil, dismissalPolicy: .immediate)
                        Task { @MainActor in ActivityPushTokenService.shared.stopObserving(activityID: activity.id) }
                    }
                    automaticPin = AutomaticActivityPin(ticketID: pin.ticketID, startedAt: now)
                    saveAutomaticActivityPin(automaticPin)
                    renewingAfterTimeLimit = true
                }
            } else {
                automaticPin = nil
                saveAutomaticActivityPin(nil)
            }
        }

        // If the activity was started remotely while the app was suspended,
        // the app may not have observed its first activity token yet. Keep a
        // deterministic departure-based fallback so a long journey still gets
        // a fresh activity when the original eight-hour window expires.
        let fallbackCandidates = tickets.filter { ticket in
            guard !ticket.isDraft, let departure = ticket.plannedDepartureAt,
                  let arrival = ticket.plannedArrivalAt else { return false }
            return departure.addingTimeInterval(manualActivityMaximumDuration) <= now && now < arrival
        }
        let fallback = fallbackCandidates.first { $0.id == selectedTicketID }
            ?? fallbackCandidates.filter { ($0.plannedDepartureAt ?? .distantFuture) <= now }
                .min { ($0.plannedDepartureAt ?? .distantFuture) < ($1.plannedDepartureAt ?? .distantFuture) }
            ?? fallbackCandidates.min { ($0.plannedDepartureAt ?? .distantFuture) < ($1.plannedDepartureAt ?? .distantFuture) }
        if requestedTicketID == nil, manualPin == nil, automaticPin == nil, let fallback {
            for activity in activities where activity.attributes.ticketID == fallback.id {
                await activity.end(nil, dismissalPolicy: .immediate)
                Task { @MainActor in ActivityPushTokenService.shared.stopObserving(activityID: activity.id) }
            }
            automaticPin = AutomaticActivityPin(ticketID: fallback.id, startedAt: now)
            saveAutomaticActivityPin(automaticPin)
            renewingAfterTimeLimit = true
        }

        // Automatic refreshes must stay dormant until the fixed three-hour
        // window. A manual request or an existing manual pin is the only way
        // to show a journey earlier than that window.
        if requestedTicketID == nil, manualPin == nil, handoffTicketID == nil {
            let hasEligibleAutomaticTicket = tickets.contains { ticket in
                guard !ticket.isDraft,
                      let start = ticket.startAt,
                      let arrival = ticket.plannedArrivalAt else { return false }
                return start <= now && now < arrival
            }
            if !hasEligibleAutomaticTicket {
                for activity in activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
                if endedAtArrival { return .arrived }
                let nextStart = tickets.compactMap { ticket -> Date? in
                    guard !ticket.isDraft, ticket.plannedArrivalAt != nil,
                          let start = ticket.startAt, start > now else { return nil }
                    return start
                }.min()
                if let nextStart {
                    return .notInAutomaticWindow(nextStart)
                }
                return activities.isEmpty ? .noEligibleTicket : .ended
            }
        }

        let selected = handoffTicketID.flatMap { id in
            tickets.first { ticket in
                ticket.id == id && !ticket.isDraft &&
                    ticket.plannedDepartureAt != nil &&
                    ticket.plannedArrivalAt.map { now < $0 } == true
            }
        } ?? ticketForActivity(tickets: tickets, selectedTicketID: selectedTicketID,
                               requestedTicketID: requestedTicketID,
                               manualActivityTicketID: manualPin?.ticketID,
                               manualActivityStartedAt: manualPin?.startedAt, now: now)

        for activity in activities where activity.attributes.ticketID != selected?.id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard let selected,
              let departure = selected.plannedDepartureAt,
              let arrival = selected.plannedArrivalAt else {
            if let requested = tickets.first(where: { $0.id == requestedTicketID }) {
                if requested.isDraft || requested.plannedArrivalAt == nil { return .draft }
                if let arrival = requested.plannedArrivalAt, now >= arrival { return .arrived }
                return .draft
            }
            return activities.isEmpty ? .noEligibleTicket : .ended
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return .disabled }

        let state = TripActivityAttributes.ContentState(
            plannedStatus: selected.status(at: now).rawValue,
            gate: selected.gate,
            waitingRoom: selected.waitingRoom
        )
        // The activity remains valid while the journey is in progress. Using
        // departure as staleDate would mark a pre-departure activity stale
        // before the background refresh has a chance to publish onboard state.
        let content = ActivityContent(state: state, staleDate: arrival)
        let matching = activities.filter { $0.attributes.matches(selected) }
        for activity in activities where activity.attributes.ticketID == selected.id && activity.id != matching.first?.id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        if requestedTicketID == selected.id {
            for activity in matching {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        } else if !renewingAfterTimeLimit, let existing = matching.first {
            if requestedTicketID == nil, manualPin == nil, automaticPin == nil {
                // A remote push-to-start may have created this activity while
                // the app was suspended. Anchor the local fallback to the
                // planned automatic window until the app can observe a newer
                // activity token.
                automaticPin = AutomaticActivityPin(ticketID: selected.id,
                                                     startedAt: selected.startAt ?? now)
                saveAutomaticActivityPin(automaticPin)
            }
            await existing.update(content)
            return .updated(selected.id)
        }
        let attributes = TripActivityAttributes(
            ticketID: selected.id, train: selected.train, origin: selected.from,
            destination: selected.to, departureAt: departure, arrivalAt: arrival,
            timezoneIdentifier: selected.originalTimezoneIdentifier,
            carriage: selected.carriage, seat: selected.seat, seatClass: selected.seatClass,
            fare: selected.fare
        )
        // Personal Development Teams cannot provision the APNs capability.
        // A local activity does not need a push type and remains fully usable
        // for lock screen and Smart Stack presentation. Remote scheduling is
        // handled separately when a production APNs-enabled build is used.
        _ = try requestLocalActivity(attributes: attributes, content: content)
        if requestedTicketID == nil, manualPin == nil {
            let pin = AutomaticActivityPin(ticketID: selected.id, startedAt: now)
            saveAutomaticActivityPin(pin)
        }
        return renewingAfterTimeLimit ? .restartedAfterTimeLimit(selected.id) : .started(selected.id)
    }

    private static func requestLocalActivity(
        attributes: TripActivityAttributes,
        content: ActivityContent<TripActivityAttributes.ContentState>
    ) throws -> Activity<TripActivityAttributes> {
        do {
            return try Activity.request(attributes: attributes, content: content, pushType: nil)
        } catch {
            let nsError = error as NSError
            logger.error("Activity request failed: domain=\(nsError.domain, privacy: .public) code=\(nsError.code) description=\(nsError.localizedDescription, privacy: .public)")
            throw error
        }
    }

    static func manualActivityEndReason(startedAt: Date, arrivalAt: Date, now: Date) -> ManualActivityEndReason? {
        if now >= arrivalAt { return .arrived }
        if now >= startedAt.addingTimeInterval(manualActivityMaximumDuration) { return .timeLimitReached }
        return nil
    }

    static func manualActivityDeadline(for ticketID: UUID) -> Date? {
        guard let pin = loadManualActivityPin(), pin.ticketID == ticketID else { return nil }
        return pin.startedAt.addingTimeInterval(manualActivityMaximumDuration)
    }

    static var nextManualActivityDeadline: Date? {
        loadManualActivityPin()?.startedAt.addingTimeInterval(manualActivityMaximumDuration)
    }

    static var nextAutomaticActivityDeadline: Date? {
        loadAutomaticActivityPin()?.startedAt.addingTimeInterval(manualActivityMaximumDuration)
    }

    static func ticketForActivity(tickets: [Ticket], selectedTicketID: UUID?, requestedTicketID: UUID? = nil,
                                  manualActivityTicketID: UUID? = nil, manualActivityStartedAt: Date? = nil,
                                  now: Date) -> Ticket? {
        if let requested = tickets.first(where: { $0.id == requestedTicketID }),
           !requested.isDraft, requested.plannedArrivalAt.map({ now < $0 }) == true {
            return requested
        }
        if let manualActivityTicketID,
           let manualActivityStartedAt,
           let manualActivity = tickets.first(where: { $0.id == manualActivityTicketID }),
           let arrival = manualActivity.plannedArrivalAt,
           !manualActivity.isDraft,
           manualActivityEndReason(startedAt: manualActivityStartedAt, arrivalAt: arrival, now: now) == nil {
            return manualActivity
        }
        let eligible = tickets.filter { ticket in
            guard !ticket.isDraft, let arrival = ticket.plannedArrivalAt,
                  let start = ticket.startAt else { return false }
            guard ticket.id != manualActivityTicketID else { return false }
            return start <= now && now < arrival
        }
        // An ongoing journey wins over the next train, even when that next train
        // entered its three-hour window or was selected in the watch app.
        let active = eligible.filter { ($0.plannedDepartureAt ?? .distantFuture) <= now }
        let candidates = active.isEmpty ? eligible : active
        return candidates.first { $0.id == selectedTicketID }
            ?? candidates.min { ($0.plannedDepartureAt ?? .distantFuture) < ($1.plannedDepartureAt ?? .distantFuture) }
    }

    private static func loadManualActivityPin() -> ManualActivityPin? {
        guard let data = UserDefaults.standard.data(forKey: manualActivityPinKey) else { return nil }
        return try? JSONDecoder().decode(ManualActivityPin.self, from: data)
    }

    private static func saveManualActivityPin(_ pin: ManualActivityPin?) {
        guard let pin, let data = try? JSONEncoder().encode(pin) else {
            UserDefaults.standard.removeObject(forKey: manualActivityPinKey)
            return
        }
        UserDefaults.standard.set(data, forKey: manualActivityPinKey)
    }

    private static func loadAutomaticActivityPin() -> AutomaticActivityPin? {
        guard let data = UserDefaults.standard.data(forKey: automaticActivityPinKey) else { return nil }
        return try? JSONDecoder().decode(AutomaticActivityPin.self, from: data)
    }

    private static func saveAutomaticActivityPin(_ pin: AutomaticActivityPin?) {
        guard let pin, let data = try? JSONEncoder().encode(pin) else {
            UserDefaults.standard.removeObject(forKey: automaticActivityPinKey)
            return
        }
        UserDefaults.standard.set(data, forKey: automaticActivityPinKey)
    }
}

private extension TripActivityAttributes {
    func matches(_ ticket: Ticket) -> Bool {
        ticketID == ticket.id && train == ticket.train && origin == ticket.from
            && destination == ticket.to && departureAt == ticket.plannedDepartureAt
            && arrivalAt == ticket.plannedArrivalAt
            && timezoneIdentifier == ticket.originalTimezoneIdentifier
            && carriage == ticket.carriage && seat == ticket.seat
            && seatClass == ticket.seatClass
            && fare == ticket.fare
    }
}
