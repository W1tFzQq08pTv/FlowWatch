import SwiftUI
import AppKit

struct AboutView: View {
    @EnvironmentObject private var l10n: LocalizationManager

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .flowWatchGlassPanel(cornerRadius: 18, material: .thin, shadowOpacity: 0.06)

            VStack(spacing: 4) {
                Text(appName)
                    .font(.title3.weight(.semibold))

                Text(AppVersion.displayString)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Button {
                openGitHub()
            } label: {
                Label(l10n.t("about.github"), systemImage: "link")
            }
            .buttonStyle(FlowWatchActionButtonStyle(tint: .blue))
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 26)
        .frame(minWidth: 340, minHeight: 250)
        .background(.regularMaterial)
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "FlowWatch"
    }

    private func openGitHub() {
        guard let url = URL(string: "https://github.com/huangxida/FlowWatch") else { return }
        NSWorkspace.shared.open(url)
    }
}

#if DEBUG
#Preview {
    AboutView()
        .environmentObject(LocalizationManager.shared)
        .environment(\.locale, LocalizationManager.shared.locale)
}
#endif
