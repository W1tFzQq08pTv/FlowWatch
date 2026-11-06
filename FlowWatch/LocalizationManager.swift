import Foundation
import SwiftUI
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans = "zh-Hans"
    case en
    
    var id: String { rawValue }
    
    var bundle: Bundle {
        switch self {
        case .system:
            return .main
        case .zhHans, .en:
            if let path = Bundle.main.path(forResource: rawValue, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
            return .main
        }
    }
    
    var localeIdentifier: String? {
        switch self {
        case .system:
            return nil
        case .zhHans:
            return "zh-Hans"
        case .en:
            return "en"
        }
    }
}

extension Notification.Name {
    static let flowWatchLanguageChanged = Notification.Name("flowwatch.language.changed")
}

@MainActor
final class LocalizationManager: @preconcurrency ObservableObject {
    static let shared = LocalizationManager()
    
    let objectWillChange = ObservableObjectPublisher()
    
    @AppStorage("appLanguage") private var appLanguageRawValue: String = AppLanguage.system.rawValue {
        didSet {
            if oldValue != appLanguageRawValue {
                NotificationCenter.default.post(name: .flowWatchLanguageChanged, object: nil)
                objectWillChange.send()
            }
        }
    }
    
    var language: AppLanguage {
        get { AppLanguage(rawValue: appLanguageRawValue) ?? .system }
        set { appLanguageRawValue = newValue.rawValue }
    }
    
    var locale: Locale {
        if let identifier = language.localeIdentifier {
            return Locale(identifier: identifier)
        }
        return .current
    }
    
    private var cachedLanguage: AppLanguage?
    private var cachedBundle = Bundle.main

    func t(_ key: String, table: String? = nil) -> String {
        let currentLanguage = language
        if cachedLanguage != currentLanguage {
            cachedLanguage = currentLanguage
            cachedBundle = currentLanguage.bundle
        }
        return cachedBundle.localizedString(forKey: key, value: key, table: table)
    }
}

enum L10n {
    @MainActor
    static func t(_ key: String) -> String {
        LocalizationManager.shared.t(key)
    }
}

struct LocalizedRootView<Content: View>: View {
    @EnvironmentObject private var l10n: LocalizationManager
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content.environment(\.locale, l10n.locale)
    }
}
