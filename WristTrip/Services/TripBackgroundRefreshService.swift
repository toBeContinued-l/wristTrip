import BackgroundTasks
import Foundation
import OSLog

/// iOS chooses when suspended apps can refresh; these boundaries are requests,
/// not exact timers. Foreground refreshes use the same persisted status rules.
@MainActor
enum TripBackgroundRefreshService {
    static let taskIdentifier = "com.clenson.WristTrip.refresh"
    private static let logger = Logger(subsystem: "com.clenson.WristTrip", category: "BackgroundRefresh")
    private static var submittedRequestDate: Date?
    private static var hasReconciledScheduler = false
    private static let retryDelay: TimeInterval = 15 * 60

    static func register() {
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in run(refreshTask) }
        }
        if !registered { logger.error("Background refresh registration failed") }
    }

    static func schedule(tickets: [Ticket]? = nil, now: Date = Date(), retryAfterFailure: Bool = false) {
        let requestDate = nextRequestDate(tickets: tickets ?? TripStore().tickets, after: now,
                                          manualDeadline: TripActivityService.nextManualActivityDeadline,
                                          retryAfterFailure: retryAfterFailure)
        guard !hasReconciledScheduler || requestDate != submittedRequestDate else { return }
        // Replace the request only when an edit changes its next boundary.
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        hasReconciledScheduler = true
        submittedRequestDate = nil
        guard let requestDate else { return }
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = requestDate
        do {
            try BGTaskScheduler.shared.submit(request)
            submittedRequestDate = requestDate
            logger.info("Next refresh requested after \(requestDate, privacy: .public)")
        } catch {
            logger.error("Background refresh scheduling failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func run(_ task: BGAppRefreshTask) {
        submittedRequestDate = nil
        logger.info("Background refresh started")
        // Keep the next boundary queued even if this task expires while updating displays.
        schedule()
        let completion = RefreshTaskCompletion(task: task)
        let work = Task { @MainActor in
            let success = await refresh(performActivityHandoff: true)
            completion.finish(success: success && !Task.isCancelled)
        }
        task.expirationHandler = {
            work.cancel()
            Task { @MainActor in
                logger.error("Background refresh expired")
                completion.finish(success: false)
            }
        }
    }

    /// Persist before updating external displays. Hooks allow boundary tests to
    /// exercise the actual background path without ActivityKit or a paired watch.
    static func refresh(
        now: Date = Date(), defaults: UserDefaults = .standard,
        performActivityHandoff: Bool = false,
        updateActivity: ([Ticket], UUID?, Date, Bool) async throws -> Void = { tickets, selectedID, now, enabled in
            if enabled {
                _ = try await TripActivityService.refresh(tickets: tickets, selectedTicketID: selectedID, now: now)
            } else {
                await TripActivityService.endAll()
            }
        },
        syncWatch: ([Ticket], UUID?) async -> Bool = { tickets, selectedID in
            await WatchSyncService.shared.queueSnapshot(tickets: tickets, selectedTicketID: selectedID)
        }
    ) async -> Bool {
        guard !Task.isCancelled else { return false }
        let store = TripStore(defaults: defaults)
        let previousTickets = store.tickets
        let previousSelection = store.selectedTicketID
        let changed = store.refreshStatuses(at: now)
        let selectedID = store.selectedTicketID
        // Keep the next journey visible at the arrival handoff, even when it
        // is more than three hours from departure. Normal automatic refreshes
        // remain constrained to their display window.
        let arrivedAtBoundary = previousTickets.contains { ticket in
            guard let arrival = ticket.plannedArrivalAt, ticket.status != .arrived else { return false }
            return now >= arrival
        }
        let handoffTicketID = arrivedAtBoundary && selectedID != previousSelection ? selectedID : nil
        logger.info("Refreshed \(store.tickets.count) tickets; statuses changed: \(changed)")
        let enabled = defaults.object(forKey: "wristTrip.liveActivitiesEnabled") as? Bool ?? true
        var success = true
        do {
            try await updateActivity(store.tickets, selectedID, now, enabled)
            // The injected callback keeps boundary tests independent from
            // ActivityKit. In production, publish the handoff explicitly
            // after the regular refresh has reconciled the old activity.
            if performActivityHandoff, enabled, let handoffTicketID {
                _ = try await TripActivityService.refresh(tickets: store.tickets,
                                                          selectedTicketID: selectedID,
                                                          now: now,
                                                          handoffTicketID: handoffTicketID)
            }
        } catch {
            logger.error("Activity refresh failed: \(error.localizedDescription, privacy: .public)")
            success = false
        }
        guard !Task.isCancelled else { return false }
        // Wait until updateApplicationContext has queued the snapshot, not until
        // the watch is reachable or confirms delivery.
        let queued = await syncWatch(store.tickets, store.selectedTicketID)
        if !queued { logger.error("Watch snapshot could not be queued") }
        return success && queued && !Task.isCancelled
    }

    static func nextRequestDate(tickets: [Ticket], after now: Date, manualDeadline: Date? = nil,
                                retryAfterFailure: Bool = false) -> Date? {
        let boundary = nextBoundary(tickets: tickets, after: now, manualDeadline: manualDeadline)
        guard retryAfterFailure else { return boundary }
        return [boundary, now.addingTimeInterval(retryDelay)].compactMap { $0 }.min()
    }

    static func nextBoundary(tickets: [Ticket], after now: Date, manualDeadline: Date? = nil) -> Date? {
        let boundaries = tickets.flatMap { ticket in
            // Keep a deterministic eight-hour fallback boundary for an
            // activity that was started remotely before the app observed its
            // actual ActivityKit start time. Once observed, the persisted
            // automatic pin supplies the more precise renewal deadline below.
            let automaticLimit = ticket.plannedDepartureAt?.addingTimeInterval(8 * 60 * 60)
            let endOfWindow = automaticLimit.flatMap { limit in
                ticket.plannedArrivalAt.map { limit < $0 ? limit : nil } ?? nil
            }
            return [
                ticket.startAt,
                ticket.plannedDepartureAt?.addingTimeInterval(-2 * 60 * 60),
                ticket.plannedDepartureAt?.addingTimeInterval(-1 * 60 * 60),
                ticket.plannedDepartureAt?.addingTimeInterval(-30 * 60),
                ticket.plannedDepartureAt,
                ticket.plannedArrivalAt,
                endOfWindow
            ].compactMap { $0 }
        }
        // Manual pins and locally tracked automatic activities have their own
        // eight-hour renewal deadline. Keep that deadline in the same request
        // stream so a suspended app can renew the current activity and select
        // the next journey at arrival.
        let automaticDeadline = TripActivityService.nextAutomaticActivityDeadline
        return (boundaries + [manualDeadline, automaticDeadline].compactMap { $0 })
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
        TripBackgroundRefreshService.schedule(retryAfterFailure: !success)
        task.setTaskCompleted(success: success)
    }
}
