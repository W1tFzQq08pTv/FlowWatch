//
//  FlowWatchApp.swift
//  FlowWatch
//
//  Created by xida huang on 12/5/25.
//

import SwiftUI
import AppKit

@main
struct FlowWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var l10n = LocalizationManager.shared

    enum MenuDisplayMode: String, CaseIterable {
        case icon = "icon"
        case compactSpeed = "compactSpeed"
        
        init(storedValue: String) {
            switch storedValue {
            case "图标":
                self = .icon
            case "上下行速率":
                self = .compactSpeed
            default:
                self = MenuDisplayMode(rawValue: storedValue) ?? .icon
            }
        }
        
        var titleKey: String {
            switch self {
            case .icon:
                return "menuDisplayMode.icon"
            case .compactSpeed:
                return "menuDisplayMode.compactSpeed"
            }
        }
    }

    enum StatusBarDisplayMode: String, CaseIterable {
        case speed
        case total
        case both
        case minimalSignal
        case curveLoader
        
        var titleKey: String {
            switch self {
            case .speed:
                return "settings.displayMode.speed"
            case .total:
                return "settings.displayMode.total"
            case .both:
                return "settings.displayMode.both"
            case .minimalSignal:
                return "settings.displayMode.minimalSignal"
            case .curveLoader:
                return "settings.displayMode.curveLoader"
            }
        }

        func next() -> StatusBarDisplayMode {
            switch self {
            case .speed: return .total
            case .total: return .both
            case .both: return .minimalSignal
            case .minimalSignal: return .curveLoader
            case .curveLoader: return .speed
            }
        }
    }

    var body: some Scene {
        Settings {
            LocalizedRootView { SettingsView() }
                .environmentObject(l10n)
        }
    }
}
