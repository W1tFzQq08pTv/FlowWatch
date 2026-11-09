import SwiftUI

struct UpdatePromptView: View {
    @ObservedObject private var updateManager = UpdateManager.shared
    @EnvironmentObject private var l10n: LocalizationManager

    var body: some View {
        VStack(spacing: 0) {
            if displayedUpdate != nil {
                header
                Divider().opacity(0.45)
            }
            content
        }
        .flowWatchWindowSurface()
        .frame(minWidth: 560, minHeight: 300, alignment: .top)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: headerIcon)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(headerTint)
                .frame(width: 28)

            Text(headerTitle)
                .font(.title2.weight(.semibold))

            Spacer()

            if let update = displayedUpdate {
                HStack(spacing: 6) {
                    if update.isCritical {
                        badge(l10n.t("update.badge.critical"), tint: .red)
                    } else if update.isMajorUpgrade {
                        badge(l10n.t("update.badge.major"), tint: .purple)
                    }
                    badge("v\(update.version)", tint: .secondary)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    @ViewBuilder
    private var content: some View {
        switch updateManager.status {
        case .checking:
            centeredState(
                icon: "arrow.triangle.2.circlepath",
                title: l10n.t("update.state.checking.title"),
                detail: l10n.t("update.state.checking.detail"),
                showsProgress: true,
                actionTitle: l10n.t("common.cancel"),
                action: updateManager.closeUpdateWindow
            )
        case .upToDate:
            centeredState(
                icon: "checkmark.seal.fill",
                title: l10n.t("update.check.upToDate.title"),
                detail: l10n.t("update.check.upToDate.message"),
                showsProgress: false,
                actionTitle: l10n.t("update.done"),
                action: updateManager.closeUpdateWindow
            )
        case .failed(let message):
            errorState(message: message)
        case .idle:
            centeredState(
                icon: "arrow.up.circle",
                title: l10n.t("update.window.title"),
                detail: l10n.t("update.state.idle.detail"),
                showsProgress: false,
                showsTitle: false
            )
        case .updateAvailable(let update),
             .readyToInstall(let update),
             .installOnQuit(let update),
             .remindLater(let update, _),
             .installing(let update),
             .skipped(let update):
            updateDetail(update)
        case .downloading(let update, _):
            updateDetail(update)
        }
    }

    private func updateDetail(_ update: UpdateManager.UpdateInfo) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            versionCard(update)

            if update.isCritical {
                Label(l10n.t("update.critical.message"), systemImage: "exclamationmark.shield.fill")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.red)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottom) {
                        Divider().opacity(0.35)
                    }
            }

            if case .downloading(_, let progress) = updateManager.status {
                downloadProgress(progress)
            }

            actions(for: update)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
    }

    private func versionCard(_ update: UpdateManager.UpdateInfo) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(l10n.t("update.version.current"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("v\(AppVersion.shortVersion)")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
            }
            Spacer()
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(l10n.t("update.version.new"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("v\(update.version)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(FlowWatchPalette.ink)
                    .monospacedDigit()
            }
        }
        .padding(24)
        .flowWatchGlassPanel()
    }

    private func downloadProgress(_ progress: Double?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(l10n.t("update.state.downloading.title"))
                    .font(.callout.weight(.semibold))
                Spacer()
                if let progress {
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            if let progress {
                FlowWatchProgressView(value: progress)

            } else {
                FlowWatchProgressView()

            }
        }
    }

    @ViewBuilder
    private func actions(for update: UpdateManager.UpdateInfo) -> some View {
        if update.isInformationOnly {
            HStack {
                Spacer()
                Button(l10n.t("update.releaseNotes")) {
                    updateManager.openReleaseNotes()
                }
                .buttonStyle(FlowWatchActionButtonStyle(tint: .blue, isPrimary: true))
            }
        } else if case .installing = updateManager.status {
            HStack(spacing: 10) {
                FlowWatchProgressView()
                Text(l10n.t("update.state.preparing.detail"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        } else if case .installOnQuit = updateManager.status {
            HStack {
                Label(l10n.t("update.state.installOnQuit.detail"), systemImage: "power")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(l10n.t("update.installNow")) {
                    updateManager.installNow()
                }
                .buttonStyle(FlowWatchActionButtonStyle(tint: .blue, isPrimary: true))
            }
        } else if case .skipped = updateManager.status {
            HStack {
                Text(l10n.t("update.state.skipped.detail"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(l10n.t("update.recheckSkipped")) {
                    updateManager.recheckSkippedVersions()
                }
                .buttonStyle(FlowWatchActionButtonStyle(tint: .blue))
            }
        } else if case .remindLater(_, let until) = updateManager.status {
            HStack {
                Text(String(format: l10n.t("update.state.remindLater.detail"), formatted(until)))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(l10n.t("update.installNow")) {
                    updateManager.checkForUpdates(userInitiated: true)
                }
                .buttonStyle(FlowWatchActionButtonStyle(tint: .blue, isPrimary: true))
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Button(l10n.t("update.releaseNotes")) {
                        updateManager.openReleaseNotes()
                    }
                    .buttonStyle(FlowWatchActionButtonStyle(tint: .blue))

                    Spacer()

                    Button(l10n.t("update.installOnQuit")) {
                        updateManager.installOnQuit()
                    }
                    .buttonStyle(FlowWatchActionButtonStyle(tint: .blue))

                    Button(primaryActionTitle) {
                        updateManager.installNow()
                    }
                    .buttonStyle(FlowWatchActionButtonStyle(tint: .blue, isPrimary: true))
                }

                HStack(spacing: 8) {
                    Button {
                        updateManager.remindLater()
                    } label: {
                        Label(l10n.t("update.remindTomorrow"), systemImage: "clock")
                    }
                    .buttonStyle(FlowWatchActionButtonStyle())

                    if !update.isCritical {
                        Button {
                            updateManager.skipVersion()
                        } label: {
                            Label(l10n.t("update.skipVersion"), systemImage: "forward.end")
                        }
                        .buttonStyle(FlowWatchActionButtonStyle())
                    }

                    Spacer()
                }
            }
        }
    }

    private func centeredState(
        icon: String,
        title: String,
        detail: String,
        showsProgress: Bool,
        showsTitle: Bool = true,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(stateTint)
            if showsTitle {
                Text(title).font(.title3.weight(.semibold))
            }
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if showsProgress { FlowWatchProgressView() }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(FlowWatchActionButtonStyle(tint: .blue, isPrimary: !showsProgress))
                    .padding(.top, 4)
            }
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text(l10n.t("update.check.failed.title")).font(.title3.weight(.semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            HStack(spacing: 10) {
                Button(l10n.t("update.close")) {
                    updateManager.closeUpdateWindow()
                }
                .buttonStyle(FlowWatchActionButtonStyle(tint: .blue))

                Button(l10n.t("update.retry")) {
                    updateManager.retryUpdateCheck()
                }
                .buttonStyle(FlowWatchActionButtonStyle(tint: .blue, isPrimary: true))
            }
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func badge(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
    }

    private var displayedUpdate: UpdateManager.UpdateInfo? {
        switch updateManager.status {
        case .updateAvailable(let update), .downloading(let update, _), .readyToInstall(let update),
             .installOnQuit(let update), .remindLater(let update, _), .installing(let update), .skipped(let update):
            return update
        default:
            return nil
        }
    }

    private var primaryActionTitle: String {
        if case .updateAvailable = updateManager.status {
            return l10n.t("update.downloadAndInstall")
        }
        return l10n.t("update.installNow")
    }

    private var headerIcon: String {
        switch updateManager.status {
        case .upToDate: return "checkmark.seal.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .installOnQuit: return "power.circle.fill"
        case .installing, .downloading: return "arrow.down.circle.fill"
        default: return displayedUpdate?.isCritical == true ? "exclamationmark.shield.fill" : "sparkles"
        }
    }

    private var headerTint: Color {
        if displayedUpdate?.isCritical == true { return .red }
        if case .failed = updateManager.status { return .orange }
        if case .upToDate = updateManager.status { return .green }
        return .blue
    }

    private var headerTitle: String {
        if let update = displayedUpdate {
            return String(format: l10n.t("update.available.title"), update.version)
        }
        return l10n.t("update.window.title")
    }

    private var stateTint: Color {
        switch updateManager.status {
        case .upToDate:
            return .green
        case .failed:
            return .orange
        default:
            return .secondary
        }
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = l10n.locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
