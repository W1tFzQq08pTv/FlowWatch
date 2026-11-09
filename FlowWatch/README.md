# FlowWatch 开发说明

FlowWatch 是 macOS 13+ 的菜单栏网速与流量监控应用，使用 SwiftUI、AppKit 和 Charts。功能、截图和安装方式见[项目 README](../README.md)。

## 构建与运行

CI 使用 Xcode 26.6，建议使用相同或更新版本。打开仓库根目录的 `FlowWatch.xcodeproj`，选择 `FlowWatch` scheme 运行：

```bash
xcodebuild -project FlowWatch.xcodeproj -scheme FlowWatch \
  -configuration Debug -destination 'platform=macOS' build
```

应用默认使用 accessory 模式，不显示 Dock 图标；从菜单栏打开快捷卡片、统计、应用流量和设置。当前未提交自动化测试目标。

## 源码结构

| 文件 | 职责 |
| --- | --- |
| `FlowWatchApp.swift` / `AppDelegate.swift` | 应用入口与监控器生命周期 |
| `NetworkUsageMonitor.swift` | 网卡计数采样、速率与每日总量，支持 1/2/3/5 秒采样间隔 |
| `ProcessNetworkMonitor.swift` / `NettopTrafficAccounting.swift` | 可选的应用与进程采样、连接增量及接口范围归类 |
| `DailyTrafficStorage.swift` / `ProcessTrafficStorage.swift` | 每日与应用历史的 JSON 持久化 |
| `StatusBarController.swift` / `StatusBarLayout.swift` | 菜单栏绘制、组件组合和快捷面板入口 |
| `FlowWatchQuickPanelView.swift` | 实时、今日与近 7 天三张快捷卡片 |
| `TrafficStatisticsDetailWindow.swift` / `TrafficStatisticsCharts.swift` | 统计分区、历史趋势与流量构成 |
| `PerAppTrafficDetailWindow.swift` / `PerAppTrafficSummaryCharts.swift` | 应用用量、筛选、排序和历史图表 |
| `FlowWatchRingChart.swift` / `FlowWatchChartStyle.swift` | 共享环形几何、图表样式和绘图区边界 |
| `SettingsView.swift` / `ModernControls.swift` | 设置页与共享卡片控件 |
| `UpdateManager.swift` / `UpdateDownloadCache.swift` | Sparkle 更新状态与下载缓存 |

界面文案位于 `Resources/zh-Hans.lproj/` 和 `Resources/en.lproj/`。修改文案时同步维护两种语言。实现 `Equatable` 的视图若包含 `@Environment`，显式比较外部输入，避免依赖新版 SDK 的自动合成行为。

## 数据与统计范围

- 网卡总量基于 `getifaddrs` 的字节计数计算，不读取网络包内容。
- 应用监控使用系统 `nettop` 数据，按接口归类；当前应用列表主要展示外部硬件接口的用量。
- 网卡与应用统计的采样及归类方式不同，不应假设两者数值完全相等。
- 偏好设置使用 UserDefaults；历史与日志保存在 `~/Library/Application Support/FlowWatch/`。不要用演示数据覆盖用户历史。

## 发布与打包

根目录 `.github/workflows/release.yml` 响应 `v*` 标签。工作流从标签注入应用版本号，并使用 Actions 运行号作为构建号，生成 `FlowWatch.dmg`、`FlowWatch.zip` 和签名的 `appcast.xml`。

- `scripts/release_build.sh`：配置证书时的构建打包入口。
- `scripts/release_build_unsigned.sh`：未配置证书时的构建打包入口。
- `scripts/notarize.sh`：具备相应凭据时公证并装订产物。
- Sparkle 私钥用于生成签名的 appcast，是发布所必需的配置；Homebrew tap 凭据可选。

大版本更新使用常规版本标签即可。只有需要禁止跳过的更新才在附注标签说明中单独加入 `sparkle:critical`。
