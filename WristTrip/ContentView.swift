import SwiftUI
import ActivityKit
import OSLog

private struct ImportRequest: Identifiable {
    let id = UUID()
    let image: UIImage?
    let sharedImageURL: URL?
}

struct ContentView: View {
    private static let logger = Logger(subsystem: "com.clenson.WristTrip", category: "UI")
    private let onReady: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var tripStore = TripStore()
    @StateObject private var pushService = ActivityPushTokenService.shared
    @State private var importRequest: ImportRequest?
    @State private var showingWatch = false
    @State private var currentDetailTicket: Ticket?
    @State private var pendingHistoryDeletionID: UUID?
    @State private var toast: String?
    @State private var clock = Date()
    @State private var sharedImageURL: URL?
    @State private var deferredSharedImageURLs: Set<URL> = []
    @State private var shareImportError: String?
    @State private var syncGeneration = 0
    @State private var activityFeedback: String?
    @State private var activityRefreshTask: Task<Void, Never>?
    @State private var nextRefreshAt: Date?
    @State private var activityGeneration = 0
    @AppStorage("wristTrip.liveActivitiesEnabled") private var liveActivitiesEnabled = true
    @AppStorage("wristTrip.appearanceMode") private var appearanceModeRaw = AppearanceMode.system.rawValue

    init(onReady: @escaping () -> Void = {}) {
        self.onReady = onReady
    }

    private var tickets: [Ticket] { tripStore.tickets }

    private var currentTicket: Ticket? {
        tripStore.currentTicket(at: clock)
    }

    var body: some View {
        TabView {
            NavigationStack { tripList }
                .tabItem { Label("行程", systemImage: "list.bullet.rectangle.portrait") }
            NavigationStack {
                SettingsView(showingWatch: $showingWatch, toast: $toast,
                             liveActivitiesEnabled: $liveActivitiesEnabled,
                             appearanceModeRaw: $appearanceModeRaw,
                             onDeleteAll: deleteAllTickets,
                             onLiveActivitiesChanged: { _ in refreshActivity() })
                .navigationTitle("设置")
            }
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .tint(.indigo)
        .sheet(item: $importRequest, onDismiss: finishImport) { request in
                ReviewView(initialImage: request.image,
                           onRecognitionSuccess: {
                    if let url = request.sharedImageURL { finishSharedImageRecognition(url) }
                },
                           onSave: { newTicket in
                    tripStore.add(newTicket)
                    importRequest = nil
                    syncSnapshot(changedTicketID: newTicket.id)
                    // A foreground save must not wait for the server's START job.
                    refreshActivity(startAutomaticallyLocally: true)
                }, isDuplicate: { tripStore.duplicate(of: $0) != nil })
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showingWatch) {
            NavigationStack {
                if let ticket = currentTicket {
                    WatchPreview(ticket: displayTicket(ticket), onSync: syncCurrent)
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { showingWatch = false } } }
                } else {
                    watchEmptyState
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完成") { showingWatch = false } } }
                }
            }
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $currentDetailTicket) { presentedTicket in
            NavigationStack {
                TicketDetailView(ticket: displayTicket(tickets.first(where: { $0.id == presentedTicket.id }) ?? presentedTicket),
                                 onSync: { syncTicket(id: presentedTicket.id) },
                                 onDelete: { deleteTicket(id: presentedTicket.id); currentDetailTicket = nil },
                                 onUpdate: { updated in
                                     saveEditedTicket(updated)
                                 },
                                 onRefresh: { await tripStore.refreshStationInfoAndWait(for: presentedTicket.id, force: true) },
                                 onAppearRefresh: { tripStore.refreshStationInfo(for: presentedTicket.id) })
                    .toolbar { ToolbarItem(placement: .topBarLeading) { Button("完成") { currentDetailTicket = nil } } }
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                if let toast {
                    Text(toast).font(.subheadline.weight(.medium)).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 11)
                        .background(.black.opacity(0.85), in: Capsule())
                        .task(id: toast) {
                            try? await Task.sleep(for: .seconds(4))
                            if self.toast == toast { self.toast = nil }
                        }
                }
            }
            .padding(.bottom, 70)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .animation(.easeInOut, value: toast)
        .alert("分享导入失败", isPresented: Binding(
            get: { shareImportError != nil },
            set: { if !$0 { shareImportError = nil } }
        )) {
            Button("确定", role: .cancel) { shareImportError = nil }
            Button("重试") {
                shareImportError = nil
                deferredSharedImageURLs.removeAll()
                checkSharedInbox()
            }
        } message: {
            Text(shareImportError ?? "")
        }
        .onOpenURL { url in
            guard url.scheme == "wristtrip", url.host == "import" else { return }
            checkSharedInbox()
            if shareImportError == nil,
               let error = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "receiveError" })?.value {
                shareImportError = "部分图片接收失败：\(error)"
            }
        }
        .onChange(of: tripStore.stationInfoRevision) { _, _ in
            syncSnapshot()
            refreshActivity()
        }
        .onChange(of: scenePhase) { _, phase in
            Self.logger.info("[UI] logTime=\(ClientLogTimestamp.now(), privacy: .public) scenePhase changed to \(String(describing: phase), privacy: .public) tickets=\(tickets.count)")
            if phase == .active {
                pushService.refreshOnForeground()
                checkSharedInbox()
                tripStore.load()
                refreshStatuses(syncWatch: true)
            } else {
                nextRefreshAt = nil
                activityRefreshTask?.cancel()
                TripBackgroundRefreshService.schedule(tickets: tickets)
            }
        }
        .task(id: nextRefreshAt) {
            guard let deadline = nextRefreshAt else { return }
            do {
                try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
            } catch { return }
            guard !Task.isCancelled, scenePhase == .active else { return }
            refreshStatuses(syncWatch: true)
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            checkSharedInbox()
            onReady()
            while !Task.isCancelled {
                refreshStatuses()
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    break
                }
            }
        }
    }

    private var watchEmptyState: some View {
        Group {
            if tickets.isEmpty {
                ContentUnavailableView("暂无车票", systemImage: "ticket", description: Text("导入车票后可查看手表卡片预览"))
            } else {
                ContentUnavailableView("暂无当前车次", systemImage: "ticket", description: Text("历史车票仍可在手表应用中查看"))
            }
        }
    }

    private var tripList: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("当前行程").font(.title2.weight(.bold))
                    if let ticket = currentTicket {
                        CurrentTicketCard(ticket: displayTicket(ticket), onSync: { syncTicket(id: ticket.id) },
                                          onWatch: { showingWatch = true },
                                          onDetail: { currentDetailTicket = ticket })
                    }
                    if !tickets.isEmpty, let activityFeedback {
                        Label(activityFeedback, systemImage: "bolt.horizontal.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if tickets.isEmpty {
                        ContentUnavailableView("暂无行程", systemImage: "ticket", description: Text("导入 12306 订单截图以添加车票"))
                    }
                    sectionHeader("接下来的行程", action: "导入车票") { presentManualImport() }
                    ForEach(tripStore.sortedTickets().filter { $0.status(at: clock) != .arrived && $0.id != currentTicket?.id }) { ticket in
                        NavigationLink {
                                             TicketDetailView(ticket: displayTicket(ticket),
                                             onSync: { syncTicket(id: ticket.id) },
                                             onDelete: { deleteTicket(id: ticket.id) },
                                             onUpdate: { saveEditedTicket($0) },
                                             onRefresh: { await tripStore.refreshStationInfoAndWait(for: ticket.id, force: true) },
                                             onAppearRefresh: { tripStore.refreshStationInfo(for: ticket.id) })
                        } label: {
                            TicketRow(ticket: displayTicket(ticket))
                        }
                        .buttonStyle(.plain)
                    }
                    sectionHeader("历史记录", action: nil, actionHandler: nil)
                    ForEach(tripStore.sortedTickets().filter { $0.status(at: clock) == .arrived }) { ticket in
                        NavigationLink {
                            TicketDetailView(ticket: displayTicket(ticket),
                                             onSync: { syncTicket(id: ticket.id) },
                                             onDelete: { deleteTicket(id: ticket.id) },
                                             onUpdate: { saveEditedTicket($0) },
                                             onRefresh: { await tripStore.refreshStationInfoAndWait(for: ticket.id, force: true) },
                                             onAppearRefresh: { tripStore.refreshStationInfo(for: ticket.id) })
                        } label: {
                            TicketRow(ticket: displayTicket(ticket))
                        }
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                        .highPriorityGesture(
                            LongPressGesture(minimumDuration: 0.5)
                                .onEnded { _ in
                                    pendingHistoryDeletionID = ticket.id
                                }
                        )
                        .accessibilityHint("长按后确认删除")
                    }
                    Label("信息来自导入截图与手动修改，不代表铁路实时状态", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
            }
        }
        .background(TripPalette.page(for: colorScheme).ignoresSafeArea())
        .navigationTitle("行程")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { presentManualImport() } label: { Image(systemName: "plus") }.accessibilityLabel("导入车票") } }
        .alert("删除这条历史车票？", isPresented: Binding(
            get: { pendingHistoryDeletionID != nil },
            set: { if !$0 { pendingHistoryDeletionID = nil } }
        )) {
            Button("取消", role: .cancel) { pendingHistoryDeletionID = nil }
            Button("确认删除", role: .destructive) {
                guard let id = pendingHistoryDeletionID else { return }
                pendingHistoryDeletionID = nil
                deleteTicket(id: id)
            }
        } message: {
            if let ticket = tickets.first(where: { $0.id == pendingHistoryDeletionID }) {
                Text("操作将删除本机保存的这条历史车票\r\n:\(ticket.train) · \(ticket.from) → \(ticket.to)\r\n且无法恢复")
            } else {
                Text("此操作将删除本机保存的这条历史车票，且无法恢复。")
            }
        }
    }

    private func sectionHeader(_ title: String, action: String?, actionHandler: (() -> Void)? = nil) -> some View {
        HStack { Text(title).font(.title3.weight(.bold)); Spacer(); if let action, let actionHandler { Button(action, action: actionHandler).font(.subheadline.weight(.medium)) } }
    }

    private func syncCurrent() {
        guard let id = currentTicket?.id else { return }
        syncTicket(id: id)
    }

    private func syncTicket(id: UUID) {
        tripStore.selectForWatch(id: id)
        refreshActivity(requestedTicketID: id, reportToUser: true)
        syncSnapshot(changedTicketID: id, selectedTicketID: id)
    }

    private func syncSnapshot(changedTicketID: UUID? = nil, selectedTicketID: UUID? = nil) {
        syncGeneration += 1
        let generation = syncGeneration
        // A nil selection is meaningful: the Watch app derives an active or
        // three-hour-window ticket from the same schedule rules. Do not pin a
        // far-future ticket during an arrival handoff.
        let selection = selectedTicketID ?? tripStore.selectedTicketID
        WatchSyncService.shared.sync(tickets: tripStore.tickets, selectedTicketID: selection, now: Date()) { result in
            guard generation == syncGeneration else { return }
            switch result {
            case .success(let receipt):
                switch receipt.delivery {
                case .confirmed:
                    setSyncText("手表已保存", for: changedTicketID)
                case .queued:
                    setSyncText("等待手表接收", for: changedTicketID)
                }
            case .failure(.appNotInstalled):
                // The Watch App is optional; Live Activity and Smart Stack do not require it.
                break
            case .failure:
                setSyncText("手表同步失败", for: changedTicketID)
            }
        }
    }

    private func setSyncText(_ text: String, for id: UUID?) {
        guard let id, var ticket = tripStore.tickets.first(where: { $0.id == id }) else { return }
        ticket.syncText = text
        tripStore.update(ticket)
    }

    private func saveEditedTicket(_ ticket: Ticket) {
        tripStore.update(ticket)
        // Recompute the status and watch selection before publishing either
        // external display. This also handles edits made while a journey is
        // already between departure and arrival.
        refreshStatuses(syncWatch: true, changedTicketID: ticket.id,
                        startAutomaticallyLocally: true)
    }

    private func deleteTicket(id: UUID) {
        tripStore.delete(id: id)
        syncSnapshot()
        refreshActivity()
    }

    private func refreshActivity(requestedTicketID: UUID? = nil, reportToUser: Bool = false,
                                 handoffTicketID: UUID? = nil,
                                 startAutomaticallyLocally: Bool = true) {
        clock = Date()
        Self.logger.info("[UI] logTime=\(ClientLogTimestamp.now(), privacy: .public) refreshActivity now=\(clock, privacy: .public) requested=\(String(describing: requestedTicketID), privacy: .public) handoff=\(String(describing: handoffTicketID), privacy: .public) selected=\(String(describing: tripStore.selectedTicketID), privacy: .public) tickets=\(tripStore.tickets.count)")
        scheduleStateRefresh()
        activityGeneration += 1
        let generation = activityGeneration
        let snapshot = tripStore.tickets
        let selectedID = tripStore.selectedTicketID ?? tripStore.currentTicket(at: clock)?.id
        pushService.updateSchedule(tickets: snapshot, selectedTicketID: selectedID,
                                   enabled: liveActivitiesEnabled)
        // Only the newest reconciliation is useful. Cancelling the previous
        // task prevents a burst of scene/status callbacks from building a
        // serial backlog while the app is under memory pressure.
        activityRefreshTask?.cancel()
        activityRefreshTask = Task { @MainActor in
            guard generation == activityGeneration else { return }
            let currentTicketIDs = Set(snapshot.map(\.id))
            let removedActivityTicketIDs = Set(Activity<TripActivityAttributes>.activities
                .map { $0.attributes.ticketID }
                .filter { !currentTicketIDs.contains($0) })
            await TripActivityService.endActivities(for: removedActivityTicketIDs)
            if !liveActivitiesEnabled {
                await TripActivityService.endAll()
            }
            guard liveActivitiesEnabled else {
                guard generation == activityGeneration else { return }
                scheduleStateRefresh()
                activityFeedback = "本机实时活动开关已关闭"
                if reportToUser { toast = activityFeedback }
                return
            }
            do {
                let result = try await TripActivityService.refresh(tickets: snapshot,
                                                                    selectedTicketID: selectedID,
                                                                    requestedTicketID: requestedTicketID,
                                                                    handoffTicketID: handoffTicketID,
                                                                    startAutomaticallyLocally: startAutomaticallyLocally)
                Self.logger.info("[UI] logTime=\(ClientLogTimestamp.now(), privacy: .public) ActivityKit result=\(String(describing: result), privacy: .public)")
                guard generation == activityGeneration else { return }
                switch result {
                case .started(let id), .updated(let id):
                    activityFeedback = id == requestedTicketID || requestedTicketID == nil
                        ? "已启动 iPhone 实时活动；配对手表的智能叠放由系统决定何时展示"
                        : "当前乘坐车次优先展示；所选车次尚未显示"
                case .restartedAfterTimeLimit:
                    activityFeedback = "行程仍在进行，已按 8 小时上限重新展示实时活动"
                case .ended: activityFeedback = "实时活动已结束"
                case .noEligibleTicket: activityFeedback = "当前无符合展示条件的车票"
                case .draft: activityFeedback = "车票信息不完整：请补齐车次、站名和计划出发／到站时间"
                case .arrived: activityFeedback = "行程已到站，实时活动已结束"
                case .disabled: activityFeedback = "系统实时活动权限未开启，请在 iPhone 设置中启用"
                case .remoteManaged: activityFeedback = "自动展示由服务端安排"
                case .notInAutomaticWindow(let start):
                    if start == .distantFuture {
                        activityFeedback = "尚未到自动展示时间，需在行程卡片手动显示"
                    } else {
                        activityFeedback = "尚未到自动展示时间，将在 \(start.formatted(date: .omitted, time: .shortened)) 自动展示"
                    }
                }
                scheduleStateRefresh()
                if reportToUser { toast = activityFeedback }
            } catch {
                Self.logger.error("[UI] logTime=\(ClientLogTimestamp.now(), privacy: .public) ActivityKit refresh failed: \(error.localizedDescription, privacy: .public)")
                guard generation == activityGeneration else { return }
                activityFeedback = "实时活动启动失败：\(error.localizedDescription)"
                if reportToUser { toast = activityFeedback }
            }
        }
    }

    private func scheduleStateRefresh() {
        let now = Date()
        nextRefreshAt = scenePhase == .active
            ? TripBackgroundRefreshService.nextBoundary(tickets: tickets, after: now,
                                                         manualDeadline: TripActivityService.nextManualActivityDeadline) : nil
        TripBackgroundRefreshService.schedule(tickets: tickets, now: now)
    }

    private func presentManualImport() {
        importRequest = ImportRequest(image: nil, sharedImageURL: nil)
    }

    private func checkSharedInbox() {
        guard importRequest == nil else { return }
        do {
            for url in try SharedImageInbox.pendingImageURLs() where !deferredSharedImageURLs.contains(url) {
                let data: Data
                do {
                    data = try Data(contentsOf: url)
                } catch {
                    deferredSharedImageURLs.insert(url)
                    shareImportError = "图片读取失败：\(error.localizedDescription)。共享文件已保留。"
                    return
                }
                guard let image = UIImage(data: data) else {
                    deferredSharedImageURLs.insert(url)
                    shareImportError = "图片读取失败：共享文件无法解码为图片。共享文件已保留。"
                    return
                }
                sharedImageURL = url
                importRequest = ImportRequest(image: image, sharedImageURL: url)
                return
            }
        } catch {
            shareImportError = "App Group 图片目录读取失败：\(error.localizedDescription)"
        }
    }

    private func finishSharedImageRecognition(_ url: URL) {
        guard sharedImageURL == url else { return }
        do {
            try SharedImageInbox.remove(url)
            self.sharedImageURL = nil
        } catch {
            deferredSharedImageURLs.insert(url)
            shareImportError = "图片识别成功，但清理共享文件失败：\(error.localizedDescription)"
        }
    }

    private func finishImport() {
        if let sharedImageURL { deferredSharedImageURLs.insert(sharedImageURL) }
        sharedImageURL = nil
    }

    private func displayTicket(_ ticket: Ticket) -> Ticket {
        var copy = ticket
        copy.refreshStatus(at: clock)
        return copy
    }

    private func refreshStatuses(syncWatch: Bool = false, changedTicketID: UUID? = nil,
                                 startAutomaticallyLocally: Bool = true) {
        let previousSelection = tripStore.selectedTicketID
        let previousSelectedTicket = previousSelection.flatMap { id in
            tripStore.tickets.first(where: { $0.id == id })
        }
        clock = Date()
        let changed = tripStore.refreshStatuses(at: clock)
        let statusLog = tripStore.tickets.map { "\($0.id.uuidString):\($0.status.rawValue)" }.joined(separator: ",")
        Self.logger.info("[UI] logTime=\(ClientLogTimestamp.now(), privacy: .public) refreshStatuses now=\(clock, privacy: .public) changed=\(changed) syncWatch=\(syncWatch) selection \(String(describing: previousSelection), privacy: .public) -> \(String(describing: tripStore.selectedTicketID), privacy: .public) statuses=\(statusLog, privacy: .public)")
        if changed || syncWatch { syncSnapshot(changedTicketID: changedTicketID) }
        let handoffTicketID: UUID?
        if let previousSelection,
           previousSelectedTicket?.plannedArrivalAt.map({ clock >= $0 }) == true,
           tripStore.selectedTicketID != previousSelection,
           let next = tripStore.selectedTicketID.flatMap({ id in tripStore.tickets.first { $0.id == id } }),
           next.isValidJourney, let start = next.startAt,
           let arrival = next.plannedArrivalAt, start <= clock, clock < arrival {
            handoffTicketID = tripStore.selectedTicketID
        } else {
            handoffTicketID = nil
        }
        refreshActivity(handoffTicketID: handoffTicketID,
                        startAutomaticallyLocally: startAutomaticallyLocally)
    }

    private func deleteAllTickets() {
        tripStore.removeAll()
        syncSnapshot()
        refreshActivity()
    }
}

struct ContentView_Previews: PreviewProvider { static var previews: some View { ContentView() } }
