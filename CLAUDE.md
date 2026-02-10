# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目概述

FlowWatch 是一个轻量级 macOS 菜单栏网速监控工具，使用 SwiftUI + AppKit 开发，实时显示网络上下行速率，支持自定义采样间隔和色阶提示。

## 构建与运行

使用 Xcode 打开 `FlowWatch.xcodeproj`，选择 `FlowWatch` scheme 运行。目标平台为 macOS 10.15+，建议使用 Xcode 15+。

## 代码架构

```
FlowWatchApp (入口)
    ↓
AppDelegate (设置为 accessory 模式)
    ├── NetworkUsageMonitor (核心监控逻辑)
    │   ├── downloadBps / uploadBps (Published)
    │   ├── totalDownloaded / totalUploaded
    │   └── sampleInterval / isActive
    │
    └── StatusBarController (状态栏管理)
        ├── MenuStatusLabel (菜单速率显示)
        └── ContentView (主控制界面)
```

**核心工作流程：**
1. `NetworkUsageMonitor` 使用 `DispatchSourceTimer` 按 `sampleInterval`（默认1秒）采样
2. 调用 `getifaddrs` 遍历网络接口，累加所有非回环接口的 `ifi_ibytes`（接收）和 `ifi_obytes`（发送）
3. 计算瞬时速率 = 当前总量 - 上次采样总量
4. `StatusBarController` 订阅 Published 属性更新状态栏显示

## 关键文件

| 文件 | 职责 |
|------|------|
| `NetworkUsageMonitor.swift` | 核心网络监控，使用 `getifaddrs` 读取网卡数据 |
| `StatusBarController.swift` | 状态栏菜单管理，包含速率上色逻辑 |
| `FlowWatchApp.swift` | 应用入口，定义显示模式枚举 |

## 技术栈

- Swift 5.x, SwiftUI + AppKit
- `getifaddrs` (BSD socket API) 用于网络数据采集
- `DispatchSourceTimer` 实现定时采样

## 开发与发布流程

### 1. 功能开发流程

**步骤：**

1. **同步主分支**
   ```bash
   git checkout main
   git pull github main
   ```

2. **创建功能分支**
   ```bash
   git checkout -b feature/功能名称
   # 或
   git checkout -b fix/问题描述
   ```

3. **开发与提交**
   - 修改代码
   - 运行测试确保功能正常
   - 提交改动（使用有意义的中文提交信息）
   ```bash
   git add 文件名
   git commit -m "描述改动内容和原因"
   ```

4. **推送分支并创建 PR**
   ```bash
   git push github 分支名 -u
   gh pr create --title "PR标题" --body "PR描述"
   ```

5. **PR 审核与合并**
   - 检查 CI/CD 状态
   - 审核代码改动
   - 合并到 main 分支

### 2. 版本发布流程

**发布新版本时：**

1. **确保 main 分支最新**
   ```bash
   git checkout main
   git pull github main
   ```

2. **打版本标签**
   ```bash
   # 查看当前最新 tag
   git tag -l --sort=-v:refname | head -5

   # 创建新 tag（遵循语义化版本）
   git tag v版本号

   # 推送 tag 到远程
   git push github v版本号
   ```

3. **版本号规范（Semantic Versioning）**
   - `v1.x.0` - 主要功能更新
   - `v1.0.x` - Bug 修复和小改进
   - `v1.0.0` - 重大版本或破坏性变更

### 3. 分支命名规范

- `feature/*` - 新功能开发
- `fix/*` - Bug 修复
- `chore/*` - 构建、配置等杂项
- `docs/*` - 文档更新

### 4. 提交信息规范

使用清晰的中文描述，说明改动的"是什么"和"为什么"：

```
修复自动更新检查在应用未运行时被跳过的问题

当应用在预定的检查时间未运行时，定时器不会触发。
应用重启后，原代码会跳过已错过的检查，直接计算下一个周期。

现在应用启动时会检查是否错过了更新检查，如果超过24小时
未检查，则立即安排一次检查（延迟5秒执行）。
```

### 5. 常见操作

**重新打 tag（谨慎使用）：**
```bash
# 删除本地 tag
git tag -d v版本号

# 删除远程 tag
git push github :refs/tags/v版本号

# 重新创建并推送
git tag v版本号
git push github v版本号
```

**查看两个版本之间的改动：**
```bash
git diff v1.3.0..v1.3.1
git log v1.3.0..v1.3.1 --oneline
```

**临时保存改动：**
```bash
git stash              # 保存当前改动
git stash pop          # 恢复改动
```
