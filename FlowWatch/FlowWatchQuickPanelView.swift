import AppKit
import Combine
import SwiftUI

@MainActor
final class FlowWatchQuickPanelState: ObservableObject {
    enum Target: Hashable {
        case action(FlowWatchQuickPanelView.Action)
    }

    @Published var cardIndex = 0
    @Published var focusedTarget: Target?

    func moveFocus(backward: Bool, perAppEnabled: Bool, updateEnabled: Bool) {
        var targets: [Target] = [.action(.statistics)]
        if perAppEnabled { targets.append(.action(.perApp)) }
        targets.append(.action(.settings))
        if updateEnabled { targets.append(.action(.update)) }
        targets += [.action(.about), .action(.quit)]
        let index = focusedTarget.flatMap { targets.firstIndex(of: $0) } ?? (backward ? 0 : -1)
        focusedTarget = targets[(index + (backward ? -1 : 1) + targets.count) % targets.count]
    }

    func advance(_ direction: Int) { cardIndex = (cardIndex + direction + 3) % 3 }
}

struct FlowWatchQuickPanelView: View {
    enum Action: Hashable { case statistics, perApp, settings, update, about, quit }

    @ObservedObject var monitor: NetworkUsageMonitor
    let processMonitor: ProcessNetworkMonitor
    @State private var isPerAppEnabled = false
    @ObservedObject var state: FlowWatchQuickPanelState
    @ObservedObject private var updater = UpdateManager.shared
    @EnvironmentObject private var l10n: LocalizationManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var keyboardFocus: FlowWatchQuickPanelState.Target?
    @GestureState private var cardDrag = CGSize.zero
    @State private var previousDays: [DailyTrafficRecord] = []
    let updateTitle: () -> String
    let action: (Action) -> Void

    private var motion: Animation? { reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.84) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            cardDeck

            VStack(spacing: 4) {
                actionRow(.statistics, title: l10n.t("menu.statisticsDetail"), icon: "chart.xyaxis.line")
                if isPerAppEnabled {
                    actionRow(.perApp, title: l10n.t("menu.perAppTraffic"), icon: "square.stack.3d.up")
                }
                actionRow(.settings, title: l10n.t("menu.settings"), icon: "slider.horizontal.3", shortcut: "⌘,")
                actionRow(.update, title: updateTitle(), icon: "arrow.down.circle")
                    .disabled(!updater.canActivateUpdateMenu)
                actionRow(.about, title: l10n.t("menu.about"), icon: "info.circle")
                Rectangle().fill(FlowWatchPalette.ink.opacity(0.06)).frame(height: 1).padding(.vertical, 8)
                actionRow(.quit, title: l10n.t("menu.quit"), icon: "power", shortcut: "⌘Q")
            }
        }
        .padding(24)
        .frame(width: 376)
        .onAppear { loadPreviousDays() }
        .onReceive(processMonitor.$isEnabled.removeDuplicates()) { isPerAppEnabled = $0 }
        .onChange(of: state.focusedTarget) { keyboardFocus = $0 }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in loadPreviousDays() }
        .onReceive(NotificationCenter.default.publisher(for: .flowWatchResetToday)) { _ in refreshAfterReset() }
        .onReceive(NotificationCenter.default.publisher(for: .flowWatchResetAllHistory)) { _ in refreshAfterReset() }
    }

    private var cardDeck: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                let depth = (index - state.cardIndex + 3) % 3
                metricCard(index, isFront: depth == 0)
                    .scaleEffect(1 - CGFloat(depth) * 0.045, anchor: .top)
                    .rotationEffect(.degrees(reduceMotion ? 0 : Double(depth) * 2.2), anchor: .topTrailing)
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : (depth == 0 ? Double(cardDrag.width) * 0.025 : Double(depth) * -3)), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
                    .offset(x: CGFloat(depth) * 3 + (depth == 0 && !reduceMotion ? cardDrag.width * 0.35 : 0), y: -CGFloat(depth) * 10)
                    .opacity(depth == 0 ? 1 : 0.9)
                    .zIndex(Double(3 - depth))
                    .allowsHitTesting(depth == 0)
                    .accessibilityHidden(depth != 0)
            }
        }
        .frame(height: 206)
        .padding(.top, 24)
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .flowWatchHover(.grab)
        .onTapGesture { advance(1) }
        .gesture(DragGesture(minimumDistance: 12)
            .updating($cardDrag) { value, state, _ in state = value.translation }
            .onEnded { value in
            guard abs(value.translation.width) > 40, abs(value.translation.width) > abs(value.translation.height) else { return }
            advance(value.translation.width < 0 ? 1 : -1)
        })
        .animation(motion, value: state.cardIndex)
        .accessibilityElement(children: .contain)
        .accessibilityHint(l10n.t("ui.cardHint"))
        .accessibilityAction(named: Text(l10n.t("ui.nextCard"))) { advance(1) }
        .accessibilityAction(named: Text(l10n.t("ui.previousCard"))) { advance(-1) }
    }

    private func metricCard(_ index: Int, isFront: Bool) -> some View {
        let title = ["ui.live", "ui.today", "ui.week"][index]
        let weekDown = previousDays.reduce(0.0) { $0 + Double($1.downloadBytes) } + Double(monitor.todayDownloaded)
        let weekUp = previousDays.reduce(0.0) { $0 + Double($1.uploadBytes) } + Double(monitor.todayUploaded)
        let down = index == 0 ? monitor.formattedSpeed(monitor.downloadBps) : bytes(index == 1 ? Double(monitor.todayDownloaded) : weekDown)
        let up = index == 0 ? monitor.formattedSpeed(monitor.uploadBps) : bytes(index == 1 ? Double(monitor.todayUploaded) : weekUp)

        return VStack(alignment: .leading, spacing: 16) {
            Text(l10n.t(title)).font(.system(size: 12, weight: .semibold))
            HStack(alignment: .top, spacing: 16) {
                metric(down, label: l10n.t("daily.download"), icon: "arrow.down", color: FlowWatchPalette.download)
                metric(up, label: l10n.t("daily.upload"), icon: "arrow.up", color: FlowWatchPalette.upload)
            }
            FlowWatchTrafficMiniChart(
                downloads: index == 0 ? liveValues(upload: false) : (index == 1 ? [Double(monitor.todayDownloaded)] : weekRecords.map { Double($0.downloadBytes) }),
                uploads: index == 0 ? liveValues(upload: true) : (index == 1 ? [Double(monitor.todayUploaded)] : weekRecords.map { Double($0.uploadBytes) }),
                style: index == 0 ? .dots : (index == 1 ? .balance : .bars)
            )
            .frame(height: 48)

        }
        .opacity(isFront ? 1 : 0)
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 206, maxHeight: 206, alignment: .topLeading)
        .background(index == 1 ? FlowWatchPalette.surface : FlowWatchPalette.elevated, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(FlowWatchPalette.edge, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.08), radius: 14, y: 7)
    }

    private func metric(_ value: String, label: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: icon).font(.system(size: 10, weight: .medium)).foregroundStyle(color)
            Text(value).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func actionRow(_ target: Action, title: String, icon: String, shortcut: String = "") -> some View {
        QuickActionRow(title: title, icon: icon, shortcut: shortcut, destructive: target == .quit,
                       isKeyboardFocused: state.focusedTarget == .action(target), target: target, focus: $keyboardFocus) { action(target) }
    }

    private func advance(_ direction: Int) { withAnimation(motion) { state.advance(direction) } }
    private func bytes(_ value: Double) -> String { FlowWatchByteFormatter.formatBytes(value) }
    private func liveValues(upload: Bool) -> [Double] {
        let samples = monitor.recentRateSamples.suffix(28)
        return Array(repeating: 0, count: max(28 - samples.count, 0)) + samples.map { upload ? $0.uploadBps : $0.downloadBps }
    }
    private var weekRecords: [DailyTrafficRecord] {
        previousDays + [DailyTrafficRecord(downloadBytes: monitor.todayDownloaded, uploadBytes: monitor.todayUploaded)]
    }
    private func loadPreviousDays() {
        previousDays = DailyTrafficStorage.shared.getRecentDays(days: 7).filter { !Calendar.current.isDateInToday($0.date) }
    }
    private func refreshAfterReset() { DispatchQueue.main.async { loadPreviousDays() } }
}

private struct QuickActionRow: View {
    let title: String
    let icon: String
    let shortcut: String
    let destructive: Bool
    let isKeyboardFocused: Bool
    let target: FlowWatchQuickPanelView.Action
    let focus: FocusState<FlowWatchQuickPanelState.Target?>.Binding
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 14, weight: .medium)).frame(width: 20)
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 4)
                Text(shortcut).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }
            .foregroundStyle(destructive ? FlowWatchPalette.destructive : FlowWatchPalette.ink)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(isHovering || isKeyboardFocused ? FlowWatchPalette.well : .clear, in: RoundedRectangle(cornerRadius: 14))
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(FlowWatchHoverButtonStyle())
        .focusable()
        .focused(focus, equals: .action(target))
        .onHover { isHovering = $0 && isEnabled }
    }
}
