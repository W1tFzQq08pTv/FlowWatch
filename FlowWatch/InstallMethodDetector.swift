//
//  InstallMethodDetector.swift
//  FlowWatch
//
//  Created by xida huang on 1/22/26.
//

import Foundation

enum InstallMethod: String {
    case homebrew
    case dmg
}

struct InstallMethodDetector {
    private static let overrideKey = "installMethodOverride"
    private static let envKey = "FLOWWATCH_INSTALL_METHOD"

    static func detect() -> InstallMethod {
        if let override = UserDefaults.standard.string(forKey: overrideKey),
           let method = InstallMethod(rawValue: override.lowercased()) {
            return method
        }

        if let envOverride = ProcessInfo.processInfo.environment[envKey],
           let method = InstallMethod(rawValue: envOverride.lowercased()) {
            return method
        }

        let bundlePath = Bundle.main.bundlePath
        let resolvedPath = URL(fileURLWithPath: bundlePath).resolvingSymlinksInPath().path
        if isHomebrewPath(bundlePath) || isHomebrewPath(resolvedPath) {
            return .homebrew
        }

        // Homebrew Cask 会把应用复制到 /Applications/，所以需要额外检查
        if isInstalledByHomebrewCask() {
            return .homebrew
        }

        return .dmg
    }

    private static func isHomebrewPath(_ path: String) -> Bool {
        let markers = ["/Caskroom/", "/Cellar/"]
        return markers.contains { path.contains($0) }
    }

    private static func isInstalledByHomebrewCask() -> Bool {
        // 检查常见的 Homebrew 安装位置
        let homebrewPrefixes = [
            "/opt/homebrew",      // Apple Silicon
            "/usr/local"          // Intel
        ]

        let caskName = "flowwatch"

        for prefix in homebrewPrefixes {
            let caskroomPath = "\(prefix)/Caskroom/\(caskName)"
            let metadataPath = "\(caskroomPath)/.metadata/INSTALL_RECEIPT.json"

            // 检查元数据文件是否存在
            if FileManager.default.fileExists(atPath: metadataPath) {
                return true
            }
        }

        return false
    }
}
