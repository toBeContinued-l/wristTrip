# WristTrip / 车次抬腕

WristTrip 是一款 iPhone 与 Apple Watch 车票管理应用。它可以从车票截图识别行程信息，在 iPhone 上管理车票，并通过实时活动和 Apple Watch 查看即将出发的行程。

## 功能

- 使用设备端文字识别导入车票截图，并在保存前核对和编辑信息。
- 按计划时间整理当前行程和历史车票。
- 在 iPhone 上展示实时活动，并通过独立的 Apple Watch 应用查看同步的车票摘要。
- 支持从系统分享菜单导入图片。

## 开发环境

- 支持 iOS 18 和 watchOS 11 SDK 的 Xcode。
- iPhone 模拟器或真机；Apple Watch 功能需要配对设备或对应模拟器。

使用 Xcode 打开 `WristTrip.xcodeproj`，选择 `WristTrip` scheme 运行。测试使用 `WristTripTests` scheme。真机运行需要在 Xcode 中配置适合自己的签名信息和 App Group。

## 项目结构

- `WristTrip/`：iPhone 应用、车票识别和本地存储。
- `WristTripWatch/`：Apple Watch 应用。
- `WristTripWidget/`：实时活动界面。
- `WristTripShare/`：系统分享扩展。
- `WristTripTests/`：自动化测试。

本项目不是中国铁路 12306 官方应用。行程信息以车票中的计划时间为准，不能代替官方的晚点、检票或站台通知。
