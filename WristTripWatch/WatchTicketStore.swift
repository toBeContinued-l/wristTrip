import Foundation
import Combine
import OSLog
import WatchConnectivity

final class WatchTicketStore: NSObject, ObservableObject, WCSessionDelegate {
    private let logger = Logger(subsystem: "com.clenson.WristTrip", category: "WatchConnectivity")
    @Published private(set) var snapshot: WatchTicketSnapshot?
    @Published private(set) var syncError: String?

    private let fileURL: URL
    private let cacheLock = NSLock()

    override init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        fileURL = support.appendingPathComponent("watch-tickets.json")
        super.init()
        if let data = try? Data(contentsOf: fileURL),
           let cached = try? JSONDecoder().decode(WatchTicketSnapshot.self, from: data),
           cached.schemaVersion == WatchTicketSnapshot.schemaVersion {
            snapshot = cached
            logger.info("[WATCH] loaded offline snapshot id=\(cached.id.uuidString, privacy: .public) generatedAt=\(cached.generatedAt, privacy: .public) tickets=\(cached.tickets.count) selected=\(String(describing: cached.selectedTicketID), privacy: .public)")
        }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
            logger.info("[WATCH] session activation requested")
            if let data = WCSession.default.receivedApplicationContext["snapshot"] as? Data {
                receive(data)
            }
        }
    }

    var sortedTickets: [WatchTicket] {
        (snapshot?.tickets ?? []).sorted { $0.departureAt < $1.departureAt }
    }

    func currentTicket(at now: Date) -> WatchTicket? {
        let tickets = sortedTickets
        if let selectedID = snapshot?.selectedTicketID,
           let selected = tickets.first(where: { $0.id == selectedID && $0.status(at: now) != "已到站" }) {
            return selected
        }
        if let active = tickets.first(where: { $0.departureAt <= now && now < ($0.arrivalAt ?? .distantFuture) }) {
            return active
        }
        return tickets.first(where: {
            let start = $0.departureAt.addingTimeInterval(-TripScheduleRules.automaticDisplayLeadTime)
            return start <= now && now < ($0.arrivalAt ?? .distantFuture)
        })
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        logger.info("[WATCH] activation completed state=\(activationState.rawValue) reachable=\(session.isReachable) error=\(String(describing: error), privacy: .public)")
        if let error {
            DispatchQueue.main.async { self.syncError = error.localizedDescription }
        }
        if activationState == .activated,
           let data = session.receivedApplicationContext["snapshot"] as? Data {
            receive(data)
        }
    }

    func session(_ session: WCSession, didReceiveMessageData messageData: Data, replyHandler: @escaping (Data) -> Void) {
        replyHandler(receive(messageData) ?? Data())
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["snapshot"] as? Data else { return }
        receive(data)
    }

    @discardableResult
    private func receive(_ messageData: Data) -> Data? {
        guard let incoming = try? JSONDecoder().decode(WatchTicketSnapshot.self, from: messageData),
              incoming.schemaVersion == WatchTicketSnapshot.schemaVersion else {
            logger.error("[WATCH] received invalid snapshot payload bytes=\(messageData.count)")
            return nil
        }

        cacheLock.lock()
        defer { cacheLock.unlock() }

        do {
            let current = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode(WatchTicketSnapshot.self, from: $0) }
            // updateApplicationContext is latest-value delivery. Ignore equal
            // or older snapshots so a delayed callback cannot roll the Watch
            // back to an earlier selection or status.
            if let current, current.generatedAt >= incoming.generatedAt {
                logger.info("[WATCH] ignored stale snapshot incoming=\(incoming.id.uuidString, privacy: .public) incomingAt=\(incoming.generatedAt, privacy: .public) currentAt=\(current.generatedAt, privacy: .public)")
                return nil
            } else {
                try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try messageData.write(to: fileURL, options: .atomic)
                DispatchQueue.main.async {
                    if self.snapshot?.generatedAt ?? .distantPast < incoming.generatedAt {
                        self.snapshot = incoming
                        self.syncError = nil
                    }
                }
                logger.info("[WATCH] applied snapshot id=\(incoming.id.uuidString, privacy: .public) generatedAt=\(incoming.generatedAt, privacy: .public) tickets=\(incoming.tickets.count) selected=\(String(describing: incoming.selectedTicketID), privacy: .public)")
            }
            let acknowledgement = WatchSyncAcknowledgement(
                schemaVersion: WatchTicketSnapshot.schemaVersion,
                snapshotID: incoming.id, storedAt: Date()
            )
            return try JSONEncoder().encode(acknowledgement)
        } catch {
            logger.error("[WATCH] persist snapshot failed: \(error.localizedDescription, privacy: .public)")
            DispatchQueue.main.async { self.syncError = error.localizedDescription }
            return nil
        }
    }
}
