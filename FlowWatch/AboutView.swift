import SwiftUI
import AppKit

struct AboutView: View {
    @EnvironmentObject private var l10n: LocalizationManager
    @State private var isGitHubHovered = false

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                FlowWatchLineSphere().frame(width: 164, height: 140)
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
                    .allowsHitTesting(false)
            }

            VStack(spacing: 4) {
                Text(appName)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))

                Text(AppVersion.displayString)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text(l10n.t("ui.aboutCaption"))
                .font(.system(size: 12)).foregroundStyle(.secondary)

            Button {
                openGitHub()
            } label: {
                Image("GitHubMark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 21, height: 21)
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
                    .background(
                        Color.primary.opacity(isGitHubHovered ? 0.08 : 0.035),
                        in: Circle()
                    )

            }
            .buttonStyle(FlowWatchHoverButtonStyle())
            .contentShape(Circle())
            .onHover { isGitHubHovered = $0 }
            .flowWatchHelp(l10n.t("about.github"))
            .accessibilityLabel(l10n.t("about.github"))
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .flowWatchWindowSurface()
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "FlowWatch"
    }

    private func openGitHub() {
        guard let url = URL(string: "https://github.com/W1tFzQq08pTv/FlowWatch") else { return }
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
