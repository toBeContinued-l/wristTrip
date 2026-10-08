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
    @Binding var appearanceModeRaw: String
    var onDeleteAll: () -> Void = {}
    var onLiveActivitiesChanged: (Bool) -> Void = { _ in }
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
                    Label("查看智能叠放预览", systemImage: "applewatch")
                }
                HStack {
                    Label("智能叠放", systemImage: "applewatch")
                    Spacer()
                    Text("无需安装手表 App").foregroundStyle(.secondary)
                }
                Toggle(isOn: $liveActivitiesEnabled) {
                    Label("本机实时活动", systemImage: "bolt.horizontal.circle")
                }
                .onChange(of: liveActivitiesEnabled) { _, enabled in
                    onLiveActivitiesChanged(enabled)
                }
                Text("开启后，App 在前台会为发车前 3 小时至计划到站间的完整车票启动或更新实时活动；关闭会结束现有活动。还需在 iPhone 系统设置中允许本 App 的实时活动。")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("设备")
            }

            Section {
                Label("本机 OCR 处理", systemImage: "lock.shield")
                Text("截图和 OCR 原文只在本机临时处理。启动的实时活动可显示在 iPhone 锁屏和通知中心；配对 Apple Watch 的智能叠放展示由系统决定，无需安装手表 App。离线查看完整车票则需要安装手表 App 并同步。\n\nApp 关闭后按计划时间自动启动或结束活动所需的 APNs 服务端尚未接入。信息中的计划时间来自截图，不代表铁路实时状态。")
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
