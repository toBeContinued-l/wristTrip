import Foundation
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
        case .appNotInstalled: return "请先在 Apple Watch 上安装抬腕车次"
        case .invalidAcknowledgement: return "手表未确认保存车票，请重试"
        case .transport(let error): return "手表同步失败：\(error.localizedDescription)"
        }
    }
}

/// Queues the latest snapshot for background delivery and requests a write acknowledgement
/// when the watch app is reachable.
final class WatchSyncService: NSObject, WCSessionDelegate {
    static let shared = WatchSyncService()

    private let session: WCSession?
    private var pendingSync: ((WCSession) -> Void)?
    private var pendingCompletion: ((Result<WatchSyncReceipt, WatchSyncError>) -> Void)?

    override init() {
        session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
        session?.delegate = self
        session?.activate()
    }

    func sync(tickets: [Ticket], selectedTicketID: UUID?, completion: @escaping (Result<WatchSyncReceipt, WatchSyncError>) -> Void) {
        let watchTickets = tickets.compactMap { ticket -> WatchTicket? in
            guard !ticket.isDraft, let departureAt = ticket.plannedDepartureAt else { return nil }
            return WatchTicket(
                id: ticket.id, train: ticket.train, departureAt: departureAt,
                arrivalAt: ticket.plannedArrivalAt, timezoneIdentifier: ticket.originalTimezoneIdentifier,
                origin: ticket.from, destination: ticket.to, carriage: ticket.carriage,
                seat: ticket.seat, seatClass: ticket.seatClass, fare: ticket.fare,
                waitingRoom: ticket.waitingRoom, gate: ticket.gate,
                sourceText: ticket.sourceText,
                fieldSources: ticket.fieldSources.mapValues(\.rawValue), updatedAt: ticket.updatedAt
            )
        }
        let selectedID = watchTickets.contains { $0.id == selectedTicketID } ? selectedTicketID : nil
        let snapshot = WatchTicketSnapshot(selectedTicketID: selectedID, tickets: watchTickets)
        let data: Data
        do {
            data = try JSONEncoder().encode(snapshot)
        } catch {
            completion(.failure(.transport(error)))
            return
        }
        DispatchQueue.main.async {
            guard let session = self.session else { completion(.failure(.unsupported)); return }
            let deliver = { (session: WCSession) in
                guard session.isPaired else { completion(.failure(.notPaired)); return }
                guard session.isWatchAppInstalled else { completion(.failure(.appNotInstalled)); return }
                self.deliver(data, snapshot: snapshot, through: session, completion: completion)
            }
            guard session.activationState == .activated else {
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
                         completion: @escaping (Result<WatchSyncReceipt, WatchSyncError>) -> Void) {
        do {
            try session.updateApplicationContext(["snapshot": data])
        } catch {
            completion(.failure(.transport(error)))
            return
        }
        let queued = WatchSyncReceipt(ticketCount: snapshot.tickets.count, storedAt: snapshot.generatedAt, delivery: .queued)
        guard session.isReachable else { completion(.success(queued)); return }
        session.sendMessageData(data, replyHandler: { reply in
            let result: Result<WatchSyncReceipt, WatchSyncError>
            if let acknowledgement = try? JSONDecoder().decode(WatchSyncAcknowledgement.self, from: reply),
               acknowledgement.schemaVersion == WatchTicketSnapshot.schemaVersion,
               acknowledgement.snapshotID == snapshot.id {
                result = .success(WatchSyncReceipt(ticketCount: snapshot.tickets.count, storedAt: acknowledgement.storedAt, delivery: .confirmed))
            } else {
                result = .success(queued)
            }
            DispatchQueue.main.async { completion(result) }
        }, errorHandler: { error in
            DispatchQueue.main.async { completion(.success(queued)) }
        })
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
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
