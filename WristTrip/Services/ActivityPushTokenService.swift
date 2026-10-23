import ActivityKit
import Combine
import Foundation
import OSLog
import Security

@MainActor
final class ActivityPushTokenService: ObservableObject {
    static let shared = ActivityPushTokenService()

    enum ScheduleState: Equatable {
        case off, notConfigured, waitingForAuthorization, waitingForPushToken,
             systemDisabled, sending, registered, failed, identityConflict

        var message: String {
            switch self {
            case .off: "自动展示未登记"
            case .notConfigured: "自动服务尚未配置"
            case .waitingForAuthorization: "正在获取自动展示令牌"
            case .waitingForPushToken: "快照已上传，等待系统提供启动令牌"
            case .systemDisabled: "请在 iPhone 设置中开启实时活动"
            case .sending: "正在登记自动展示"
            case .registered: "自动展示已登记；推送由系统尽力投递"
            case .failed: "自动展示登记失败，打开 App 后会重试"
            case .identityConflict: "设备 ID 已绑定其他身份，请切换身份后重试"
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
        var departureAt: Date? = nil
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

        init?(_ ticket: Ticket, now _: Date) {
            guard ticket.isValidJourney, let departure = ticket.plannedDepartureAt,
                  let arrival = ticket.plannedArrivalAt,
                  TimeZone(identifier: ticket.originalTimezoneIdentifier) != nil else { return nil }
            id = ticket.id
            train = ticket.train
            origin = ticket.from
            destination = ticket.to
            departureAt = departure
            arrivalAt = arrival
            startAt = TripScheduleRules.automaticStart(departure: departure)
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
        let snapshotVersion: Int64
        let enabled: Bool
        let pushToStartToken: String?
        let selectedTicketID: UUID?
        let tickets: [ScheduledTicket]
        let activityTokens: [Registration]

        private enum CodingKeys: String, CodingKey {
            case deviceID, snapshotVersion, enabled, pushToStartToken, selectedTicketID, tickets, activityTokens
        }

        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(deviceID, forKey: .deviceID)
            try values.encode(snapshotVersion, forKey: .snapshotVersion)
            try values.encode(enabled, forKey: .enabled)
            try values.encode(pushToStartToken, forKey: .pushToStartToken)
            try values.encode(selectedTicketID, forKey: .selectedTicketID)
            try values.encode(tickets, forKey: .tickets)
            try values.encode(activityTokens, forKey: .activityTokens)
        }

        func matchesContent(of other: ScheduleSnapshot) -> Bool {
            deviceID == other.deviceID && enabled == other.enabled
                && pushToStartToken == other.pushToStartToken
                && selectedTicketID == other.selectedTicketID
                && tickets == other.tickets && activityTokens == other.activityTokens
        }

        func withVersion(_ version: Int64) -> ScheduleSnapshot {
            ScheduleSnapshot(deviceID: deviceID, snapshotVersion: version, enabled: enabled,
                             pushToStartToken: pushToStartToken, selectedTicketID: selectedTicketID,
                             tickets: tickets, activityTokens: activityTokens)
        }
    }

    struct AccessCredential: Codable {
        let accessToken: String
        let expiresAt: Date
        let isAnonymous: Bool

        init(accessToken: String, expiresAt: Date, isAnonymous: Bool = false) {
            self.accessToken = accessToken
            self.expiresAt = expiresAt
            self.isAnonymous = isAnonymous
        }

        private enum CodingKeys: String, CodingKey { case accessToken, expiresAt, isAnonymous }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            accessToken = try values.decode(String.self, forKey: .accessToken)
            expiresAt = try values.decode(Date.self, forKey: .expiresAt)
            isAnonymous = try values.decodeIfPresent(Bool.self, forKey: .isAnonymous) ?? false
        }

        func isValid(at date: Date = Date()) -> Bool {
            !accessToken.isEmpty && expiresAt > date.addingTimeInterval(60)
        }

        func needsRenewal(at date: Date = Date()) -> Bool {
            expiresAt <= date.addingTimeInterval(24 * 60 * 60)
        }
    }

    struct StoredCredentials: Codable {
        let current: AccessCredential
        let previousAnonymous: [AccessCredential]
    }

    struct ExchangeResponse: Decodable {
        struct DataPayload: Decodable {
            let accessToken: String
            let tokenType: String
            let expiresIn: TimeInterval
        }

        let code: Int
        let data: DataPayload?
    }

    @Published private(set) var scheduleState: ScheduleState = .off
    @Published private(set) var lastSuccessfulUploadAt: Date?

    private static let registrationsKey = "wristTrip.activityPushTokenRegistrations"
    private static let deviceIDKey = "wristTrip.activityDeviceID"
    private static let acknowledgedKey = "wristTrip.acknowledgedActivitySchedule"
    private static let issuedVersionKey = "wristTrip.activitySnapshotVersion"
    private static let authorizationTokenKey = "wristTrip.activityAccessCredential"
    private static let authorizationTokenService = "com.clenson.WristTrip.authentication"
    private static let forbiddenDeviceIDKey = "wristTrip.forbiddenActivityDeviceID"
    private let logger = Logger(subsystem: "com.clenson.WristTrip", category: "ActivityPushToken")
    private var pushToStartTask: Task<Void, Never>?
    private var activityUpdateTask: Task<Void, Never>?
    private var activityTasks: [String: Task<Void, Never>] = [:]
    private var activityStateTasks: [String: Task<Void, Never>] = [:]
    private var activityArrivalTasks: [String: Task<Void, Never>] = [:]
    private var handledStaleActivityIDs = Set<String>()
    private var programmaticallyEndingActivityIDs = Set<String>()
    private var deliveryTask: Task<Void, Never>?
    private var tickets: [Ticket] = []
    private var selectedTicketID: UUID?
    private var enabled = false
    private var desired: ScheduleSnapshot?
    private var accessCredential: AccessCredential?
    private var previousAnonymousCredentials: [AccessCredential] = []
    private var sourceLoginToken: String?
    private var exchangeRevision = 0
    private var exchangeTask: Task<Bool, Never>?
    private var didReexchangeAfterUnauthorized = false
    private var isPreparingForLogout = false
    private var nextExchangeAttemptAt = Date.distantPast
    private var renewalTask: Task<Void, Never>?
    private var exchangeRetryTask: Task<Void, Never>?
    private var unauthorizedAccessToken: String?
    private var rejectedSnapshot: ScheduleSnapshot?
    private var authenticationRequired = false
    private var needsForegroundUpload = true
    private var scheduleRetryDelay: Double = 2
    private var nextScheduleAttemptAt = Date.distantPast

    private init() {
        if let stored = Self.loadAccessCredentials() {
            accessCredential = stored.current
            previousAnonymousCredentials = stored.previousAnonymous
        }
        scheduleRenewal()
    }

    func start() {
        guard pushToStartTask == nil else { return }
        logger.info("[PUSH] logTime=\(ClientLogTimestamp.now(), privacy: .public) ActivityKit token observation started activitiesEnabled=\(ActivityAuthorizationInfo().areActivitiesEnabled)")
        rescanActivities()
        activityUpdateTask = Task { @MainActor [weak self] in
            for await activity in Activity<TripActivityAttributes>.activityUpdates {
                guard !Task.isCancelled, let self else { return }
                self.logger.info("[ACTIVITY] logTime=\(ClientLogTimestamp.now(), privacy: .public) activityUpdates id=\(activity.id, privacy: .public) ticket=\(activity.attributes.ticketID.uuidString, privacy: .public) state=\(String(describing: activity.activityState), privacy: .public)")
                self.observe(activity: activity, ticketID: activity.attributes.ticketID)
                // A push-to-start can land just after the local request's
                // final enumeration. Reconcile on ActivityKit's authoritative
                // stream so the second producer is discovered and deduplicated.
                Task { @MainActor in
                    _ = try? await TripActivityService.refresh(
                        tickets: TripStore().tickets,
                        selectedTicketID: TripStore().selectedTicketID,
                        startAutomaticallyLocally: false)
                }
            }
        }
        pushToStartTask = Task { @MainActor [weak self] in
            if let token = Activity<TripActivityAttributes>.pushToStartToken {
                guard let self else { return }
                self.logger.info("[PUSH] logTime=\(ClientLogTimestamp.now(), privacy: .public) Current push-to-start token available bytes=\(token.count)")
                self.store(Registration(kind: .pushToStart, token: Self.hexToken(token),
                                        activityID: nil, ticketID: nil, createdAt: Date()))
            }
            for await token in Activity<TripActivityAttributes>.pushToStartTokenUpdates {
                guard !Task.isCancelled, let self else { return }
                self.logger.info("[PUSH] logTime=\(ClientLogTimestamp.now(), privacy: .public) Push-to-start token updated bytes=\(token.count)")
                self.store(Registration(kind: .pushToStart, token: Self.hexToken(token),
                                        activityID: nil, ticketID: nil, createdAt: Date()))
            }
        }
    }

    func observe(activity: Activity<TripActivityAttributes>, ticketID: UUID) {
        let activityID = activity.id
        guard activityTasks[activityID] == nil else { return }
        logger.info("[PUSH] logTime=\(ClientLogTimestamp.now(), privacy: .public) Activity token observation attached activityID=\(activityID, privacy: .public) ticketID=\(ticketID.uuidString, privacy: .public) tokenAvailable=\(activity.pushToken != nil)")
        handledStaleActivityIDs.remove(activityID)
        activityTasks[activityID] = Task { @MainActor [weak self] in
            if let token = activity.pushToken {
                guard let self else { return }
                self.logger.info("[PUSH] logTime=\(ClientLogTimestamp.now(), privacy: .public) Current activity update token available activityID=\(activityID, privacy: .public) ticketID=\(ticketID.uuidString, privacy: .public) bytes=\(token.count)")
                self.store(Registration(kind: .activity, token: Self.hexToken(token),
                                        activityID: activityID, ticketID: ticketID, createdAt: Date(),
                                        departureAt: activity.attributes.departureAt))
            }
            for await token in activity.pushTokenUpdates {
                guard !Task.isCancelled, let self else { return }
                self.logger.info("[PUSH] logTime=\(ClientLogTimestamp.now(), privacy: .public) Activity update token changed activityID=\(activityID, privacy: .public) ticketID=\(ticketID.uuidString, privacy: .public) bytes=\(token.count)")
                self.store(Registration(kind: .activity, token: Self.hexToken(token),
                                        activityID: activityID, ticketID: ticketID, createdAt: Date(),
                                        departureAt: activity.attributes.departureAt))
            }
        }
        activityStateTasks[activityID] = Task { @MainActor [weak self] in
            for await state in activity.activityStateUpdates {
                guard !Task.isCancelled, let self else { return }
                self.logger.info("[ACTIVITY] logTime=\(ClientLogTimestamp.now(), privacy: .public) state changed id=\(activityID, privacy: .public) ticket=\(ticketID.uuidString, privacy: .public) state=\(String(describing: state), privacy: .public) programmaticEnd=\(self.programmaticallyEndingActivityIDs.contains(activityID))")
                switch state {
                case .stale:
                    // If ActivityKit delivers staleDate while the process is
                    // resumed, reconcile immediately even when no BG task ran
                    // at the planned boundary so an arrived activity can end.
                    guard self.handledStaleActivityIDs.insert(activityID).inserted else {
                        continue
                    }
                    self.logger.info("[ACTIVITY] logTime=\(ClientLogTimestamp.now(), privacy: .public) state became stale id=\(activityID, privacy: .public)")
                    Task { @MainActor in
                        let success = await TripBackgroundRefreshService.refresh(now: Date(),
                                                                                  performActivityHandoff: true,
                                                                                  updatePushSchedule: { tickets, selectedID, enabled in
                                                                                      ActivityPushTokenService.shared.updateSchedule(
                                                                                          tickets: tickets,
                                                                                          selectedTicketID: selectedID,
                                                                                          enabled: enabled)
                                                                                  })
                        if !success {
                            TripBackgroundRefreshService.schedule(retryAfterFailure: true)
                        } else {
                            TripBackgroundRefreshService.recordSuccessfulRefresh()
                            // The refresh can clear an arrived ticket's
                            // renewal pin. Reconcile again after ActivityKit
                            // finishes so an obsolete eight-hour request is
                            // not left in BGTaskScheduler.
                            TripBackgroundRefreshService.schedule()
                        }
                    }
                    return
                case .ended, .dismissed:
                    // A swipe-to-dismiss is a user-visible activity state
                    // change. Reconcile the next BG boundary without making
                    // Watch reachability a prerequisite for iPhone activity.
                    let programmaticEnd = self.programmaticallyEndingActivityIDs.contains(activityID)
                    let arrived = Date() >= activity.attributes.arrivalAt
                    let recordsUserDismissal = TripActivityService.shouldRecordDismissal(
                        state: state, attributes: activity.attributes,
                        programmaticEnd: programmaticEnd, tickets: TripStore().tickets, now: Date())
                    self.logger.info("[ACTIVITY] logTime=\(ClientLogTimestamp.now(), privacy: .public) terminal state id=\(activityID, privacy: .public) ticket=\(ticketID.uuidString, privacy: .public) arrived=\(arrived) recordUserDismissal=\(recordsUserDismissal)")
                    if recordsUserDismissal {
                        TripActivityService.recordDismissal(attributes: activity.attributes)
                    }
                    self.programmaticallyEndingActivityIDs.remove(activityID)
                    self.stopObserving(activityID: activityID)
                    self.handledStaleActivityIDs.remove(activityID)
                    TripBackgroundRefreshService.schedule()
                    if arrived {
                        Task { @MainActor in
                            let success = await TripBackgroundRefreshService.refresh(
                                now: Date(), performActivityHandoff: true,
                                updatePushSchedule: { tickets, selectedID, enabled in
                                    ActivityPushTokenService.shared.updateSchedule(
                                        tickets: tickets,
                                        selectedTicketID: selectedID,
                                        enabled: enabled)
                                })
                            if success {
                                TripBackgroundRefreshService.recordSuccessfulRefresh()
                                TripBackgroundRefreshService.schedule()
                            } else {
                                TripBackgroundRefreshService.schedule(retryAfterFailure: true)
                            }
                        }
                    }
                    return
                default:
                    continue
                }
            }
        }
        // staleDate is a display hint and does not guarantee that the app is
        // resumed at the arrival instant. While the process is running, keep
        // an explicit arrival timer so the normal refresh path ends the
        // activity instead of leaving a stale card visible indefinitely.
        activityArrivalTasks[activityID] = Task { @MainActor [weak self] in
            do {
                let delay = activity.attributes.arrivalAt.timeIntervalSinceNow
                if delay > 0 {
                    try await Task.sleep(for: .seconds(delay))
                }
                guard !Task.isCancelled, let self,
                      Activity<TripActivityAttributes>.activities.contains(where: { $0.id == activityID }) else { return }
                self.logger.info("[ACTIVITY] logTime=\(ClientLogTimestamp.now(), privacy: .public) arrival cleanup timer fired id=\(activityID, privacy: .public)")
                let success = await TripBackgroundRefreshService.refresh(now: Date(),
                                                                          performActivityHandoff: true,
                                                                          updatePushSchedule: { tickets, selectedID, enabled in
                                                                              ActivityPushTokenService.shared.updateSchedule(
                                                                                  tickets: tickets,
                                                                                  selectedTicketID: selectedID,
                                                                                  enabled: enabled)
                                                                          })
                if success {
                    TripBackgroundRefreshService.recordSuccessfulRefresh()
                    TripBackgroundRefreshService.schedule()
                } else {
                    TripBackgroundRefreshService.schedule(retryAfterFailure: true)
                }
            } catch is CancellationError {
                return
            } catch {
                self?.logger.error("[ACTIVITY] logTime=\(ClientLogTimestamp.now(), privacy: .public) arrival cleanup timer failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func stopObserving(activityID: String) {
        stopObserving(activityID: activityID, reconcile: true)
    }

    func stopObserving(activityID: String, reconcile: Bool) {
        activityTasks.removeValue(forKey: activityID)?.cancel()
        activityStateTasks.removeValue(forKey: activityID)?.cancel()
        activityArrivalTasks.removeValue(forKey: activityID)?.cancel()
        handledStaleActivityIDs.remove(activityID)
        var values = registrations()
        let removed = values.filter { $0.kind == .activity && $0.activityID == activityID }
        values.removeAll { $0.kind == .activity && $0.activityID == activityID }
        saveRegistrations(values)
        for registration in removed {
            logger.info("[PUSH] logTime=\(ClientLogTimestamp.now(), privacy: .public) Activity token removed activityID=\(activityID, privacy: .public) ticketID=\(registration.ticketID?.uuidString ?? "nil", privacy: .public) reason=OBSERVATION_STOPPED")
        }
        if reconcile { self.reconcile() }
    }

    func markProgrammaticEnd(activityID: String) {
        programmaticallyEndingActivityIDs.insert(activityID)
    }

    func clearProgrammaticEnd(activityID: String) {
        programmaticallyEndingActivityIDs.remove(activityID)
    }

    func updateSchedule(tickets: [Ticket], selectedTicketID: UUID?, enabled: Bool) {
        self.tickets = tickets
        self.selectedTicketID = selectedTicketID
        self.enabled = enabled
        reconcile()
    }

    func refreshOnForeground() {
        needsForegroundUpload = true
        rescanActivities()
    }

    private func rescanActivities() {
        let activities = Activity<TripActivityAttributes>.activities
        let liveIDs = Set(activities.map(\.id))
        for activityID in activityTasks.keys.filter({ !liveIDs.contains($0) }) {
            activityTasks.removeValue(forKey: activityID)?.cancel()
            activityStateTasks.removeValue(forKey: activityID)?.cancel()
            activityArrivalTasks.removeValue(forKey: activityID)?.cancel()
            handledStaleActivityIDs.remove(activityID)
        }
        var values = registrations()
        let removed = values.filter { $0.kind == .activity && !liveIDs.contains($0.activityID ?? "") }
        values.removeAll { $0.kind == .activity && !liveIDs.contains($0.activityID ?? "") }
        if !removed.isEmpty { saveRegistrations(values) }
        logger.info("[PUSH] logTime=\(ClientLogTimestamp.now(), privacy: .public) Activity token rescan liveActivities=\(activities.count) removedRegistrations=\(removed.count)")
        for registration in removed {
            logger.info("[PUSH] logTime=\(ClientLogTimestamp.now(), privacy: .public) Activity token removed activityID=\(registration.activityID ?? "nil", privacy: .public) ticketID=\(registration.ticketID?.uuidString ?? "nil", privacy: .public) reason=ACTIVITY_NOT_FOUND")
        }
        for activity in activities {
            observe(activity: activity, ticketID: activity.attributes.ticketID)
        }
    }

    /// Supplies the same exchanged credentials used by the existing API
    /// requests. The source login token remains in memory and is never stored
    /// in a request body or log.
    func apiRequestCredentials() async -> APIRequestCredentials? {
        if accessCredential?.isValid() != true {
            if exchangeTask == nil, !isPreparingForLogout {
                let revision = exchangeRevision
                exchangeTask = Task { [weak self] in
                    await self?.exchangeAccessToken(revision: revision) ?? false
                }
            }
            _ = await exchangeTask?.value
        }
        guard let credential = accessCredential, credential.isValid(),
              !authenticationRequired else { return nil }
        return APIRequestCredentials(token: credential.accessToken,
                                     userLoginToken: sourceLoginToken)
    }

    /// Lets other API clients hand a 401/114 response back to the existing
    /// authentication state machine without duplicating token exchange logic.
    func retryAfterAPIUnauthorized() {
        guard !isPreparingForLogout else { return }
        unauthorizedAccessToken = accessCredential?.accessToken
        authenticationRequired = false
        didReexchangeAfterUnauthorized = false
        nextExchangeAttemptAt = .distantPast
        exchangeTask?.cancel()
        let revision = exchangeRevision
        exchangeTask = Task { [weak self] in
            await self?.exchangeAccessToken(revision: revision) ?? false
        }
    }

    /// Call with a login token from clenson's trusted login flow. Only the
    /// exchanged access token is stored; the source token stays in memory.
    @discardableResult
    func setSourceLoginToken(_ token: String?) async -> Bool {
        let normalized = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextToken = normalized?.isEmpty == false ? normalized : nil
        if let nextToken, nextToken == sourceLoginToken {
            if let accessCredential, accessCredential.isValid(),
               !authenticationRequired, unauthorizedAccessToken != accessCredential.accessToken {
                return true
            }
            authenticationRequired = false
            didReexchangeAfterUnauthorized = false
            nextExchangeAttemptAt = .distantPast
            exchangeTask?.cancel()
            exchangeRevision += 1
            let revision = exchangeRevision
            let task = Task { [weak self] in
                await self?.exchangeAccessToken(revision: revision) ?? false
            }
            exchangeTask = task
            return await task.value
        }
        let previousEnabled = enabled
        if UserDefaults.standard.string(forKey: Self.forbiddenDeviceIDKey) == deviceID.uuidString {
            accessCredential = nil
            previousAnonymousCredentials = []
            Self.clearAccessCredential()
            rotateDeviceID()
        } else if accessCredential != nil || sourceLoginToken != nil {
            guard await prepareForLogout() else {
                enabled = previousEnabled
                reconcile()
                return false
            }
        } else if (nextToken != nil || authenticationRequired),
                  UserDefaults.standard.string(forKey: Self.deviceIDKey) != nil {
            // A prior identity may have expired before it could be disabled.
            rotateDeviceID()
        }
        exchangeTask?.cancel()
        exchangeTask = nil
        sourceLoginToken = nextToken
        authenticationRequired = false
        exchangeRevision += 1
        didReexchangeAfterUnauthorized = false
        guard nextToken != nil else {
            reconcile()
            return true
        }
        enabled = previousEnabled
        let revision = exchangeRevision
        let task = Task { [weak self] in
            await self?.exchangeAccessToken(revision: revision) ?? false
        }
        exchangeTask = task
        return await task.value
    }

    private func exchangeAccessToken(revision: Int) async -> Bool {
        guard let exchangeURL else {
            scheduleState = .waitingForAuthorization
            return false
        }
        defer {
            if exchangeRevision == revision { exchangeTask = nil }
        }
        let credential = accessCredential
        let loginToken = sourceLoginToken
        let sourceToken = loginToken ?? credential?.accessToken
        let isAnonymous = loginToken == nil && (credential?.isAnonymous ?? true)
        let responseDate: Date
        do {
            var request = URLRequest(url: exchangeURL)
            request.httpMethod = "POST"
            if let sourceToken {
                request.setValue("Bearer \(sourceToken)", forHTTPHeaderField: "Authorization")
            }
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data("{}".utf8)
            logger.info("[PUSH] logTime=\(ClientLogTimestamp.now(), privacy: .public) Token exchange started sourcePresent=\(sourceToken != nil)")
            let (data, response) = try await URLSession.shared.data(for: request)
            responseDate = Date()
            guard exchangeRevision == revision, self.sourceLoginToken == loginToken,
                  self.accessCredential?.accessToken == credential?.accessToken,
                  !Task.isCancelled else { return false }
            guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            logger.info("[PUSH] logTime=\(ClientLogTimestamp.now(), privacy: .public) Token exchange completed httpStatus=\(response.statusCode)")
            if response.statusCode == 429 {
                nextExchangeAttemptAt = Date().addingTimeInterval(60)
                scheduleExchangeRetry(revision: revision)
                return false
            }
            let result = try JSONDecoder().decode(ExchangeResponse.self, from: data)
            logger.info("[PUSH] logTime=\(ClientLogTimestamp.now(), privacy: .public) Token exchange businessCode=\(result.code)")
            if result.code == 302 {
                nextExchangeAttemptAt = Date().addingTimeInterval(60)
                scheduleExchangeRetry(revision: revision)
                return false
            }
            if result.code == 102 || result.code == 114 {
                if isAnonymous, credential != nil {
                    let remaining = previousAnonymousCredentials.filter {
                        $0.expiresAt > responseDate && $0.accessToken != sourceToken
                    }
                    if let fallback = remaining.first {
                        let older = Array(remaining.dropFirst())
                        guard Self.saveAccessCredentials(StoredCredentials(
                            current: fallback, previousAnonymous: older)) else {
                            throw URLError(.cannotWriteToFile)
                        }
                        accessCredential = fallback
                        previousAnonymousCredentials = older
                    } else {
                        accessCredential = nil
                        previousAnonymousCredentials = []
                        Self.clearAccessCredential()
                        rotateDeviceID()
                    }
                    scheduleRenewal()
                    nextExchangeAttemptAt = Date().addingTimeInterval(2)
                    scheduleExchangeRetry(revision: revision)
                } else {
                    authenticationRequired = true
                    sourceLoginToken = nil
                    scheduleState = .waitingForAuthorization
                }
                return false
            }
            guard (200..<300).contains(response.statusCode) else { throw URLError(.badServerResponse) }
            guard result.code == 0, let payload = result.data,
                  payload.tokenType.caseInsensitiveCompare("Bearer") == .orderedSame,
                  !payload.accessToken.isEmpty, payload.expiresIn > 60 else {
                throw URLError(.badServerResponse)
            }
            let credential = AccessCredential(accessToken: payload.accessToken,
                                              expiresAt: responseDate.addingTimeInterval(payload.expiresIn),
                                              isAnonymous: isAnonymous)
            var previous = previousAnonymousCredentials.filter { $0.expiresAt > responseDate }
            if isAnonymous, let old = accessCredential, old.isAnonymous,
               old.expiresAt > responseDate, old.accessToken != credential.accessToken {
                previous.removeAll { $0.accessToken == old.accessToken }
                previous.insert(old, at: 0)
            }
            if !isAnonymous { previous = [] }
            guard Self.saveAccessCredentials(StoredCredentials(
                current: credential, previousAnonymous: previous)) else {
                throw URLError(.cannotWriteToFile)
            }
            accessCredential = credential
            previousAnonymousCredentials = previous
            nextExchangeAttemptAt = .distantPast
            unauthorizedAccessToken = nil
            scheduleRenewal()
            reconcile(force: true)
            return true
        } catch {
            if exchangeRevision == revision {
                logger.error("[PUSH] logTime=\(ClientLogTimestamp.now(), privacy: .public) Token exchange failed category=\(String(describing: type(of: error)), privacy: .public)")
                nextExchangeAttemptAt = Date().addingTimeInterval(30)
                scheduleExchangeRetry(revision: revision)
                if accessCredential?.isValid() == true {
                    reconcile()
                } else {
                    scheduleState = .waitingForAuthorization
                }
            }
            return false
        }
    }

    private func scheduleExchangeRetry(revision: Int) {
        guard !isPreparingForLogout else { return }
        exchangeRetryTask?.cancel()
        let delay = max(1, nextExchangeAttemptAt.timeIntervalSinceNow)
        exchangeRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.exchangeRevision == revision else { return }
            self.exchangeRetryTask = nil
            self.reconcile()
        }
    }

    private func scheduleRenewal() {
        renewalTask?.cancel()
        guard let credential = accessCredential else { return }
        let delay = max(1, credential.expiresAt.addingTimeInterval(-24 * 60 * 60).timeIntervalSinceNow)
        renewalTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.reconcile()
        }
    }

    func retry() {
        deliveryTask?.cancel()
        reconcile(force: true)
    }

    /// Call while the current clenson login token is still valid. The local
    /// activities are ended first, then the server receives an enabled=false
    /// full snapshot before the token is discarded and the device identity is
    /// rotated for the next account.
    @discardableResult
    func prepareForLogout() async -> Bool {
        guard !isPreparingForLogout else { return false }
        isPreparingForLogout = true
        defer { isPreparingForLogout = false }
        await TripActivityService.endAll()
        updateSchedule(tickets: tickets, selectedTicketID: selectedTicketID, enabled: false)
        await deliveryTask?.value
        let acknowledged = UserDefaults.standard.data(forKey: Self.acknowledgedKey)
            .flatMap { try? JSONDecoder().decode(ScheduleSnapshot.self, from: $0) }
        if endpoint != nil {
            guard scheduleState == .off, acknowledged?.enabled == false else { return false }
        } else {
            guard acknowledged?.enabled != true else { return false }
        }
        exchangeRevision += 1
        exchangeTask?.cancel()
        exchangeTask = nil
        exchangeRetryTask?.cancel()
        exchangeRetryTask = nil
        accessCredential = nil
        previousAnonymousCredentials = []
        sourceLoginToken = nil
        Self.clearAccessCredential()
        renewalTask?.cancel()
        unauthorizedAccessToken = nil
        didReexchangeAfterUnauthorized = false
        rejectedSnapshot = nil
        authenticationRequired = false
        desired = nil
        rotateDeviceID()
        scheduleState = .off
        return true
    }

    func registrations() -> [Registration] {
        guard let data = UserDefaults.standard.data(forKey: Self.registrationsKey),
              let values = try? JSONDecoder().decode([Registration].self, from: data) else { return [] }
        return values
    }

    private func store(_ registration: Registration) {
        var values = registrations()
        if values.contains(where: { $0.kind == registration.kind && $0.activityID == registration.activityID
            && $0.token == registration.token && $0.departureAt == registration.departureAt }) {
            return
        }
        values.removeAll { $0.kind == registration.kind && $0.activityID == registration.activityID }
        values.append(registration)
        saveRegistrations(values)
        logger.info("[PUSH] logTime=\(ClientLogTimestamp.now(), privacy: .public) Activity token stored kind=\(registration.kind.rawValue, privacy: .public) activityID=\(registration.activityID ?? "nil", privacy: .public) ticketID=\(registration.ticketID?.uuidString ?? "nil", privacy: .public)")
        reconcile()
    }

    private func saveRegistrations(_ values: [Registration]) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults.standard.set(data, forKey: Self.registrationsKey)
    }

    private func snapshotVersion(for content: ScheduleSnapshot, acknowledged: ScheduleSnapshot?) -> Int64 {
        let issued = (UserDefaults.standard.object(forKey: Self.issuedVersionKey) as? NSNumber)?.int64Value ?? 0
        if let desired, desired.matchesContent(of: content), desired.snapshotVersion >= issued {
            return desired.snapshotVersion
        }
        if let acknowledged, acknowledged.matchesContent(of: content), acknowledged.snapshotVersion >= issued {
            return acknowledged.snapshotVersion
        }
        let nowMillis = Int64(Date().timeIntervalSince1970 * 1000)
        let version = max(issued + 1, nowMillis)
        UserDefaults.standard.set(version, forKey: Self.issuedVersionKey)
        return version
    }

    private func reconcile(force: Bool = false) {
        let acknowledged = UserDefaults.standard.data(forKey: Self.acknowledgedKey)
            .flatMap { try? JSONDecoder().decode(ScheduleSnapshot.self, from: $0) }
        if !enabled, acknowledged?.enabled != true, desired?.enabled != true,
           !isPreparingForLogout {
            scheduleState = .off
            return
        }
        guard let endpoint else {
            scheduleState = enabled ? .notConfigured : .off
            return
        }
        if UserDefaults.standard.string(forKey: Self.forbiddenDeviceIDKey) == deviceID.uuidString {
            scheduleState = .identityConflict
            return
        }
        let token = registrations().first(where: { $0.kind == .pushToStart })?.token
        if !authenticationRequired,
           (accessCredential == nil || accessCredential?.needsRenewal() == true ||
            unauthorizedAccessToken == accessCredential?.accessToken),
           exchangeTask == nil, !isPreparingForLogout, Date() >= nextExchangeAttemptAt {
            let revision = exchangeRevision
            exchangeTask = Task { [weak self] in
                await self?.exchangeAccessToken(revision: revision) ?? false
            }
        }
        guard let credential = accessCredential, credential.isValid() else {
            scheduleState = .waitingForAuthorization
            return
        }
        if authenticationRequired {
            scheduleState = .waitingForAuthorization
            return
        }
        if unauthorizedAccessToken == credential.accessToken {
            scheduleState = .waitingForAuthorization
            return
        }
        let scheduled = enabled ? tickets.compactMap { ScheduledTicket($0, now: Date()) } : []
        let activityTokens = registrations().filter { registration in
            registration.kind == .activity && scheduled.contains {
                $0.id == registration.ticketID && $0.departureAt == registration.departureAt
            }
        }
        let selectedForSnapshot: UUID?
        if enabled, let selectedTicketID,
           scheduled.contains(where: { $0.id == selectedTicketID }) {
            selectedForSnapshot = selectedTicketID
        } else {
            selectedForSnapshot = nil
        }
        let content = ScheduleSnapshot(deviceID: deviceID, snapshotVersion: 0, enabled: enabled,
                                        pushToStartToken: enabled ? token : nil,
                                        selectedTicketID: selectedForSnapshot,
                                        tickets: scheduled.sorted { $0.departureAt < $1.departureAt },
                                        activityTokens: enabled ? activityTokens : [])
        let snapshot = content.withVersion(snapshotVersion(for: content, acknowledged: acknowledged))
        if snapshot == rejectedSnapshot {
            scheduleState = .failed
            return
        }
        if !force && !needsForegroundUpload && snapshot == acknowledged && deliveryTask == nil {
            desired = snapshot
            scheduleState = state(for: snapshot)
            return
        }
        if !force && snapshot == desired && deliveryTask != nil { return }
        desired = snapshot
        let previousDelivery = deliveryTask
        previousDelivery?.cancel()
        deliveryTask = Task { [weak self] in
            guard let self else { return }
            await previousDelivery?.value
            guard !Task.isCancelled, self.desired == snapshot else { return }
            while !Task.isCancelled {
                let wait = self.nextScheduleAttemptAt.timeIntervalSinceNow
                if wait > 0 {
                    try? await Task.sleep(for: .seconds(wait))
                    guard !Task.isCancelled, self.desired == snapshot else { return }
                }
                self.scheduleState = .sending
                do {
                    let request = try Self.scheduleRequest(
                        for: snapshot, endpoint: endpoint, accessToken: credential.accessToken)
                    self.logger.info("[PUSH] logTime=\(ClientLogTimestamp.now(), privacy: .public) Activity snapshot PUT started enabled=\(snapshot.enabled) tickets=\(snapshot.tickets.count) hasStartToken=\(snapshot.pushToStartToken != nil) activityTokens=\(snapshot.activityTokens.count)")
                    let liveActivities = Activity<TripActivityAttributes>.activities
                    for ticket in snapshot.tickets {
                        let live = liveActivities.filter { $0.attributes.ticketID == ticket.id }
                        let uploadedCount = snapshot.activityTokens.filter { $0.ticketID == ticket.id }.count
                        self.logger.info("[PUSH] logTime=\(ClientLogTimestamp.now(), privacy: .public) Activity snapshot ticket ticketID=\(ticket.id.uuidString, privacy: .public) selected=\(snapshot.selectedTicketID == ticket.id) liveActivities=\(live.count) uploadedTokens=\(uploadedCount)")
                    }
                    let (data, response) = try await URLSession.shared.data(for: request)
                    guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                    self.logger.info("[PUSH] logTime=\(ClientLogTimestamp.now(), privacy: .public) Activity snapshot PUT completed httpStatus=\(response.statusCode)")
                    if response.statusCode == 409 {
                        let result = try JSONDecoder().decode(ScheduleResponse.self, from: data)
                        throw ScheduleError.staleVersion(Int64(result.data ?? 0))
                    }
                    guard response.statusCode == 200 else {
                        throw ScheduleError.httpStatus(response.statusCode)
                    }
                    let result = try JSONDecoder().decode(ScheduleResponse.self, from: data)
                    self.logger.info("[PUSH] logTime=\(ClientLogTimestamp.now(), privacy: .public) Activity snapshot businessCode=\(result.code)")
                    guard result.confirmsSnapshotSaved(httpStatus: response.statusCode),
                          let version = result.data else {
                        throw ScheduleError.rejected(code: result.code, message: result.err ?? "")
                    }
                    self.logger.info("[PUSH] logTime=\(ClientLogTimestamp.now(), privacy: .public) Activity snapshot saved version=\(version)")
                    guard self.desired == snapshot, !Task.isCancelled else { return }
                    UserDefaults.standard.set(try JSONEncoder().encode(snapshot), forKey: Self.acknowledgedKey)
                    self.needsForegroundUpload = false
                    self.lastSuccessfulUploadAt = Date()
                    self.didReexchangeAfterUnauthorized = false
                    self.unauthorizedAccessToken = nil
                    self.scheduleRetryDelay = 2
                    self.nextScheduleAttemptAt = .distantPast
                    self.scheduleState = self.state(for: snapshot)
                    self.deliveryTask = nil
                    return
                } catch let error as ScheduleError {
                    guard self.desired == snapshot, !Task.isCancelled else { return }
                    switch error {
                    case .staleVersion(let serverVersion):
                        let issued = (UserDefaults.standard.object(forKey: Self.issuedVersionKey) as? NSNumber)?.int64Value ?? 0
                        UserDefaults.standard.set(max(issued, serverVersion), forKey: Self.issuedVersionKey)
                        self.desired = nil
                        self.deliveryTask = nil
                        self.reconcile(force: true)
                        return
                    case .httpStatus(401), .rejected(code: 114, message: _):
                        self.unauthorizedAccessToken = credential.accessToken
                        self.scheduleState = .waitingForAuthorization
                        self.deliveryTask = nil
                        if !self.didReexchangeAfterUnauthorized, !self.isPreparingForLogout {
                            self.didReexchangeAfterUnauthorized = true
                            let revision = self.exchangeRevision
                            let task = Task { [weak self] in
                                await self?.exchangeAccessToken(revision: revision) ?? false
                            }
                            self.exchangeTask = task
                            _ = await task.value
                        } else if !self.isPreparingForLogout {
                            self.authenticationRequired = true
                        }
                        return
                    case .httpStatus(403), .rejected(code: 403, message: _):
                        UserDefaults.standard.set(snapshot.deviceID.uuidString, forKey: Self.forbiddenDeviceIDKey)
                        self.logger.error("[PUSH] logTime=\(ClientLogTimestamp.now(), privacy: .public) Activity schedule device identity is bound to another account")
                        self.scheduleState = .identityConflict
                        self.deliveryTask = nil
                        return
                    case .httpStatus(400), .rejected(code: 400, message: _):
                        self.rejectedSnapshot = snapshot
                        self.logger.error("[PUSH] logTime=\(ClientLogTimestamp.now(), privacy: .public) Activity schedule rejected with a non-retryable response")
                        self.scheduleState = .failed
                        self.deliveryTask = nil
                        return
                    default:
                        self.logger.error("[PUSH] logTime=\(ClientLogTimestamp.now(), privacy: .public) Activity schedule registration failed")
                    }
                    self.scheduleState = .failed
                    if self.isPreparingForLogout {
                        self.deliveryTask = nil
                        return
                    }
                    self.scheduleNextAttempt()
                    try? await Task.sleep(for: .seconds(max(1, self.nextScheduleAttemptAt.timeIntervalSinceNow)))
                } catch {
                    guard self.desired == snapshot, !Task.isCancelled else { return }
                    self.logger.error("[PUSH] logTime=\(ClientLogTimestamp.now(), privacy: .public) Activity schedule registration failed category=\(String(describing: type(of: error)), privacy: .public)")
                    self.scheduleState = .failed
                    if self.isPreparingForLogout {
                        self.deliveryTask = nil
                        return
                    }
                    self.scheduleNextAttempt()
                    try? await Task.sleep(for: .seconds(max(1, self.nextScheduleAttemptAt.timeIntervalSinceNow)))
                }
            }
        }
    }

    private func scheduleNextAttempt() {
        nextScheduleAttemptAt = Date().addingTimeInterval(scheduleRetryDelay)
        scheduleRetryDelay = min(scheduleRetryDelay * 2, 300)
    }

    private func state(for snapshot: ScheduleSnapshot) -> ScheduleState {
        guard snapshot.enabled else { return .off }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return .systemDisabled }
        return snapshot.pushToStartToken == nil ? .waitingForPushToken : .registered
    }

    private var endpoint: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "WristTripScheduleURL") as? String,
              let url = URL(string: raw), url.scheme == "https", url.host != nil,
              url.path == "/api/activity-schedules" else { return nil }
        return url
    }

    private var exchangeURL: URL? {
        guard let endpoint else { return nil }
        return Self.exchangeURL(for: endpoint)
    }

    nonisolated static func exchangeURL(for scheduleURL: URL) -> URL? {
        guard var components = URLComponents(url: scheduleURL, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.host != nil,
              components.path == "/api/activity-schedules" else { return nil }
        components.path = "/api/auth/token/exchange"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    nonisolated static func scheduleRequest(for snapshot: ScheduleSnapshot, endpoint: URL,
                                            accessToken: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(snapshot)
        return request
    }

    private var deviceID: UUID {
        if let raw = UserDefaults.standard.string(forKey: Self.deviceIDKey), let id = UUID(uuidString: raw) { return id }
        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: Self.deviceIDKey)
        return id
    }

    private func rotateDeviceID() {
        UserDefaults.standard.set(UUID().uuidString, forKey: Self.deviceIDKey)
        UserDefaults.standard.removeObject(forKey: Self.acknowledgedKey)
        UserDefaults.standard.removeObject(forKey: Self.forbiddenDeviceIDKey)
        desired = nil
        rejectedSnapshot = nil
        unauthorizedAccessToken = nil
    }

    nonisolated static func hexToken(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private static func loadAccessCredentials() -> StoredCredentials? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: authorizationTokenService,
            kSecAttrAccount: authorizationTokenKey,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        if let stored = try? JSONDecoder().decode(StoredCredentials.self, from: data) {
            return stored
        }
        guard let credential = try? JSONDecoder().decode(AccessCredential.self, from: data) else { return nil }
        return StoredCredentials(current: credential, previousAnonymous: [])
    }

    @discardableResult
    private static func saveAccessCredentials(_ credentials: StoredCredentials) -> Bool {
        let baseQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: authorizationTokenService,
            kSecAttrAccount: authorizationTokenKey
        ]
        guard let data = try? JSONEncoder().encode(credentials) else { return false }
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = baseQuery
            attributes.forEach { addQuery[$0.key] = $0.value }
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        }
        return status == errSecSuccess
    }

    private static func clearAccessCredential() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: authorizationTokenService,
            kSecAttrAccount: authorizationTokenKey
        ]
        _ = SecItemDelete(query as CFDictionary)
    }

    struct ScheduleResponse: Decodable {
        let code: Int
        let data: Int?
        let err: String?

        func confirmsSnapshotSaved(httpStatus: Int) -> Bool {
            httpStatus == 200 && code == 0 && (data ?? 0) > 0
        }
    }

    enum ScheduleError: Error {
        case httpStatus(Int)
        case rejected(code: Int, message: String)
        case staleVersion(Int64)
    }
}
