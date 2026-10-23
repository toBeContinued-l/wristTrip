import BackgroundTasks
import Foundation
import OSLog

/// iOS chooses when suspended apps can refresh; these boundaries are requests,
/// not exact timers. Foreground refreshes use the same persisted status rules.
@MainActor
enum TripBackgroundRefreshService {
    static let taskIdentifier = "com.clenson.WristTrip.refresh"
    static let logger = Logger(subsystem: "com.clenson.WristTrip", category: "BackgroundRefresh")
    private static var submittedRequestDate: Date?
    private static var hasReconciledScheduler = false
    private static var hasRegistered = false
    private static let retryDelay: TimeInterval = 15 * 60
    private static let maximumConsecutiveRetries = 3
    private static let retryCountKey = "wristTrip.backgroundRefreshRetryCount"

    static func register() {
        guard !hasRegistered else {
            logger.debug("[BG] logTime=\(ClientLogTimestamp.now(), privacy: .public) registration already completed")
            return
        }
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                logger.error("[BG] logTime=\(ClientLogTimestamp.now(), privacy: .public) received unexpected task type: \(String(describing: type(of: task)), privacy: .public)")
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in run(refreshTask) }
        }
        hasRegistered = registered
        if registered {
            logger.info("[BG] logTime=\(ClientLogTimestamp.now(), privacy: .public) registration succeeded for \(taskIdentifier, privacy: .public)")
        } else {
            logger.error("[BG] logTime=\(ClientLogTimestamp.now(), privacy: .public) registration failed for \(taskIdentifier, privacy: .public)")
        }
    }

    static func schedule(tickets: [Ticket]? = nil, now: Date = Date(), retryAfterFailure: Bool = false) {
        let consecutiveFailures = retryAfterFailure
            ? UserDefaults.standard.integer(forKey: retryCountKey) + 1
            : UserDefaults.standard.integer(forKey: retryCountKey)
        if retryAfterFailure { UserDefaults.standard.set(consecutiveFailures, forKey: retryCountKey) }
        let sourceTickets = tickets ?? TripStore().tickets
        let requestDate = nextRequestDate(tickets: sourceTickets, after: now,
                                          manualDeadline: TripActivityService.nextManualActivityDeadline,
                                          retryAfterFailure: retryAfterFailure && consecutiveFailures <= maximumConsecutiveRetries)
        if retryAfterFailure && consecutiveFailures > maximumConsecutiveRetries {
            logger.error("[BG] logTime=\(ClientLogTimestamp.now(), privacy: .public) retry limit reached; waiting for next journey boundary or app launch")
        }
        logger.info("[BG] logTime=\(ClientLogTimestamp.now(), privacy: .public) reconcile schedule now=\(now, privacy: .public) tickets=\(sourceTickets.count) retry=\(retryAfterFailure) next=\(String(describing: requestDate), privacy: .public) submitted=\(String(describing: submittedRequestDate), privacy: .public)")
        guard !hasReconciledScheduler || requestDate != submittedRequestDate else {
            logger.debug("[BG] logTime=\(ClientLogTimestamp.now(), privacy: .public) skipped duplicate request")
            return
        }
        // Replace the request only when an edit changes its next boundary.
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        logger.debug("[BG] logTime=\(ClientLogTimestamp.now(), privacy: .public) cancelled previous request before reconciliation")
        hasReconciledScheduler = true
        submittedRequestDate = nil
        guard let requestDate else {
            logger.info("[BG] logTime=\(ClientLogTimestamp.now(), privacy: .public) no future boundary; no request submitted")
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = requestDate
        do {
            try BGTaskScheduler.shared.submit(request)
            submittedRequestDate = requestDate
            logger.info("[BG] logTime=\(ClientLogTimestamp.now(), privacy: .public) request submitted earliestBeginDate=\(requestDate, privacy: .public)")
            logPendingRequests()
        } catch {
            logger.error("[BG] logTime=\(ClientLogTimestamp.now(), privacy: .public) scheduling failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Pending requests are diagnostic only. Their presence means iOS accepted
    /// the request; it does not mean the task will run at earliestBeginDate.
    private static func logPendingRequests() {
        let identifier = taskIdentifier
        BGTaskScheduler.shared.getPendingTaskRequests { requests in
            let matching = requests.filter { $0.identifier == identifier }
            let dates = matching.map { String(describing: $0.earliestBeginDate) }.joined(separator: ",")
            Task { @MainActor in
                logger.info("[BG] logTime=\(ClientLogTimestamp.now(), privacy: .public) pending requests count=\(matching.count) earliest=\(dates, privacy: .public)")
            }
        }
    }

    private static func run(_ task: BGAppRefreshTask) {
        submittedRequestDate = nil
        let startedAt = Date()
        logger.info("[BG] logTime=\(ClientLogTimestamp.now(), privacy: .public) task started at \(startedAt, privacy: .public)")
        let completion = RefreshTaskCompletion(task: task)
        let work = Task { @MainActor in
            let success = await refresh(
                performActivityHandoff: true,
                updatePushSchedule: { tickets, selectedID, enabled in
                    ActivityPushTokenService.shared.updateSchedule(
                        tickets: tickets,
                        selectedTicketID: selectedID,
                        enabled: enabled)
                })
            logger.info("[BG] logTime=\(ClientLogTimestamp.now(), privacy: .public) task work finished success=\(success) elapsed=\(Date().timeIntervalSince(startedAt), privacy: .public)s")
            completion.finish(success: success && !Task.isCancelled)
        }
        task.expirationHandler = {
            work.cancel()
            Task { @MainActor in
                logger.error("[BG] logTime=\(ClientLogTimestamp.now(), privacy: .public) task expired at \(Date(), privacy: .public) elapsed=\(Date().timeIntervalSince(startedAt), privacy: .public)s")
                completion.finish(success: false)
            }
        }
    }

    static func recordSuccessfulRefresh() {
        UserDefaults.standard.removeObject(forKey: retryCountKey)
    }

    /// Persist before updating external displays. Hooks allow boundary tests to
    /// exercise the actual background path without ActivityKit or a paired watch.
    static func refresh(
        now: Date = Date(), defaults: UserDefaults = .standard,
        performActivityHandoff: Bool = false,
        updateActivity: ([Ticket], UUID?, Date, Bool) async throws -> Void = { tickets, selectedID, now, enabled in
            if enabled {
                // A suspended/background refresh reconciles existing remote
                // activities only. New automatic starts are owned by APNs;
                // foreground saves pass startAutomaticallyLocally explicitly.
                _ = try await TripActivityService.refresh(tickets: tickets, selectedTicketID: selectedID,
                                                           now: now, startAutomaticallyLocally: false)
            } else {
                await TripActivityService.endAll()
            }
        },
        syncWatch: ([Ticket], UUID?) async -> Bool = { tickets, selectedID in
            await WatchSyncService.shared.queueSnapshot(tickets: tickets, selectedTicketID: selectedID,
                                                         now: Date())
        },
        updatePushSchedule: (([Ticket], UUID?, Bool) -> Void)? = nil
    ) async -> Bool {
        guard !Task.isCancelled else { return false }
        let store = TripStore(defaults: defaults)
        let previousTickets = store.tickets
        let previousSelection = store.selectedTicketID
        let changed = store.refreshStatuses(at: now)
        let selectedID = store.selectedTicketID
        let ticketLog = store.tickets.map { ticket in
            "id=\(ticket.id.uuidString) train=\(ticket.train) persisted=\(ticket.status.rawValue) calculated=\(ticket.status(at: now).rawValue) dep=\(String(describing: ticket.plannedDepartureAt)) arr=\(String(describing: ticket.plannedArrivalAt))"
        }.joined(separator: " | ")
        // Carry the selection change into ActivityKit only when the next
        // journey entered the same automatic three-hour display window.
        let arrivedAtBoundary = previousTickets.contains { ticket in
            guard let arrival = ticket.plannedArrivalAt, ticket.status != .arrived else { return false }
            return now >= arrival
        }
        let handoffTicketID: UUID? = {
            guard arrivedAtBoundary, selectedID != previousSelection,
                  let next = store.tickets.first(where: { $0.id == selectedID }),
                  next.isValidJourney, let start = next.startAt,
                  let arrival = next.plannedArrivalAt, start <= now, now < arrival else {
                return nil
            }
            return next.id
        }()
        logger.info("[BG] logTime=\(ClientLogTimestamp.now(), privacy: .public) refresh now=\(now, privacy: .public) tickets=\(ticketLog, privacy: .public)")
        logger.info("[BG] logTime=\(ClientLogTimestamp.now(), privacy: .public) persisted statuses changed=\(changed) selection \(String(describing: previousSelection), privacy: .public) -> \(String(describing: selectedID), privacy: .public) handoff=\(String(describing: handoffTicketID), privacy: .public)")
        let enabled = defaults.object(forKey: "wristTrip.liveActivitiesEnabled") as? Bool ?? true
        // The background store may advance the selected ticket during an
        // arrival handoff while ActivityPushTokenService still holds the
        // previous in-memory selection. Publish the persisted selection before
        // ActivityKit and Watch reconciliation so the server never receives a
        // mixed old/new journey snapshot.
        updatePushSchedule?(store.tickets, selectedID, enabled)
        var success = true
        do {
            logger.info("[BG] logTime=\(ClientLogTimestamp.now(), privacy: .public) updating ActivityKit enabled=\(enabled)")
            try await updateActivity(store.tickets, selectedID, now, enabled)
        } catch {
            logger.error("[BG] logTime=\(ClientLogTimestamp.now(), privacy: .public) ActivityKit refresh failed: \(error.localizedDescription, privacy: .public)")
            success = false
        }
        guard !Task.isCancelled else { return false }
        // Wait until updateApplicationContext has queued the snapshot, not until
        // the watch is reachable or confirms delivery.
        let watchStore = TripStore(defaults: defaults)
        let watchNow = performActivityHandoff ? Date() : now
        _ = watchStore.refreshStatuses(at: watchNow)
        let queued = await syncWatch(watchStore.tickets, watchStore.selectedTicketID)
        logger.info("[BG] logTime=\(ClientLogTimestamp.now(), privacy: .public) Watch snapshot queue result=\(queued)")
        if !queued { logger.error("[BG] logTime=\(ClientLogTimestamp.now(), privacy: .public) Watch snapshot could not be queued") }
        return success && queued && !Task.isCancelled
    }

    static func nextRequestDate(tickets: [Ticket], after now: Date, manualDeadline: Date? = nil,
                                retryAfterFailure: Bool = false) -> Date? {
        let boundary = nextBoundary(tickets: tickets, after: now, manualDeadline: manualDeadline)
        guard retryAfterFailure else { return boundary }
        return [boundary, now.addingTimeInterval(retryDelay)].compactMap { $0 }.min()
    }

    static func nextBoundary(tickets: [Ticket], after now: Date, manualDeadline: Date? = nil) -> Date? {
        let boundaries: [Date] = tickets.flatMap { (ticket: Ticket) -> [Date] in
            guard ticket.isValidJourney,
                  let start = ticket.startAt,
                  let departure = ticket.plannedDepartureAt,
                  let arrival = ticket.plannedArrivalAt else {
                return []
            }
            // A local activity normally starts at the three-hour boundary, so
            // its first eight-hour renewal request is start + 8h. The actual
            // pin deadline below takes precedence when iOS runs the task late
            // and the activity starts at a different instant.
            let automaticLimit = start.addingTimeInterval(TripScheduleRules.activityMaximumDuration)
            let renewal: Date? = automaticLimit < arrival ? automaticLimit : nil
            return [
                start,
                departure.addingTimeInterval(-2 * 60 * 60),
                departure.addingTimeInterval(-1 * 60 * 60),
                departure.addingTimeInterval(-30 * 60),
                departure,
                arrival,
                renewal
            ].compactMap { $0 }
        }
        // Manual pins and locally tracked automatic activities have their own
        // eight-hour renewal deadline. Keep that deadline in the same request
        // stream so a suspended app can renew the current activity and select
        // the next journey at arrival.
        let automaticDeadline = TripActivityService.nextAutomaticActivityDeadline
        let extraDeadlines: [Date] = [manualDeadline, automaticDeadline].compactMap { $0 }
        return (boundaries + extraDeadlines)
            .filter { $0 > now }.min()
    }
}

@MainActor
private final class RefreshTaskCompletion {
    private let task: BGAppRefreshTask
    private var finished = false

    init(task: BGAppRefreshTask) {
        self.task = task
    }

    func finish(success: Bool) {
        guard !finished else { return }
        finished = true
        if success { TripBackgroundRefreshService.recordSuccessfulRefresh() }
        TripBackgroundRefreshService.logger.info("[BG] logTime=\(ClientLogTimestamp.now(), privacy: .public) setTaskCompleted success=\(success); scheduling retry=\(!success)")
        TripBackgroundRefreshService.schedule(retryAfterFailure: !success)
        task.setTaskCompleted(success: success)
    }
}
