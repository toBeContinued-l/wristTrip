import Foundation
import OSLog
import WatchConnectivity

struct WatchSyncReceipt {
    let ticketCount: Int
    let storedAt: Date
    let delivery: Delivery

    enum Delivery {
        case confirmed
        case queued
    }
}

enum WatchSyncError: LocalizedError {
    case unsupported
    case activating
    case notPaired
    case appNotInstalled
    case invalidAcknowledgement
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .unsupported: return "此设备不支持 Apple Watch 同步"
        case .activating: return "手表连接仍在初始化，请稍后重试"
        case .notPaired: return "尚未配对 Apple Watch"
        case .appNotInstalled: return nil
        case .invalidAcknowledgement: return "手表未确认保存车票，请重试"
        case .transport(let error): return "手表同步失败：\(error.localizedDescription)"
        }
    }
}

/// Queues the latest snapshot for background delivery and requests a write acknowledgement
/// when the watch app is reachable.
final class WatchSyncService: NSObject, WCSessionDelegate {
    static let shared = WatchSyncService()
    private let logger = Logger(subsystem: "com.clenson.WristTrip", category: "WatchConnectivity")

    private let session: WCSession?
    private var pendingSync: ((WCSession) -> Void)?
    private var pendingCompletion: ((Result<WatchSyncReceipt, WatchSyncError>) -> Void)?
    private var latestQueuedSnapshotAt: Date = .distantPast

    override init() {
        session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func sync(tickets: [Ticket], selectedTicketID: UUID?, confirmReceipt: Bool = true,
              now: Date = Date(),
              completion: @escaping (Result<WatchSyncReceipt, WatchSyncError>) -> Void) {
        let watchTickets = tickets.compactMap { ticket -> WatchTicket? in
            guard ticket.isValidJourney, let departureAt = ticket.plannedDepartureAt,
                  let arrivalAt = ticket.plannedArrivalAt else { return nil }
            let leg = TripScheduleRules.displayedLeg(departure: departureAt, arrival: arrivalAt,
                                                      origin: ticket.from, destination: ticket.to, now: now)
            return WatchTicket(
                id: ticket.id, train: ticket.train, departureAt: departureAt,
                arrivalAt: arrivalAt, timezoneIdentifier: ticket.originalTimezoneIdentifier,
                origin: ticket.from, destination: ticket.to, carriage: ticket.carriage,
                seat: ticket.seat, seatClass: ticket.seatClass, fare: ticket.fare,
                waitingRoom: ticket.waitingRoom, gate: ticket.gate,
                sourceText: ticket.sourceText,
                fieldSources: ticket.fieldSources.mapValues(\.rawValue), updatedAt: ticket.updatedAt,
                plannedStatus: ticket.status(at: now).rawValue,
                displayedStation: leg.station, displayedTime: leg.time
            )
        }
        let selectedID = watchTickets.contains { $0.id == selectedTicketID } ? selectedTicketID : nil
        let snapshot = WatchTicketSnapshot(selectedTicketID: selectedID, tickets: watchTickets)
        let ticketLog = watchTickets.map { ticket in
            "id=\(ticket.id.uuidString) train=\(ticket.train) status=\(ticket.plannedStatus) displayed=\(ticket.displayedStation)@\(ticket.displayedTime)"
        }.joined(separator: " | ")
        logger.info("[WATCH] snapshot id=\(snapshot.id.uuidString, privacy: .public) generatedAt=\(snapshot.generatedAt, privacy: .public) tickets=\(snapshot.tickets.count) selected=\(String(describing: snapshot.selectedTicketID), privacy: .public) now=\(now, privacy: .public)")
        logger.info("[WATCH] tickets=\(ticketLog, privacy: .public)")
        let data: Data
        do {
            data = try JSONEncoder().encode(snapshot)
        } catch {
            logger.error("Watch snapshot encoding failed: \(error.localizedDescription, privacy: .public)")
            completion(.failure(.transport(error)))
            return
        }
        DispatchQueue.main.async {
            guard snapshot.generatedAt >= self.latestQueuedSnapshotAt else {
                self.logger.info("[WATCH] ignored older outgoing snapshot id=\(snapshot.id.uuidString, privacy: .public)")
                completion(.success(WatchSyncReceipt(ticketCount: snapshot.tickets.count,
                                                     storedAt: snapshot.generatedAt, delivery: .queued)))
                return
            }
            self.latestQueuedSnapshotAt = snapshot.generatedAt
            guard let session = self.session else {
                self.logger.error("[WATCH] unsupported: no WCSession")
                completion(.failure(.unsupported)); return
            }
            self.logger.info("[WATCH] session state=\(session.activationState.rawValue) paired=\(session.isPaired) installed=\(session.isWatchAppInstalled) reachable=\(session.isReachable)")
            let deliver = { (session: WCSession) in
                guard session.isPaired else { self.logger.info("[WATCH] snapshot queued without a paired watch"); completion(.failure(.notPaired)); return }
                guard session.isWatchAppInstalled else { self.logger.info("[WATCH] snapshot queued without the Watch app installed"); completion(.failure(.appNotInstalled)); return }
                self.deliver(data, snapshot: snapshot, through: session, confirmReceipt: confirmReceipt, completion: completion)
            }
            guard session.activationState == .activated else {
                self.logger.info("[WATCH] activation pending state=\(session.activationState.rawValue); snapshot retained for activation callback")
                self.pendingCompletion?(.failure(.activating))
                self.pendingSync = deliver
                self.pendingCompletion = completion
                session.activate()
                return
            }
            deliver(session)
        }
    }

    private func deliver(_ data: Data, snapshot: WatchTicketSnapshot, through session: WCSession,
                         confirmReceipt: Bool,
                         completion: @escaping (Result<WatchSyncReceipt, WatchSyncError>) -> Void) {
        do {
            try session.updateApplicationContext(["snapshot": data])
            logger.info("[WATCH] updateApplicationContext accepted snapshot=\(snapshot.id.uuidString, privacy: .public) generatedAt=\(snapshot.generatedAt, privacy: .public) selected=\(String(describing: snapshot.selectedTicketID), privacy: .public)")
        } catch {
            logger.error("[WATCH] updateApplicationContext failed snapshot=\(snapshot.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            completion(.failure(.transport(error)))
            return
        }
        let queued = WatchSyncReceipt(ticketCount: snapshot.tickets.count, storedAt: snapshot.generatedAt, delivery: .queued)
        guard confirmReceipt && session.isReachable else {
            logger.info("[WATCH] snapshot queued delivery=queued confirm=\(confirmReceipt) reachable=\(session.isReachable)")
            completion(.success(queued)); return
        }
        session.sendMessageData(data, replyHandler: { reply in
            let result: Result<WatchSyncReceipt, WatchSyncError>
            if let acknowledgement = try? JSONDecoder().decode(WatchSyncAcknowledgement.self, from: reply),
               acknowledgement.schemaVersion == WatchTicketSnapshot.schemaVersion,
               acknowledgement.snapshotID == snapshot.id {
                result = .success(WatchSyncReceipt(ticketCount: snapshot.tickets.count, storedAt: acknowledgement.storedAt, delivery: .confirmed))
            } else {
                self.logger.info("[WATCH] acknowledgement invalid or absent snapshot=\(snapshot.id.uuidString, privacy: .public); retaining queued result")
                result = .success(queued)
            }
            DispatchQueue.main.async { completion(result) }
        }, errorHandler: { error in
            self.logger.error("[WATCH] message delivery failed after context queue snapshot=\(snapshot.id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
            DispatchQueue.main.async { completion(.success(queued)) }
        })
    }

    @MainActor
    func queueSnapshot(tickets: [Ticket], selectedTicketID: UUID?, now: Date = Date()) async -> Bool {
        let waiter = WatchQueueWaiter()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiter.install(continuation)
                guard !Task.isCancelled else { waiter.finish(false); return }
                sync(tickets: tickets, selectedTicketID: selectedTicketID, confirmReceipt: false, now: now) { result in
                    switch result {
                    case .success, .failure(.unsupported), .failure(.notPaired), .failure(.appNotInstalled):
                        waiter.finish(true)
                    case .failure: waiter.finish(false)
                    }
                }
                // Activation must not consume the whole background execution budget.
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { waiter.finish(false) }
            }
        } onCancel: {
            waiter.finish(false)
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.logger.info("[WATCH] activation completed state=\(activationState.rawValue) paired=\(session.isPaired) installed=\(session.isWatchAppInstalled) reachable=\(session.isReachable) error=\(String(describing: error), privacy: .public)")
            guard let pendingSync = self.pendingSync else { return }
            self.pendingSync = nil
            let pendingCompletion = self.pendingCompletion
            self.pendingCompletion = nil
            if activationState == .activated {
                pendingSync(session)
            } else if let error {
                pendingCompletion?(.failure(.transport(error)))
            } else {
                pendingCompletion?(.failure(.activating))
            }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}

/// Activation, expiration and timeout can race; resume the background waiter once.
private final class WatchQueueWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    private var result: Bool?

    func install(_ continuation: CheckedContinuation<Bool, Never>) {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(returning: result)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    func finish(_ result: Bool) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: result)
    }
}
