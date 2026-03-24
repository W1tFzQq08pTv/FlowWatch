//
//  LaunchAtLoginManager.swift
//  FlowWatch
//
//  Created by FlowWatch Assistant on 2026/01/09.
//

import Foundation
import ServiceManagement
import AppKit

@MainActor
final class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()
    
    private let hasPromptedKey = "LaunchAtLogin.hasPrompted"
    private var isPromptPending = false
    private var isPromptVisible = false
    private var hasScheduledPrompt = false
    
    // 仅支持 macOS 13.0+
    @available(macOS 13.0, *)
    var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    @available(macOS 13.0, *)
    var isEnabled: Bool {
        status == .enabled
    }

    @available(macOS 13.0, *)
    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status == .enabled { return }
            try SMAppService.mainApp.register()
        } else {
            if SMAppService.mainApp.status == .notRegistered { return }
            try SMAppService.mainApp.unregister()
        }
    }
    
    func checkAndPrompt() {
        guard #available(macOS 13.0, *) else { return }
        LogManager.shared.log("Check launch at login status")
        // 如果已经开启，无需提示
        if isEnabled { return }
        
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: hasPromptedKey) { return }
        guard !hasScheduledPrompt else { return }

        isPromptPending = true
        hasScheduledPrompt = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.hasScheduledPrompt = false
            self.presentPromptIfNeeded()
        }
    }
    
    func presentPromptIfNeeded(on window: NSWindow? = nil) {
        guard #available(macOS 13.0, *) else { return }
        guard isPromptPending, !isPromptVisible else { return }
        guard !isEnabled else {
            isPromptPending = false
            return
        }

        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: hasPromptedKey) else {
            isPromptPending = false
            return
        }

        guard let hostWindow = window ?? NSApp.keyWindow ?? NSApp.mainWindow else {
            LogManager.shared.log("Launch at login prompt deferred: no host window")
            return
        }

        guard hostWindow.attachedSheet == nil else {
            LogManager.shared.log("Launch at login prompt deferred: host window already has attached sheet")
            return
        }

        let alert = NSAlert()
        alert.messageText = LocalizationManager.shared.t("launch.prompt.title")
        alert.informativeText = LocalizationManager.shared.t("launch.prompt.message")
        alert.addButton(withTitle: LocalizationManager.shared.t("launch.prompt.enable"))
        alert.addButton(withTitle: LocalizationManager.shared.t("launch.prompt.notNow"))
        
        isPromptVisible = true
        isPromptPending = false

        // 使用 sheet 避免全局 runModal 卡住 accessory app 的窗口关闭事件。
        NSApp.activate(ignoringOtherApps: true)
        hostWindow.makeKeyAndOrderFront(nil)

        LogManager.shared.log("Present launch at login prompt sheet")
        alert.beginSheetModal(for: hostWindow) { [weak self] response in
            self?.handlePromptResponse(response)
        }
    }

    @available(macOS 13.0, *)
    private func handlePromptResponse(_ response: NSApplication.ModalResponse) {
        LogManager.shared.log("Launch at login prompt response: \(response.rawValue)")

        isPromptVisible = false
        let defaults = UserDefaults.standard
        
        switch response {
        case .alertFirstButtonReturn:
            defaults.set(true, forKey: hasPromptedKey)
            do {
                try setEnabled(true)
                LogManager.shared.log("Launch at login enabled by user")
            } catch {
                LogManager.shared.log("Failed to enable launch at login: \(error)", level: .error)
            }
        case .alertSecondButtonReturn:
            defaults.set(true, forKey: hasPromptedKey)
        default:
            isPromptPending = true
            LogManager.shared.log("Launch at login prompt aborted, keeping prompt pending")
        }
    }
}
