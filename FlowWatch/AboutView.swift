import SwiftUI
import AppKit

struct AboutView: View {
    @EnvironmentObject private var l10n: LocalizationManager
    @State private var isGitHubHovered = false

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 68, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

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
                    .overlay {
                        Circle()
                            .stroke(Color.primary.opacity(isGitHubHovered ? 0.16 : 0.09), lineWidth: 0.8)
                    }
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .onHover { isGitHubHovered = $0 }
            .help(l10n.t("about.github"))
            .accessibilityLabel(l10n.t("about.github"))
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 26)
        .frame(minWidth: 340, minHeight: 250)
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
