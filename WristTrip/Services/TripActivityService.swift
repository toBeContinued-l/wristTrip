import ActivityKit
import Foundation
import OSLog
import UIKit

enum TripActivityResult {
    case started(UUID)
    case updated(UUID)
    case ended
    case noEligibleTicket
    case draft
    case arrived
    case restartedAfterTimeLimit(UUID)
    case disabled
    case remoteManaged
    case notInAutomaticWindow(Date)
}

/// Refresh local activities after ticket edits and when the iPhone app becomes active.
@MainActor
struct TripActivityService {
    private static let logger = Logger(subsystem: "com.clenson.WristTrip", category: "LiveActivity")
    /// ActivityKit calls can arrive from the scene, a stale-date callback and
    /// a BG task at the same time. Async methods on the main actor may still
    /// interleave at each `await`, so keep one refresh operation in flight.
    private static var refreshInFlight: Task<Void, Never>?
    private static let dismissedTicketIDsKey = "wristTrip.dismissedActivityTicketIDs"
    private static let dismissedJourneysKey = "wristTrip.dismissedActivityJourneys"

    struct DismissedJourney: Codable, Hashable {
        let ticketID: UUID
        let departureAt: Date
        let arrivalAt: Date

        init?(_ ticket: Ticket) {
            guard let departureAt = ticket.plannedDepartureAt,
                  let arrivalAt = ticket.plannedArrivalAt else { return nil }
            self.ticketID = ticket.id
            self.departureAt = departureAt
            self.arrivalAt = arrivalAt
        }
    }

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
    private static let manualActivityMaximumDuration = TripScheduleRules.activityMaximumDuration

    static func endAll() async {
        let previous = refreshInFlight
        let operation = Task { @MainActor in
            await previous?.value
            await endAllUnserialized()
        }
        refreshInFlight = operation
        await operation.value
    }

    static func endActivities(for ticketIDs: Set<UUID>) async {
        guard !ticketIDs.isEmpty else { return }
        let previous = refreshInFlight
        let operation = Task { @MainActor in
            await previous?.value
            for activity in Activity<TripActivityAttributes>.activities
                where ticketIDs.contains(activity.attributes.ticketID) {
                await end(activity, reason: "ticketSnapshotChanged")
            }
        }
        refreshInFlight = operation
        await operation.value
    }

    static func shouldRecordDismissal(state: ActivityState, attributes: TripActivityAttributes,
                                      programmaticEnd: Bool, tickets: [Ticket], now: Date) -> Bool {
        guard state == .dismissed, !programmaticEnd, now < attributes.arrivalAt,
              let ticket = tickets.first(where: { $0.id == attributes.ticketID }) else { return false }
        return ticket.plannedDepartureAt == attributes.departureAt
            && ticket.plannedArrivalAt == attributes.arrivalAt
    }

    static func recordDismissal(attributes: TripActivityAttributes, defaults: UserDefaults = .standard) {
        guard let ticket = TripStore(defaults: defaults).tickets.first(where: { $0.id == attributes.ticketID }),
              ticket.plannedDepartureAt == attributes.departureAt,
              ticket.plannedArrivalAt == attributes.arrivalAt,
              let journey = DismissedJourney(ticket) else { return }
        var journeys = dismissedJourneys(defaults: defaults)
        journeys.insert(journey)
        saveDismissedJourneys(journeys, defaults: defaults)
        logger.info("[ACTIVITY] logTime=\(ClientLogTimestamp.now(), privacy: .public) user dismissed ticket=\(journey.ticketID.uuidString, privacy: .public) departure=\(journey.departureAt, privacy: .public)")
    }

    static func eligibleTickets(_ tickets: [Ticket], requestedTicketID: UUID? = nil,
                                defaults: UserDefaults = .standard) -> [Ticket] {
        var journeys = dismissedJourneys(defaults: defaults)
        let current = Set(tickets.compactMap(DismissedJourney.init))
        journeys.formIntersection(current)
        if let requestedTicketID {
            journeys = journeys.filter { $0.ticketID != requestedTicketID }
        }
        saveDismissedJourneys(journeys, defaults: defaults)
        return tickets.filter { ticket in
            guard let journey = DismissedJourney(ticket) else { return true }
            return !journeys.contains(journey)
        }
    }

    private static func dismissedJourneys(defaults: UserDefaults) -> Set<DismissedJourney> {
        if defaults.object(forKey: dismissedTicketIDsKey) != nil {
            // UUID-only records cannot be attributed to a specific timetable.
            defaults.removeObject(forKey: dismissedTicketIDsKey)
            logger.info("[ACTIVITY] logTime=\(ClientLogTimestamp.now(), privacy: .public) discarded legacy UUID-only dismissal records")
        }
        guard let data = defaults.data(forKey: dismissedJourneysKey),
              let journeys = try? JSONDecoder().decode(Set<DismissedJourney>.self, from: data) else { return [] }
        return journeys
    }

    private static func saveDismissedJourneys(_ journeys: Set<DismissedJourney>, defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(journeys) else { return }
        defaults.set(data, forKey: dismissedJourneysKey)
    }

    private static func endAllUnserialized() async {
        let activities = Activity<TripActivityAttributes>.activities
        let manualPinID = loadManualActivityPin()?.ticketID.uuidString ?? "nil"
        let automaticPinID = loadAutomaticActivityPin()?.ticketID.uuidString ?? "nil"
        logger.info("[ACTIVITY] logTime=\(ClientLogTimestamp.now(), privacy: .public) endAll begin count=\(activities.count) manualPin=\(manualPinID, privacy: .public) automaticPin=\(automaticPinID, privacy: .public)")
        UserDefaults.standard.removeObject(forKey: manualActivityPinKey)
        UserDefaults.standard.removeObject(forKey: automaticActivityPinKey)
        for activity in activities {
            await end(activity, reason: "endAll")
        }
        // ActivityKit can publish a just-created instance while the first
        // end request is being processed. Re-scan once so concurrent refreshes
        // cannot leave a second visible activity behind.
        let lateActivities = Activity<TripActivityAttributes>.activities
            .filter { activity in !activities.contains { $0.id == activity.id } }
        for activity in lateActivities {
            await end(activity, reason: "endAllLateActivity")
        }
        logger.info("[ACTIVITY] logTime=\(ClientLogTimestamp.now(), privacy: .public) endAll requested initial=\(activities.count) late=\(lateActivities.count) remaining=\(Activity<TripActivityAttributes>.activities.count)")
    }

    static func refresh(tickets: [Ticket], selectedTicketID: UUID?, requestedTicketID: UUID? = nil,
                        now: Date = Date(), handoffTicketID: UUID? = nil,
                        startAutomaticallyLocally: Bool = false) async throws -> TripActivityResult {
        // Reserve the next slot before suspending. Every slot reloads persisted
        // tickets, so a callback queued before an edit cannot restore old data.
        let previous = refreshInFlight
        let operation = Task { @MainActor in
            await previous?.value
            try Task.checkCancellation()
            let store = TripStore()
            let currentNow = max(now, Date())
            let currentTickets = store.tickets
            let currentSelection = store.selectedTicketID
            let currentHandoff = handoffTicketID == currentSelection ? handoffTicketID : nil
            if UserDefaults.standard.object(forKey: "wristTrip.liveActivitiesEnabled") as? Bool == false {
                await endAllUnserialized()
                return TripActivityResult.disabled
            }
            return try await performRefresh(tickets: currentTickets, selectedTicketID: currentSelection,
                                            requestedTicketID: requestedTicketID, now: currentNow,
                                            handoffTicketID: currentHandoff,
                                            startAutomaticallyLocally: startAutomaticallyLocally)
        }
        refreshInFlight = Task { _ = try? await operation.value }
        return try await operation.value
    }

    private static func performRefresh(tickets: [Ticket], selectedTicketID: UUID?, requestedTicketID: UUID?,
                                       now: Date, handoffTicketID: UUID?,
                                       startAutomaticallyLocally: Bool) async throws -> TripActivityResult {
        let activities = Activity<TripActivityAttributes>.activities
        let originalTicketCount = tickets.count
        let tickets = eligibleTickets(tickets, requestedTicketID: requestedTicketID)
        var manualPin = loadManualActivityPin()
        var automaticPin = loadAutomaticActivityPin()
        var renewingAfterTimeLimit = false
        var endedAtArrival = false
        let ticketLog = tickets.map { ticket in
            "id=\(ticket.id.uuidString) train=\(ticket.train) status=\(ticket.status(at: now).rawValue) dep=\(String(describing: ticket.plannedDepartureAt)) arr=\(String(describing: ticket.plannedArrivalAt)) valid=\(ticket.isValidJourney)"
        }.joined(separator: " | ")
        let activityLog = activities.map { activity in
            "\(activity.id):\(activity.attributes.ticketID.uuidString)"
        }.joined(separator: ",")
        logger.info("[ACTIVITY] logTime=\(ClientLogTimestamp.now(), privacy: .public) refresh now=\(now, privacy: .public) selected=\(String(describing: selectedTicketID), privacy: .public) requested=\(String(describing: requestedTicketID), privacy: .public) handoff=\(String(describing: handoffTicketID), privacy: .public) inputTickets=\(originalTicketCount) filteredDismissed=\(originalTicketCount - tickets.count) activities=\(activityLog, privacy: .public)")
        logger.info("[ACTIVITY] logTime=\(ClientLogTimestamp.now(), privacy: .public) tickets=\(ticketLog, privacy: .public)")
        logger.info("[ACTIVITY] logTime=\(ClientLogTimestamp.now(), privacy: .public) pins manual=\(String(describing: manualPin), privacy: .public) automatic=\(String(describing: automaticPin), privacy: .public)")
        if let requested = tickets.first(where: { $0.id == requestedTicketID }),
           requested.isValidJourney, let arrival = requested.plannedArrivalAt, now < arrival {
            if manualPin?.ticketID != requested.id {
                manualPin = ManualActivityPin(ticketID: requested.id, startedAt: now)
            }
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
                        await end(activity, reason: "manualPinBoundary.\(reason)")
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
                    await end(activity, reason: "manualPinTicketMissing")
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
                        await end(activity, reason: "automaticPinEightHourRenewal")
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
            guard ticket.isValidJourney, let departure = ticket.plannedDepartureAt,
                  let arrival = ticket.plannedArrivalAt else { return false }
            return ticket.startAt.map { $0.addingTimeInterval(manualActivityMaximumDuration) <= now } == true
                && now < arrival
        }
        let fallback = fallbackCandidates.first { $0.id == selectedTicketID }
            ?? fallbackCandidates.filter { ($0.plannedDepartureAt ?? .distantFuture) <= now }
                .min { ($0.plannedDepartureAt ?? .distantFuture) < ($1.plannedDepartureAt ?? .distantFuture) }
            ?? fallbackCandidates.min { ($0.plannedDepartureAt ?? .distantFuture) < ($1.plannedDepartureAt ?? .distantFuture) }
        if requestedTicketID == nil, manualPin == nil, automaticPin == nil, let fallback {
            for activity in activities where activity.attributes.ticketID == fallback.id {
                await end(activity, reason: "fallbackEightHourRenewal")
            }
            automaticPin = AutomaticActivityPin(ticketID: fallback.id, startedAt: now)
            saveAutomaticActivityPin(automaticPin)
            renewingAfterTimeLimit = true
        }

        // Automatic refreshes must stay dormant until the fixed three-hour window.
        if requestedTicketID == nil, manualPin == nil, handoffTicketID == nil {
            let hasEligibleAutomaticTicket = tickets.contains { ticket in
                guard ticket.isValidJourney, let departure = ticket.plannedDepartureAt,
                      let arrival = ticket.plannedArrivalAt else { return false }
                return TripScheduleRules.isWithinAutomaticWindow(
                    departure: departure, arrival: arrival, now: now)
            }
            logger.info("[ACTIVITY] logTime=\(ClientLogTimestamp.now(), privacy: .public) automatic eligibility=\(hasEligibleAutomaticTicket) now=\(now, privacy: .public)")
            if !hasEligibleAutomaticTicket {
                // Arrival with no next journey must clear both the visible
                // ActivityKit instances and the local renewal pins. This is
                // also safe when the task is delayed or runs more than once.
                await endAllUnserialized()
                logger.info("[ACTIVITY] logTime=\(ClientLogTimestamp.now(), privacy: .public) no eligible automatic ticket; all activities requested to end")
                if endedAtArrival { return .arrived }
                let nextStart = tickets.compactMap { ticket -> Date? in
                    guard ticket.isValidJourney, ticket.plannedArrivalAt != nil,
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
                ticket.id == id && ticket.isValidJourney &&
                    ticket.plannedArrivalAt.map { now < $0 } == true
            }
        } ?? ticketForActivity(tickets: tickets, selectedTicketID: selectedTicketID,
                               requestedTicketID: requestedTicketID,
                               manualActivityTicketID: manualPin?.ticketID,
                               manualActivityStartedAt: manualPin?.startedAt, now: now)
        let selectedTrain = selected?.train ?? "nil"
        logger.info("[ACTIVITY] logTime=\(ClientLogTimestamp.now(), privacy: .public) selected result=\(String(describing: selected?.id), privacy: .public) train=\(selectedTrain, privacy: .public)")

        for activity in activities where activity.attributes.ticketID != selected?.id {
            await end(activity, reason: "differentSelectedTicket")
        }
        guard let selected,
              let departure = selected.plannedDepartureAt,
              let arrival = selected.plannedArrivalAt else {
            // A stale selection or a delayed arrival refresh can reach this
            // branch even when an old ActivityKit instance is still present.
            // End it before reporting the empty state so the lock screen and
            // phone activity stack do not retain the arrived journey.
            await endAllUnserialized()
            logger.info("[ACTIVITY] logTime=\(ClientLogTimestamp.now(), privacy: .public) no selected journey; all activities requested to end")
            if let requested = tickets.first(where: { $0.id == requestedTicketID }) {
                if !requested.isValidJourney { return .draft }
                if let arrival = requested.plannedArrivalAt, now >= arrival { return .arrived }
                return .draft
            }
            return activities.isEmpty ? .noEligibleTicket : .ended
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return .disabled }

        // The iPhone Live Activity is a fixed ticket summary. Its route must
        // remain origin/departure -> destination/arrival after departure too.
        let state = TripActivityAttributes.ContentState(
            plannedStatus: selected.status(at: now).rawValue,
            gate: selected.gate,
            waitingRoom: selected.waitingRoom,
            displayedStation: selected.from,
            displayedTime: departure
        )
        // The activity remains valid while the journey is in progress. Using
        // departure as staleDate would mark a pre-departure activity stale
        // before the background refresh has a chance to publish onboard state.
        let content = ActivityContent(state: state, staleDate: arrival)
        let matching = Activity<TripActivityAttributes>.activities.filter { $0.attributes.matches(selected) }
        logger.info("[ACTIVITY] logTime=\(ClientLogTimestamp.now(), privacy: .public) candidate ticket=\(selected.id.uuidString, privacy: .public) status=\(state.plannedStatus, privacy: .public) matching=\(matching.count) renewing=\(renewingAfterTimeLimit)")
        for activity in activities where activity.attributes.ticketID == selected.id && activity.id != matching.first?.id {
            await end(activity, reason: "duplicateMatchingActivity")
        }
        if !renewingAfterTimeLimit, let existing = matching.first {
            if requestedTicketID == nil, manualPin == nil, automaticPin == nil {
                // A remote push-to-start may have created this activity while
                // the app was suspended. Anchor the local fallback to the
                // planned automatic window until the app can observe a newer
                // activity token.
                automaticPin = AutomaticActivityPin(ticketID: selected.id,
                                                     startedAt: selected.startAt ?? now)
                saveAutomaticActivityPin(automaticPin)
            }
            logger.info("[ACTIVITY] logTime=\(ClientLogTimestamp.now(), privacy: .public) updating existing id=\(existing.id, privacy: .public) ticket=\(selected.id.uuidString, privacy: .public)")
            ActivityPushTokenService.shared.observe(activity: existing, ticketID: selected.id)
            await existing.update(content)
            logger.info("[ACTIVITY] logTime=\(ClientLogTimestamp.now(), privacy: .public) update requested id=\(existing.id, privacy: .public)")
            return .updated(selected.id)
        }
        let inAutomaticWindow = selected.plannedDepartureAt.map {
            TripScheduleRules.isWithinAutomaticWindow(departure: $0, arrival: arrival, now: now)
        } == true
        guard shouldStartLocally(requestedTicketID: requestedTicketID,
                                 handoffTicketID: handoffTicketID,
                                 startAutomaticallyLocally: startAutomaticallyLocally,
                                 inAutomaticWindow: inAutomaticWindow,
                                 isForeground: UIApplication.shared.applicationState == .active) else {
            logger.info("[ACTIVITY] logTime=\(ClientLogTimestamp.now(), privacy: .public) local start deferred ticket=\(selected.id.uuidString, privacy: .public) applicationState=\(UIApplication.shared.applicationState.rawValue)")
            return .remoteManaged
        }
        let attributes = TripActivityAttributes(
            ticketID: selected.id, train: selected.train, origin: selected.from,
            destination: selected.to, departureAt: departure, arrivalAt: arrival,
            timezoneIdentifier: selected.originalTimezoneIdentifier,
            carriage: selected.carriage, seat: selected.seat, seatClass: selected.seatClass,
            fare: selected.fare
        )
        // Local activities that the server may update or end must expose an
        // ActivityKit update token. The signed build must enable Live
        // Activities and the matching push capability before this path runs.
        // Recheck immediately before requesting: an APNs push-to-start may
        // have arrived while the earlier reconciliation awaited an ActivityKit call.
        let racedMatches = Activity<TripActivityAttributes>.activities
            .filter { $0.attributes.matches(selected) }
        if let raced = racedMatches.first {
            let duplicateIDs = Set(Self.duplicateActivityIDs(racedMatches.map(\.id)))
            for duplicate in racedMatches where duplicateIDs.contains(duplicate.id) {
                await end(duplicate, reason: "startRaceDuplicate")
            }
            ActivityPushTokenService.shared.observe(activity: raced, ticketID: selected.id)
            await raced.update(content)
            if requestedTicketID == nil, manualPin == nil {
                saveAutomaticActivityPin(AutomaticActivityPin(ticketID: selected.id,
                                                               startedAt: selected.startAt ?? now))
            }
            return .updated(selected.id)
        }
        guard UIApplication.shared.applicationState == .active else {
            logger.info("[ACTIVITY] logTime=\(ClientLogTimestamp.now(), privacy: .public) local start deferred after reconciliation ticket=\(selected.id.uuidString, privacy: .public)")
            return .remoteManaged
        }
        let created = try requestLocalActivity(attributes: attributes, content: content)
        // ActivityKit and APNs are independent producers. Reconcile once more
        // after request so a remotely-created twin is ended promptly.
        let postRequestMatches = Activity<TripActivityAttributes>.activities
            .filter { $0.attributes.matches(selected) }
        let survivor = postRequestMatches.first ?? created
        let duplicateIDs = Set(Self.duplicateActivityIDs(postRequestMatches.map(\.id), keeping: survivor.id))
        for duplicate in postRequestMatches where duplicateIDs.contains(duplicate.id) {
            await end(duplicate, reason: "startRaceDuplicate")
        }
        if survivor.id != created.id {
            await end(created, reason: "startRaceDuplicate")
            await survivor.update(content)
        }
        ActivityPushTokenService.shared.observe(activity: survivor, ticketID: selected.id)
        logger.info("[ACTIVITY] logTime=\(ClientLogTimestamp.now(), privacy: .public) started id=\(survivor.id, privacy: .public) ticket=\(selected.id.uuidString, privacy: .public) status=\(state.plannedStatus, privacy: .public)")
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
            return try Activity.request(attributes: attributes, content: content,
                                        pushType: .token)
        } catch {
            let nsError = error as NSError
            logger.error("[ACTIVITY] logTime=\(ClientLogTimestamp.now(), privacy: .public) request failed: domain=\(nsError.domain, privacy: .public) code=\(nsError.code) description=\(nsError.localizedDescription, privacy: .public)")
            throw error
        }
    }

    private static func end(_ activity: Activity<TripActivityAttributes>, reason: String) async {
        logger.info("[ACTIVITY] logTime=\(ClientLogTimestamp.now(), privacy: .public) ending id=\(activity.id, privacy: .public) ticket=\(activity.attributes.ticketID.uuidString, privacy: .public) reason=\(reason, privacy: .public)")
        ActivityPushTokenService.shared.markProgrammaticEnd(activityID: activity.id)
        let updatesWillFollow = reason == "ticketSnapshotChanged"
            || reason == "endAll" || reason == "endAllLateActivity"
        ActivityPushTokenService.shared.stopObserving(activityID: activity.id, reconcile: !updatesWillFollow)
        await activity.end(nil, dismissalPolicy: .immediate)
        ActivityPushTokenService.shared.clearProgrammaticEnd(activityID: activity.id)
        logger.info("[ACTIVITY] logTime=\(ClientLogTimestamp.now(), privacy: .public) end requested id=\(activity.id, privacy: .public) reason=\(reason, privacy: .public)")
    }

    nonisolated static func manualActivityEndReason(startedAt: Date, arrivalAt: Date, now: Date) -> ManualActivityEndReason? {
        if now >= arrivalAt { return .arrived }
        if now >= startedAt.addingTimeInterval(TripScheduleRules.activityMaximumDuration) { return .timeLimitReached }
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

    nonisolated static func ticketForActivity(tickets: [Ticket], selectedTicketID: UUID?, requestedTicketID: UUID? = nil,
                                  manualActivityTicketID: UUID? = nil, manualActivityStartedAt: Date? = nil,
                                  now: Date) -> Ticket? {
        if let requested = tickets.first(where: { $0.id == requestedTicketID }),
           requested.isValidJourney, requested.plannedArrivalAt.map({ now < $0 }) == true {
            return requested
        }
        if let manualActivityTicketID,
           let manualActivityStartedAt,
           let manualActivity = tickets.first(where: { $0.id == manualActivityTicketID }),
           let arrival = manualActivity.plannedArrivalAt,
           manualActivity.isValidJourney,
           manualActivityEndReason(startedAt: manualActivityStartedAt, arrivalAt: arrival, now: now) == nil {
            return manualActivity
        }
        let eligible = tickets.filter { ticket in
            guard ticket.isValidJourney, let arrival = ticket.plannedArrivalAt,
                  let start = ticket.startAt else { return false }
            guard ticket.id != manualActivityTicketID else { return false }
            return start <= now && now < arrival
        }
        // An ongoing journey wins over the next train, even when that next train
        // entered its three-hour window or was selected in the watch app.
        let active = eligible.filter { ($0.plannedDepartureAt ?? .distantFuture) <= now }
        let candidates = active.isEmpty ? eligible : active
        return candidates.min {
            let left = $0.plannedDepartureAt ?? .distantFuture
            let right = $1.plannedDepartureAt ?? .distantFuture
            return left == right ? $0.id.uuidString < $1.id.uuidString : left < right
        }
    }

    nonisolated static func duplicateActivityIDs(_ activityIDs: [String], keeping survivorID: String? = nil) -> [String] {
        guard let survivor = survivorID ?? activityIDs.first else { return [] }
        return activityIDs.filter { $0 != survivor }
    }

    nonisolated static func shouldStartLocally(requestedTicketID: UUID?, handoffTicketID: UUID?,
                                                startAutomaticallyLocally: Bool,
                                                inAutomaticWindow: Bool,
                                                isForeground: Bool) -> Bool {
        isForeground && (requestedTicketID != nil
            || (inAutomaticWindow && (startAutomaticallyLocally || handoffTicketID != nil)))
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
