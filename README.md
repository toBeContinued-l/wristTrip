# 车次抬腕 / WristTrip

车次抬腕是一个开发中的 iPhone 与 Apple Watch 车票应用。用户可以导入 12306 订单截图，在设备上识别并核对车票，然后手动启动 iPhone 实时活动。系统允许时，实时活动也可出现在配对 Apple Watch 的智能叠放中；独立 Watch App 提供可选的离线查看。

## 当前功能

- 从系统分享菜单或相册导入截图，使用 Vision 在本机识别车次、站点、时间和座位等信息。
- 核对、编辑、保存多张车票，并根据计划发车和到站时间显示行程状态。
- 手动启动实时活动；已安装 Watch App 时可同步离线车票快照。
- 提供自动展示的客户端设置和推送令牌登记逻辑。定时启动、更新及结束需要另行部署 APNs 调度服务。
- 使用 `BGAppRefreshTask` 请求发车前 3 小时、2 小时、1 小时、30 分钟、计划发车、计划到站和 8 小时续期边界；这些是系统的最早执行时间，不是精确闹钟。
- iPhone、Live Activity 和 Watch 共用计划状态规则。后台任务先持久化状态，再更新 ActivityKit 和 WatchConnectivity 离线快照；到站车票保留在历史记录中。

## 运行与测试

使用 Xcode 16 或更新版本打开 `WristTrip.xcodeproj`，选择 `WristTrip` scheme 和 iOS 18 或更新版本的 iPhone 模拟器运行。watchOS App 的最低版本为 watchOS 11。回归测试位于 `WristTripTests` scheme，需要可用的 iOS 模拟器运行时。

真机运行需要在 Xcode 中为各 target 配置自己的开发团队、Bundle Identifier 和 App Group，并保持 Watch App 的 companion 标识与 iPhone App 一致。推送功能还需要相应的 Apple Developer 能力和服务端；仓库不包含 APNs 服务端、生产地址或推送凭据。未配置服务端时，应用会显示“自动服务尚未配置”。

当前工程的默认配置为：iPhone `com.clenson.wristrail`、Widget `com.clenson.wristrail.widget`、Watch App `com.clenson.wristrail.watchkitapp`，开发团队为工程中的 `DEVELOPMENT_TEAM`。iPhone 与分享扩展共用 `group.com.clenson.wristrail`；Watch 使用 WatchConnectivity 离线传输，不直接依赖该 App Group。提交真机前仍需在开发者账号中为这些 Bundle ID、ActivityKit、Background Modes 和相同团队重新生成有效签名配置。

## 隐私与限制

截图识别在设备上完成，完整车票和订单号保存在 iPhone 本机。分享扩展使用临时文件交接图片；可选的 Watch 同步只发送展示所需字段。只有用户启用自动展示且配置服务端后，客户端才会登记最小行程信息和推送令牌；不会发送截图、OCR 原文或订单号。

行程状态依据计划时间计算，不代表铁路实际晚点、检票或站台变化。实时活动何时出现在 Apple Watch 智能叠放由系统决定，后台刷新和 APNs 推送也不保证准点送达。APNs 调度服务端与完整真机流程仍待实现和验收。本项目不是 12306 官方应用。

## 代码目录

- `WristTrip/`：iPhone 应用、OCR、车票存储、实时活动和设置。
- `WristTripWatch/`：可选的 watchOS 离线车票应用。
- `WristTripWidget/`：ActivityKit 实时活动视图。
- `WristTripShare/`：图片分享扩展。
- `WristTripTests/`：OCR、编辑和行程状态回归测试。
