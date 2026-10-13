import ActivityKit
import Combine
import Foundation
import OSLog

@MainActor
final class ActivityPushTokenService: ObservableObject {
    static let shared = ActivityPushTokenService()

    enum ScheduleState: Equatable {
        case off, notConfigured, waitingForToken, sending, registered, failed

        var message: String {
            switch self {
            case .off: "自动展示未启用"
            case .notConfigured: "自动服务尚未配置"
            case .waitingForToken: "等待系统提供实时活动推送令牌"
            case .sending: "正在登记自动展示"
            case .registered: "自动展示已登记；推送由系统尽力投递"
            case .failed: "自动展示登记失败，打开 App 后会重试"
            }
        }
    }

    enum TokenKind: String, Codable {
        case pushToStart, activity
    }

    struct Registration: Codable, Equatable {
        let kind: TokenKind
        let token: String
        let activityID: String?
        let ticketID: UUID?
        let createdAt: Date
    }

    struct ScheduledTicket: Codable, Equatable {
        let id: UUID
        let train: String
        let origin: String
        let destination: String
        let departureAt: Date
        let arrivalAt: Date
        let startAt: Date
        let timezoneIdentifier: String
        let carriage: String
        let seat: String
        let seatClass: String
        let fare: String
        let gate: String
        let waitingRoom: String

        init?(_ ticket: Ticket, now: Date) {
            guard !ticket.isDraft, let departure = ticket.plannedDepartureAt,
                  let arrival = ticket.plannedArrivalAt, arrival > now else { return nil }
            id = ticket.id
            train = ticket.train
            origin = ticket.from
            destination = ticket.to
            departureAt = departure
            arrivalAt = arrival
            startAt = departure.addingTimeInterval(-3 * 60 * 60)
            timezoneIdentifier = ticket.originalTimezoneIdentifier
            carriage = ticket.carriage
            seat = ticket.seat
            seatClass = ticket.seatClass
            fare = ticket.fare
            gate = ticket.gate
            waitingRoom = ticket.waitingRoom
        }
    }

    struct ScheduleSnapshot: Codable, Equatable {
        let deviceID: UUID
        let enabled: Bool
        let pushToStartToken: String?
        let selectedTicketID: UUID?
        let tickets: [ScheduledTicket]
        let activityTokens: [Registration]
    }

    @Published private(set) var scheduleState: ScheduleState = .off

    private static let registrationsKey = "wristTrip.activityPushTokenRegistrations"
    private static let deviceIDKey = "wristTrip.activityDeviceID"
    private static let acknowledgedKey = "wristTrip.acknowledgedActivitySchedule"
    private let logger = Logger(subsystem: "com.clenson.WristTrip", category: "ActivityPushToken")
    private var pushToStartTask: Task<Void, Never>?
    private var activityUpdateTask: Task<Void, Never>?
    private var activityTasks: [String: Task<Void, Never>] = [:]
    private var deliveryTask: Task<Void, Never>?
    private var tickets: [Ticket] = []
    private var selectedTicketID: UUID?
    private var enabled = false
    private var desired: ScheduleSnapshot?
    private var scheduleAuthorizationToken: String?

    private init() {}

    func start() {
        guard pushToStartTask == nil else { return }
        let activities = Activity<TripActivityAttributes>.activities
        var values = registrations()
        values.removeAll { registration in
            registration.kind == .activity && !activities.contains { $0.id == registration.activityID }
        }
        saveRegistrations(values)
        for activity in activities {
            observe(activity: activity, ticketID: activity.attributes.ticketID)
        }
        activityUpdateTask = Task { [weak self] in
            for await activity in Activity<TripActivityAttributes>.activityUpdates {
                guard let self else { continue }
                self.observe(activity: activity, ticketID: activity.attributes.ticketID)
            }
        }
        pushToStartTask = Task { [weak self] in
            guard let self else { return }
            if let token = Activity<TripActivityAttributes>.pushToStartToken {
                self.store(Registration(kind: .pushToStart, token: Self.hexToken(token),
                                        activityID: nil, ticketID: nil, createdAt: Date()))
            }
            for await token in Activity<TripActivityAttributes>.pushToStartTokenUpdates {
                self.store(Registration(kind: .pushToStart, token: Self.hexToken(token),
                                        activityID: nil, ticketID: nil, createdAt: Date()))
            }
        }
    }

    func observe(activity: Activity<TripActivityAttributes>, ticketID: UUID) {
        let activityID = activity.id
        guard activityTasks[activityID] == nil else { return }
        activityTasks[activityID] = Task { [weak self] in
            guard let self else { return }
            if let token = activity.pushToken {
                self.store(Registration(kind: .activity, token: Self.hexToken(token),
                                        activityID: activityID, ticketID: ticketID, createdAt: Date()))
            }
            for await token in activity.pushTokenUpdates {
                self.store(Registration(kind: .activity, token: Self.hexToken(token),
                                        activityID: activityID, ticketID: ticketID, createdAt: Date()))
            }
        }
    }

    func stopObserving(activityID: String) {
        activityTasks.removeValue(forKey: activityID)?.cancel()
        var values = registrations()
        values.removeAll { $0.kind == .activity && $0.activityID == activityID }
        saveRegistrations(values)
        reconcile()
    }

    func updateSchedule(tickets: [Ticket], selectedTicketID: UUID?, enabled: Bool) {
        self.tickets = tickets
        self.selectedTicketID = selectedTicketID
        self.enabled = enabled
        reconcile()
    }

    /// The authentication layer can inject a short-lived user/device token.
    /// It is kept in memory and is never written to the schedule snapshot.
    func setScheduleAuthorizationToken(_ token: String?) {
        scheduleAuthorizationToken = token
        reconcile(force: true)
    }

    func retry() {
        deliveryTask?.cancel()
        deliveryTask = nil
        reconcile(force: true)
    }

    func registrations() -> [Registration] {
        guard let data = UserDefaults.standard.data(forKey: Self.registrationsKey),
              let values = try? JSONDecoder().decode([Registration].self, from: data) else { return [] }
        return values
    }

    private func store(_ registration: Registration) {
        var values = registrations()
        if values.contains(where: { $0.kind == registration.kind && $0.activityID == registration.activityID && $0.token == registration.token }) {
            return
        }
        values.removeAll { $0.kind == registration.kind && $0.activityID == registration.activityID }
        values.append(registration)
        saveRegistrations(values)
        reconcile()
    }

    private func saveRegistrations(_ values: [Registration]) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults.standard.set(data, forKey: Self.registrationsKey)
    }

    private func reconcile(force: Bool = false) {
        let acknowledged = UserDefaults.standard.data(forKey: Self.acknowledgedKey)
            .flatMap { try? JSONDecoder().decode(ScheduleSnapshot.self, from: $0) }
        if !enabled && acknowledged?.enabled != true {
            scheduleState = .off
            return
        }
        guard let endpoint else {
            scheduleState = enabled ? .notConfigured : .off
            return
        }
        let token = registrations().first(where: { $0.kind == .pushToStart })?.token
        if enabled && token == nil {
            scheduleState = .waitingForToken
            return
        }
        let scheduled = enabled ? tickets.compactMap { ScheduledTicket($0, now: Date()) } : []
        let activityTokens = registrations().filter { registration in
            registration.kind == .activity && scheduled.contains { $0.id == registration.ticketID }
        }
        let snapshot = ScheduleSnapshot(deviceID: deviceID, enabled: enabled,
                                        pushToStartToken: enabled ? token : nil,
                                        selectedTicketID: enabled ? selectedTicketID : nil,
                                        tickets: scheduled.sorted { $0.departureAt < $1.departureAt },
                                        activityTokens: enabled ? activityTokens : [])
        if !force && snapshot == acknowledged {
            scheduleState = enabled ? .registered : .off
            return
        }
        if !force && snapshot == desired && deliveryTask != nil { return }
        desired = snapshot
        deliveryTask?.cancel()
        deliveryTask = Task { [weak self] in
            guard let self else { return }
            var delay: Double = 2
            while !Task.isCancelled {
                self.scheduleState = .sending
                do {
                    var request = URLRequest(url: endpoint)
                    request.httpMethod = "PUT"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if let token = self.scheduleAuthorizationToken {
                        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    }
                    request.httpBody = try JSONEncoder().encode(snapshot)
                    let (_, response) = try await URLSession.shared.data(for: request)
                    guard let response = response as? HTTPURLResponse,
                          (200..<300).contains(response.statusCode) else { throw URLError(.badServerResponse) }
                    guard self.desired == snapshot, !Task.isCancelled else { return }
                    UserDefaults.standard.set(try JSONEncoder().encode(snapshot), forKey: Self.acknowledgedKey)
                    self.scheduleState = snapshot.enabled ? .registered : .off
                    self.deliveryTask = nil
                    return
                } catch {
                    guard self.desired == snapshot, !Task.isCancelled else { return }
                    self.logger.error("Activity schedule registration failed: \(error.localizedDescription, privacy: .public)")
                    self.scheduleState = .failed
                    try? await Task.sleep(for: .seconds(delay))
                    delay = min(delay * 2, 300)
                }
            }
        }
    }

    private var endpoint: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "WristTripScheduleURL") as? String,
              let url = URL(string: raw), url.scheme == "https", url.host != nil else { return nil }
        return url
    }

    private var deviceID: UUID {
        if let raw = UserDefaults.standard.string(forKey: Self.deviceIDKey), let id = UUID(uuidString: raw) { return id }
        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: Self.deviceIDKey)
        return id
    }

    private static func hexToken(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
