# 车次抬腕 / WristTrip

SwiftUI iPhone + watchOS V1 开发基线。产品需求见 [docs/prd.md](docs/prd.md)。当前已有车票模型、本机持久化、按计划时间计算状态、相册导入和 Vision OCR 核对、watchOS 离线缓存与 WatchConnectivity 同步。iPhone 包已嵌入 Watch App、图片分享扩展和 ActivityKit Widget 扩展。本地活动启动、车票变更后的刷新和分享收件箱入口已接入主 App；APNs 定时启动与服务端未实现。

## 项目结构

```text
WristTrip.xcodeproj/                 Xcode 工程和共享 scheme
WristTrip/
  WristTripApp.swift                 应用入口
  ContentView.swift                  主导航和行程状态刷新
  Models/Ticket.swift                车票模型、时间状态和字段来源
  Services/TripStore.swift           本机车票持久化、排序、冲突与当前票选择
  Services/TicketOCRService.swift    Vision 本机 OCR 和候选字段解析
  Services/TicketGateLookupService.swift  用户主动查询 12306 检票口的原生 HTTPS 客户端
  Features/Trips/TripViews.swift     行程列表组件和车票详情
  Features/Import/ReviewView.swift   相册导入、OCR 核对和车票保存
  Features/Watch/WatchPreview.swift  iPhone 内的手表卡片预览
  Services/SharedImageInbox.swift    分享图片的 App Group 临时收件箱
  Services/TripActivityService.swift 本地实时活动选择、启动、更新和结束
  Features/Settings/SettingsView.swift
  Resources/Assets.xcassets/         图片与颜色资源目录，含 AppIcon
  Resources/logo-source.png          应用图标原图
WristTripWatch/                       watchOS 11 离线车票应用
WristTripShare/                       接收分享图片的 Share Extension
WristTripWidget/                      ActivityKit 实时活动视图
WristTripTests/                       检票口响应解析的脱敏 XCTest 回归测试
docs/prd.md                          产品需求
```

## 运行

1. 用 Xcode 16 或更新版本打开 `WristTrip.xcodeproj`。
2. 选择 `WristTrip` scheme 和 iOS 18 或更新版本的 iPhone 模拟器运行。
3. 真机运行时，根据自己的开发者账号调整 Signing & Capabilities 中的 Team 和 Bundle Identifier。
4. 回归测试位于 `WristTripTests` target；需要可用的 iOS Simulator runtime 才能运行 XCTest。
5. 真机签名前，在开发者账号中为 iPhone App 和 Share Extension 启用 `group.com.clenson.WristTrip` App Group。

最低系统版本为 iOS 18、watchOS 11。`WristTrip` 模拟器构建已验证同时包含 `Watch/WristTripWatch.app`、`PlugIns/WristTripShare.appex` 和 `PlugIns/WristTripWidget.appex`；手表模拟器可单独安装运行。通过 `simctl install` 安装 iPhone App 时，配对手表未自动安装，自动随装仍需在 Xcode 配对运行流程或真机复核。

分享扩展把图片放入 App Group 收件箱并提示打开主 App；Share Extension 不能可靠保证自动唤起宿主，主 App 会在激活时读取 `SharedImageInbox.pendingImageURLs()`、送入核对页，并在完成或取消后调用 `remove(_:)`。设置页的“本机实时活动”开关默认开启，关闭时会结束已有本地活动并阻止后续刷新；它不代表服务端自动启动能力。`TripActivityService.refresh(tickets:selectedTicketID:)` 已由主 App 在车票保存、编辑、删除和进入前台时调用；符合时间窗口时，Live Activity 可直接出现在配对 Apple Watch 的智能叠放中，无需安装 WristTripWatch App。Watch App 仍作为可选的离线详情和历史车票入口，使用 WatchConnectivity 时才需要安装。App 关闭时的定时启动、状态刷新、到站结束仍需 APNs 服务端。真机配对同步、分享输入与智能叠放展示尚未验收。
