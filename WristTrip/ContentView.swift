import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedTab = 0
    @StateObject private var tripStore = TripStore()
    @State private var showingImport = false
    @State private var showingWatch = false
    @State private var showingCurrentDetail = false
    @State private var currentDetailTicketID: UUID?
    @State private var toast: String?
    @State private var watchSyncFeedback: String?
    @State private var clock = Date()
    @State private var sharedImageURL: URL?
    @State private var sharedImage: UIImage?
    @State private var syncGeneration = 0
    @State private var activityFeedback: String?
    @State private var demoFeedback: String?
    @State private var activityRefreshTask: Task<Void, Never>?
    @State private var activityGeneration = 0
    @AppStorage("wristTrip.liveActivitiesEnabled") private var liveActivitiesEnabled = true
    @AppStorage("wristTrip.appearanceMode") private var appearanceModeRaw = AppearanceMode.system.rawValue

    private var tickets: [Ticket] { tripStore.tickets }

    private var currentTicket: Ticket? {
        tripStore.currentTicket(at: clock)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { tripList }
                .tabItem { Label("行程", systemImage: "list.bullet.rectangle.portrait") }.tag(0)
            NavigationStack {
                if let ticket = currentTicket {
                    WatchPreview(ticket: displayTicket(ticket), onSync: syncCurrent)
                } else {
                    watchEmptyState
                }
            }
                .tabItem { Label("智能叠放", systemImage: "applewatch") }.tag(1)
            NavigationStack {
                SettingsView(showingWatch: $showingWatch, toast: $toast,
                             liveActivitiesEnabled: $liveActivitiesEnabled,
                             appearanceModeRaw: $appearanceModeRaw,
                             onDeleteAll: deleteAllTickets,
                             onLiveActivitiesChanged: { _ in refreshActivity() })
                    .navigationTitle("设置")
            }
                .tabItem { Label("设置", systemImage: "gearshape") }.tag(2)
        }
        .tint(.indigo)
        .preferredColorScheme(AppearanceMode(rawValue: appearanceModeRaw)?.colorScheme)
        .sheet(isPresented: $showingImport, onDismiss: finishImport) {
                ReviewView(initialImage: sharedImage, onSave: { newTicket in
                    tripStore.add(newTicket)
                    showingImport = false
                    syncSnapshot(changedTicketID: newTicket.id)
                    refreshActivity()
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
        .sheet(isPresented: $showingCurrentDetail) {
            if let id = currentDetailTicketID, let ticket = tickets.first(where: { $0.id == id }) {
                NavigationStack {
                    TicketDetailView(ticket: displayTicket(ticket), demoFeedback: $demoFeedback,
                                     onSync: { syncTicket(id: ticket.id) },
                                     onDemo: { startActivityDemo(id: ticket.id) },
                                     onDelete: { deleteTicket(id: ticket.id); showingCurrentDetail = false },
                                     onUpdate: { saveEditedTicket($0) })
                        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("完成") { showingCurrentDetail = false } } }
                }
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                if let watchSyncFeedback {
                    Text(watchSyncFeedback).font(.subheadline.weight(.medium)).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 11)
                        .background(.indigo, in: Capsule())
                        .task(id: watchSyncFeedback) {
                            try? await Task.sleep(for: .seconds(4))
                            if self.watchSyncFeedback == watchSyncFeedback { self.watchSyncFeedback = nil }
                        }
                }
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
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                checkSharedInbox()
                refreshActivity()
            }
        }
        .task {
            checkSharedInbox()
            refreshActivity()
            while !Task.isCancelled {
                refreshStatuses()
                try? await Task.sleep(for: .seconds(60))
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("行程").font(.title2.weight(.bold))
                if let ticket = currentTicket { CurrentTicketCard(ticket: displayTicket(ticket), onSync: syncCurrent, onWatch: { showingWatch = true }, onDetail: { currentDetailTicketID = ticket.id; showingCurrentDetail = true }) }
                if !tickets.isEmpty, let activityFeedback {
                    Label(activityFeedback, systemImage: "bolt.horizontal.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if tickets.isEmpty {
                    ContentUnavailableView("暂无行程", systemImage: "ticket", description: Text("导入 12306 订单截图以添加车票"))
                }
                sectionHeader("接下来的行程", action: "导入车票") { showingImport = true }
                ForEach(tripStore.sortedTickets().filter { $0.status(at: clock) != .arrived && $0.id != currentTicket?.id }) { ticket in NavigationLink { TicketDetailView(ticket: displayTicket(ticket), demoFeedback: $demoFeedback, onSync: { syncTicket(id: ticket.id) }, onDemo: { startActivityDemo(id: ticket.id) }, onDelete: { deleteTicket(id: ticket.id) }, onUpdate: { saveEditedTicket($0) }) } label: { TicketRow(ticket: displayTicket(ticket)) }.buttonStyle(.plain) }
                sectionHeader("历史记录", action: nil, actionHandler: nil)
                ForEach(tripStore.sortedTickets().filter { $0.status(at: clock) == .arrived }) { ticket in NavigationLink { TicketDetailView(ticket: displayTicket(ticket), demoFeedback: $demoFeedback, onSync: { syncTicket(id: ticket.id) }, onDemo: { startActivityDemo(id: ticket.id) }, onDelete: { deleteTicket(id: ticket.id) }, onUpdate: { saveEditedTicket($0) }) } label: { TicketRow(ticket: displayTicket(ticket)) }.buttonStyle(.plain) }
                Label("信息来自导入截图与手动修改，不代表铁路实时状态", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
            }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
        }
        .background(TripPalette.page(for: colorScheme).ignoresSafeArea()).navigationTitle("行程")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { showingImport = true } label: { Image(systemName: "plus") }.accessibilityLabel("导入车票") } }
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
        syncSnapshot(changedTicketID: id, selectedTicketID: id, manual: true)
    }

    private func startActivityDemo(id: UUID) {
        demoFeedback = nil
        guard let ticket = tripStore.tickets.first(where: { $0.id == id }) else { return }
        guard liveActivitiesEnabled else {
            demoFeedback = "请先在设置中开启本机实时活动"
            return
        }
        activityGeneration += 1
        let generation = activityGeneration
        let previous = activityRefreshTask
        previous?.cancel()
        activityRefreshTask = Task { @MainActor in
            _ = await previous?.value
            guard generation == activityGeneration else { return }
            do {
                let result = try await TripActivityService.startDemo(ticket: ticket)
                guard generation == activityGeneration else { return }
                switch result {
                case .demoActive:
                    demoFeedback = "演示实时活动已启动，可在 iPhone 锁屏查看。配对手表的智能叠放由系统决定何时展示。"
                case .disabled:
                    demoFeedback = "系统实时活动权限未开启，请在 iPhone 设置中启用"
                default: break
                }
            } catch {
                demoFeedback = "演示启动失败：\(error.localizedDescription)"
            }
        }
    }

    private func syncSnapshot(changedTicketID: UUID? = nil, selectedTicketID: UUID? = nil, manual: Bool = false) {
        syncGeneration += 1
        let generation = syncGeneration
        let selection = selectedTicketID ?? tripStore.selectedTicketID ?? tripStore.currentTicket(at: clock)?.id
        WatchSyncService.shared.sync(tickets: tripStore.tickets, selectedTicketID: selection) { result in
            guard generation == syncGeneration else { return }
            switch result {
            case .success(let receipt):
                switch receipt.delivery {
                case .confirmed:
                    setSyncText("手表已保存", for: changedTicketID)
                    if manual { watchSyncFeedback = "手表 App 已保存 \(receipt.ticketCount) 张车票" }
                case .queued:
                    setSyncText("等待手表接收", for: changedTicketID)
                    if manual { watchSyncFeedback = "已加入手表 App 同步队列（\(receipt.ticketCount) 张）" }
                }
            case .failure(let error):
                setSyncText("手表同步失败", for: changedTicketID)
                if manual { watchSyncFeedback = error.localizedDescription }
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
        syncSnapshot(changedTicketID: ticket.id)
        refreshActivity()
    }

    private func deleteTicket(id: UUID) {
        tripStore.delete(id: id)
        syncSnapshot()
        refreshActivity()
    }

    private func refreshActivity(requestedTicketID: UUID? = nil, reportToUser: Bool = false) {
        activityGeneration += 1
        let generation = activityGeneration
        let previous = activityRefreshTask
        let snapshot = tripStore.tickets
        let selectedID = tripStore.selectedTicketID ?? tripStore.currentTicket(at: clock)?.id
        activityRefreshTask = Task { @MainActor in
            _ = await previous?.value
            guard generation == activityGeneration else { return }
            guard liveActivitiesEnabled else {
                await TripActivityService.endAll()
                guard generation == activityGeneration else { return }
                activityFeedback = "本机实时活动开关已关闭"
                if reportToUser { toast = activityFeedback }
                return
            }
            do {
                let result = try await TripActivityService.refresh(tickets: snapshot, selectedTicketID: selectedID, requestedTicketID: requestedTicketID)
                guard generation == activityGeneration else { return }
                switch result {
                case .started(let id), .updated(let id):
                    activityFeedback = id == requestedTicketID || requestedTicketID == nil
                        ? "已启动 iPhone 实时活动；配对手表的智能叠放由系统决定何时展示"
                        : "当前乘坐车次优先展示；所选车次尚未显示"
                case .ended: activityFeedback = "实时活动已结束"
                case .noEligibleTicket: activityFeedback = "当前无符合展示条件的车票"
                case .draft: activityFeedback = "车票信息不完整：请补齐车次、站名和计划出发／到站时间"
                case .notInWindow(let start):
                    activityFeedback = "尚未进入发车前 3 小时窗口（\(start.formatted(date: .abbreviated, time: .shortened)) 起）；离开 App 后自动启动尚未接入"
                case .arrived: activityFeedback = "计划到站时间已过，不会启动实时活动"
                case .timeLimitReached: activityFeedback = "已超过单次实时活动的 8 小时展示上限"
                case .disabled: activityFeedback = "系统实时活动权限未开启，请在 iPhone 设置中启用"
                case .demoActive: activityFeedback = "演示实时活动运行中；配对手表的智能叠放由系统决定何时展示"
                }
                if reportToUser { toast = activityFeedback }
            } catch {
                guard generation == activityGeneration else { return }
                activityFeedback = "实时活动启动失败：\(error.localizedDescription)"
                if reportToUser { toast = activityFeedback }
            }
        }
    }

    private func checkSharedInbox() {
        guard !showingImport else { return }
        for url in SharedImageInbox.pendingImageURLs() {
            guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else {
                SharedImageInbox.remove(url)
                continue
            }
            sharedImageURL = url
            sharedImage = image
            showingImport = true
            return
        }
    }

    private func finishImport() {
        if let sharedImageURL { SharedImageInbox.remove(sharedImageURL) }
        sharedImageURL = nil
        sharedImage = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            checkSharedInbox()
        }
    }

    private func displayTicket(_ ticket: Ticket) -> Ticket {
        var copy = ticket
        copy.refreshStatus(at: clock)
        return copy
    }

    private func refreshStatuses() {
        clock = Date()
        var changed = false
        for index in tickets.indices {
            let resolved = tickets[index].status(at: clock)
            if tickets[index].status != resolved {
                var ticket = tickets[index]
                ticket.status = resolved
                tripStore.update(ticket)
                changed = true
            }
        }
        if changed || !tickets.isEmpty { refreshActivity() }
    }

    private func deleteAllTickets() {
        tripStore.removeAll()
        syncSnapshot()
        refreshActivity()
    }
}

struct ContentView_Previews: PreviewProvider { static var previews: some View { ContentView() } }
