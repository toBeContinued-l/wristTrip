# 车次抬腕 / WristTrip

SwiftUI iPhone + watchOS V1 开发基线。产品需求见 [docs/prd.md](docs/prd.md)。主流程是截图核对后启动 iPhone 实时活动，由系统决定其在 Apple Watch 智能叠放的展示；独立 Watch App 仅提供可选的离线查看。本地启动、后台尽力刷新、分享扩展及推送令牌和调度客户端已接入；APNs 调度服务端与真机验收尚未完成。

## 项目结构

```text
WristTrip.xcodeproj/                 Xcode 工程和共享 scheme
WristTrip/
  WristTripApp.swift                 应用入口
  ContentView.swift                  主导航和行程状态刷新
  Models/Ticket.swift                车票模型、时间状态和字段来源
  Services/TripStore.swift           本机车票持久化、排序、冲突与当前票选择
  Services/TicketOCRService.swift    Vision 本机 OCR 和候选字段解析
  Features/Trips/TripViews.swift     行程列表组件和车票详情
  Features/Import/ReviewView.swift   相册导入、OCR 核对和车票保存
  Features/Watch/WatchPreview.swift  iPhone 内的手表卡片预览
  Features/Watch/TrainTicketCard.swift  iPhone、Watch 与实时活动共用的叠放卡片
  Services/TripBackgroundRefreshService.swift  本地 BGAppRefresh 状态刷新与边界调度
  Services/SharedImageInbox.swift    分享图片的 App Group 临时收件箱
  Services/TripActivityService.swift 本地实时活动选择、启动、更新和结束
  Services/WristTripAppDelegate.swift 启动 ActivityKit 推送令牌监听
  Services/ActivityPushTokenService.swift 远程启动和活动令牌、调度登记与重试
  Features/Settings/SettingsView.swift
  Resources/Assets.xcassets/         图片与颜色资源目录，含 AppIcon
  Resources/logo-source.png          应用图标原图
WristTripWatch/                       watchOS 11 离线车票应用
WristTripShare/                       接收分享图片的 Share Extension
WristTripWidget/                      ActivityKit 实时活动视图
WristTripTests/                       OCR、编辑和行程状态的 XCTest 回归测试
docs/prd.md                          产品需求
docs/apns-backend-ai-spec.md         APNs 服务端调度、payload 与验收契约
```

## 运行

1. 用 Xcode 16 或更新版本打开 `WristTrip.xcodeproj`。
2. 选择 `WristTrip` scheme 和 iOS 18 或更新版本的 iPhone 模拟器运行。
3. 真机运行时，在 Xcode 的 Settings > Accounts 登录拥有开发资源权限的 Apple Account；在 `WristTrip`、`WristTripWatch`、`WristTripShare`、`WristTripWidget` 和 `WristTripTests` 的 Signing & Capabilities 中选择同一个 Team，并开启 Automatically manage signing。工程当前使用 Team `JM6FWTK9KJ`，主 App Bundle ID 为 `com.clenson.wristtrip.jm6fwtk9kj`，其他 target 使用它的子标识；如需换成你们公司注册的标识，需同时修改全部 target 的 Bundle ID 和 Watch 的 `WKCompanionAppBundleIdentifier`。
4. 回归测试位于 `WristTripTests` target；需要可用的 iOS Simulator runtime 才能运行 XCTest。
5. 主 App 和 Share Extension 使用 `group.com.clenson.wristtrip.jm6fwtk9kj` App Group。首次真机签名时，Xcode 需要在当前开发团队注册这个 App Group；如果团队权限不允许自动注册，请让 Account Holder 或 Admin 在 Certificates, Identifiers & Profiles 中创建它，再回到 Xcode 点击 Try Again。
6. 如果 Xcode 报 `No profiles for ... were found`，先确认报错 target 的 Team 与 Bundle ID，再确认该团队有对应的 Apple Development 证书、已注册的 App ID、App Group 和已纳入测试设备的 iOS App Development profile。自动签名需要该 Apple Account 能访问 Certificates, Identifiers & Profiles，并能连接 Apple 开发者服务。工程默认不带 `aps-environment`；启用 APNs 时，在支持 Push Notifications 的 Apple Developer Program 团队为 iPhone App 添加该能力，再配置 `WristTrip/Info.plist` 的 `WristTripScheduleURL` 为 HTTPS 调度接口。由 Xcode 和对应 profile 管理 development / production 的 `aps-environment`。

最低系统版本为 iOS 18、watchOS 11。`WristTrip` 模拟器构建已验证同时包含 `Watch/WristTripWatch.app`、`PlugIns/WristTripShare.appex` 和 `PlugIns/WristTripWidget.appex`；手表模拟器可单独安装运行。通过 `simctl install` 安装 iPhone App 时，配对手表未自动安装，自动随装仍需在 Xcode 配对运行流程或真机复核。

分享扩展把图片放入 App Group 收件箱并提示打开主 App；主 App 在激活时读取收件箱并在核对后删除临时图片。“本机实时活动”默认开启，“自动展示”默认关闭并单独征得用户同意。手动显示立即启动实时活动，已安装 Watch App 时顺带同步离线快照；未安装 Watch App 不影响智能叠放。自动展示启用后，客户端监听 push-to-start 和每个活动的推送令牌，在车票、选择、令牌或开关变化时以幂等 PUT 登记调度快照；失败时前台指数退避重试，重新打开 App 时重新对账。`BGAppRefreshTask` 只是本地尽力刷新，锁屏期间的定时启动、更新、续开和到站结束仍需 APNs 服务端。单次活动达到 8 小时时会尝试续开，但系统可能延迟或拒绝，不承诺全程置顶。

## 自动展示服务接口

`WristTripScheduleURL` 是完整的 HTTPS PUT 地址。请求 JSON 包含 `deviceID`、`enabled`、`pushToStartToken`、`selectedTicketID`、`tickets` 和 `activityTokens`。每个车票只含车次、站点、座位、检票信息、时区及计划时间；**不包含订单号、截图或 OCR 原文**。服务端以 `deviceID` 整体替换该设备的未来任务，重复请求须幂等；`enabled: false` 表示撤销任务并删除令牌。登录层可通过 `ActivityPushTokenService.setScheduleAuthorizationToken(_:)` 注入短期 Bearer token；未注入时仅适合开发环境，生产服务端不能开放匿名 PUT。客户端的 Date 使用 Swift 默认 reference-date 数字编码，服务端需要转换后再生成 APNs payload。仅在持久化任务成功后返回 2xx，客户端才显示“已登记”。服务端仍需实现设备认证、APNs 环境区分、当前车次选择、重复推送去重、令牌失效处理、8 小时续开和到站结束。未配置 URL 时界面显示“自动服务尚未配置”，不宣称自动展示已可用。
