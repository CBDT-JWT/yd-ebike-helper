# YD E-Bike Helper

<p align="center">
  <img src="Assets/AppIcon.png" width="160" alt="YD E-Bike Helper 图标">
</p>

`YD E-Bike Helper` 是一款适用于 macOS 和 iPhone 的雅迪（YADEA）电动车 BLE 蓝牙调试工具，可用于发现设备、建立连接、完成设备认证、管理动力锁定以及查看通信日志。

[软件主页](https://cbdt-jwt.github.io/yd-ebike-helper/) · [下载最新版](https://github.com/CBDT-JWT/yd-ebike-helper/releases/latest)

> 本项目是独立开发的非官方工具，与雅迪科技集团有限公司无隶属或授权关系。请仅连接和调试属于自己或已获得明确授权的设备。

## 主要功能

- 扫描附近名称以 `YD` 开头的 BLE 设备
- 展示设备名称、信号强度、系统标识和广播数据
- 从设备广播信息中识别 MAC 地址，也支持手动输入
- 连接设备并完成认证流程
- 解除或恢复兼容车辆的动力锁定
- 设置提示音音量，并支持发送自定义 HEX 数据
- 查看 GATT 服务、特征及收发日志

## 系统要求

### iPhone

- iOS 17 或更高版本
- 一台安装了 Xcode 15 或更高版本的 Mac
- 普通 Apple 账户即可进行免费真机签名

### Mac

- macOS 13 Ventura 或更高版本
- 支持蓝牙的 Mac
- Apple Silicon 或 Intel 处理器

## 安装到 iPhone

iPhone 版本不需要 TestFlight，可以通过 Xcode 直接安装到自己的手机。

1. 使用 Xcode 打开 `YDEbikeHelper.xcodeproj`。
2. 打开“Xcode → Settings → Accounts”，登录你的 Apple 账户。
3. 用数据线连接 iPhone，在手机上选择“信任此电脑”。
4. 在项目导航中选择 `YDEbikeHelper`，再选择 `YDEbikeHelper-iOS` Target。
5. 打开“Signing & Capabilities”，将 Team 设为你的 `Personal Team`。
6. 如果 Bundle Identifier 出现重复提示，将其修改成只属于你的值，例如 `com.yourname.ydebikehelper`。
7. 在 Xcode 顶部运行设备中选择你的 iPhone，然后点击运行按钮或按 `Command + R`。
8. 如果手机提示需要开发者模式，前往“设置 → 隐私与安全性 → 开发者模式”，开启并按提示重新启动手机。
9. 首次打开 App 时允许使用蓝牙。

免费 `Personal Team` 筿名有效期为 7 天。到期后重新连接 iPhone，并在 Xcode 中再次运行即可续签安装。蓝牙功能必须使用真机测试，iOS 模拟器不能代替车辆 BLE 通信。

## 安装 macOS 版本

从 [Releases](https://github.com/CBDT-JWT/yd-ebike-helper/releases/latest) 下载 `yd-ebike-helper-macOS.zip`。

1. 解压下载的 ZIP 文件。
2. 将 `YD E-Bike Helper.app` 拖入“应用程序”文件夹。
3. 首次启动时允许应用使用蓝牙。
4. 如果 macOS 阻止打开，请前往“系统设置 → 隐私与安全性”，在安全性提示中选择“仍要打开”。

## 使用方法

1. 打开应用并点击“刷新扫描”。
2. 从设备列表中选择目标雅迪电动车。
3. 核对自动识别的 MAC 地址；无法自动识别时可手动填写。
4. 点击连接，等待设备认证和 GATT 服务发现完成。
5. 管理动力锁定、设置提示音音量，或在高级区域发送自定义 HEX 数据。
6. 通过通信日志查看连接、认证、写入和通知结果。

设备 MAC 地址通常会从广播数据中自动识别。不同车型、控制器版本或固件的广播格式可能不同，因此部分设备仍需手动输入。

## 从源码构建

项目使用 SwiftUI、CoreBluetooth 和 Swift Package Manager。协议测试和 macOS 打包命令：

```bash
swift test
zsh scripts/build-app.sh
```

打包完成后会生成：

```text
dist/yd-ebike-helper-macOS.zip
```

iOS 工程可以使用以下命令执行不签名的 ARM64 编译检查：

```bash
xcodebuild \
  -project YDEbikeHelper.xcodeproj \
  -scheme YDEbikeHelper-iOS \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## 注意事项

- 解除动力锁定后，车辆动力状态可能立即发生变化；请确保车辆完全停稳、支架可靠且周围无障碍物。
- 请勿在车辆行驶过程中连接或发送控制指令。
- 不同车型和固件版本的兼容性可能存在差异。
- 本工具不提供绕过车辆安全机制、所有权验证或访问控制的功能。
