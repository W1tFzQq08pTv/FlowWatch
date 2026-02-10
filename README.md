<div align="center">
  <img src=".github/assets/app-icon.png" width="96" height="96" alt="FlowWatch" />
  <h1>FlowWatch</h1>
  <p>轻量级 macOS 菜单栏网速监控工具：实时速率、流量统计与趋势图。</p>
</div>

简体中文 | [English](README.en.md)

## 功能
- 菜单栏实时显示上行/下行速率
- 今日/累计流量统计与趋势图（Charts，macOS 13+）
- 应用流量监控：按应用统计网络流量，支持日期范围筛选
- 自定义采样间隔与显示样式
- 自动检查更新并显示上次/下次检查时间
- 可选日志输出（按天保存，保留 7 天）

## 数据与隐私
- 流量统计仅在本地基于系统网卡计数器计算，不采集任何包内容。
- 设置项与每日流量仅保存在本机（UserDefaults）。
- 日志（如开启）仅写入本地文件，不会上传或同步。
- 无需账号，应用不会上传或同步你的数据。

## 安装
### Homebrew
```bash
brew tap huangxida/flowwatch
brew install --cask flowwatch
```

### 从发布页下载
前往 GitHub Releases 下载最新的 DMG：
[FlowWatch Releases](https://github.com/huangxida/FlowWatch/releases)


## 截图
| 状态栏：速率 | 状态栏：今日统计 | 状态栏：速率 + 今日统计 |
| --- | --- | --- |
| <img src=".github/assets/statusbar-speed.png" width="260" alt="Status bar speed" /> | <img src=".github/assets/statusbar-today.png" width="260" alt="Status bar today" /> | <img src=".github/assets/statusbar-speed-today.png" width="260" alt="Status bar speed and today" /> |

| 设置 | 弹窗 | 应用流量 |
| --- | --- | --- |
| <img src=".github/assets/settings.png" width="300" alt="Settings" /> | <img src=".github/assets/popup.png" width="300" alt="Popup" /> | <img src=".github/assets/perapp-traffic.png" width="300" alt="Per-App Traffic" /> |
