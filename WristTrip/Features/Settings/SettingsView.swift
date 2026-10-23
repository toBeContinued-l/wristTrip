import SwiftUI
import SafariServices
import UIKit

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

private struct PrivacyPolicyView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ viewController: SFSafariViewController, context: Context) {}
}

struct SettingsView: View {
    private let feedbackEmail = "1056860980@qq.com"
    private let privacyPolicyURL = URL(string: "https://www.clenson.com/wristTrip-privacy.html")!

    @Binding var showingWatch: Bool
    @Binding var toast: String?
    @Binding var liveActivitiesEnabled: Bool
    @Binding var appearanceModeRaw: String
    var onDeleteAll: () -> Void = {}
    var onLiveActivitiesChanged: (Bool) -> Void = { _ in }
    @State private var showingDeleteConfirmation = false
    @State private var showingPrivacyPolicy = false

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
            } header: {
                Text("设备")
            }

            Section {
                Label("本机 OCR 处理", systemImage: "lock.shield")
                Text("截图和 OCR 识别仅在本机处理。为安排 APNs 推送，行程快照和推送令牌会发送到服务器处理，服务器不会持久化保存这些信息。\r\n\r\n实时活动会显示在锁屏上。如果不小心在锁屏上移除了实时活动，可以在行程页的当前行程中，再次点击『显示到智能叠放』按钮恢复显示。\r\n\r\n车次状态按计划时间推算，不代表铁路实时状态。")
                Button {
                    showingPrivacyPolicy = true
                } label: {
                    Label("隐私政策", systemImage: "doc.text")
                }
            } header: {
                Text("数据与隐私")
            }

            Section {
                HStack {
                    Label("邮箱", systemImage: "envelope")
                    Spacer()
                    Text(feedbackEmail)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Button {
                        UIPasteboard.general.string = feedbackEmail
                        toast = "邮箱已复制"
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("复制邮箱")
                }
            } header: {
                Text("问题与反馈")
            }

            Section {
                Button("删除所有本地车票", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            } footer: {
                Text("删除当前设备保存的所有车票。该操作需要二次确认。")
            }
        }
        .alert("删除所有本地车票？", isPresented: $showingDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("确认删除", role: .destructive) {
                onDeleteAll()
                toast = "本地车票已删除"
            }
        } message: {
            Text("此操作将删除本机保存的所有车票，且无法恢复。")
        }
        .sheet(isPresented: $showingPrivacyPolicy) {
            PrivacyPolicyView(url: privacyPolicyURL)
                .ignoresSafeArea()
                .presentationDetents([.large])
        }
    }
}
