import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct SettingsView: View {
    @Binding var showingWatch: Bool
    @Binding var toast: String?
    @Binding var liveActivitiesEnabled: Bool
    @Binding var remoteScheduleEnabled: Bool
    @ObservedObject var pushService: ActivityPushTokenService
    @Binding var appearanceModeRaw: String
    var onDeleteAll: () -> Void = {}
    var onLiveActivitiesChanged: (Bool) -> Void = { _ in }
    var onRemoteScheduleChanged: () -> Void = {}
    @State private var showingDeleteConfirmation = false

    var body: some View {
        Form {
            Section {
                Picker("外观", selection: $appearanceModeRaw) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("外观")
            }

            Section {
                Button { showingWatch = true } label: {
                    Label("预览智能叠放卡片", systemImage: "applewatch")
                }
                Toggle(isOn: $liveActivitiesEnabled) {
                    Label("本机实时活动", systemImage: "bolt.horizontal.circle")
                }
                .onChange(of: liveActivitiesEnabled) { _, enabled in
                    onLiveActivitiesChanged(enabled)
                }
                Toggle(isOn: $remoteScheduleEnabled) {
                    Label("自动展示", systemImage: "clock.arrow.circlepath")
                }
                .disabled(!liveActivitiesEnabled)
                .onChange(of: remoteScheduleEnabled) { _, _ in onRemoteScheduleChanged() }
                if remoteScheduleEnabled {
                    HStack {
                        Text(pushService.scheduleState.message).foregroundStyle(.secondary)
                        Spacer()
                        if pushService.scheduleState == .failed {
                            Button("重试") { pushService.retry() }
                        }
                    }
                    .font(.footnote)
                }
            } header: {
                Text("设备")
            } footer: {
                Text("自动展示会向服务端发送车次、站点、座位、计划时间和实时活动令牌以安排推送。Watch App 仅用于可选的离线查看。")
            }

            Section {
                Label("本机 OCR 处理", systemImage: "lock.shield")
                Text("截图和 OCR 原文仅在本机处理；订单号仅保存在本机。实时活动会显示在锁屏，Apple Watch 智能叠放是否展示由系统决定。车次状态按计划时间推算，不代表铁路实时状态。")
            } header: {
                Text("数据与隐私")
            }

            Section {
                Button("删除所有本地车票", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            } footer: {
                Text("删除当前设备保存的所有车票。该操作需要二次确认。")
            }
        }
        .alert("确认清空全部行程数据？", isPresented: $showingDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("确认删除", role: .destructive) {
                onDeleteAll()
                toast = "本地车票已删除"
            }
        } message: {
            Text("此操作将删除本机保存的所有车票，且无法恢复。")
        }
    }
}
