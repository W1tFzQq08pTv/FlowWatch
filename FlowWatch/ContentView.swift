//
//  ContentView.swift
//  FlowWatch
//
//  Created by xida huang on 12/5/25.
//

import SwiftUI
import AppKit
import Combine

struct ContentView: View {
    @ObservedObject var monitor: NetworkUsageMonitor
    @AppStorage("menuDisplayMode") private var displayModeRaw: String = FlowWatchApp.MenuDisplayMode.icon.rawValue
    @EnvironmentObject private var l10n: LocalizationManager

    private var displayMode: FlowWatchApp.MenuDisplayMode {
        let mode = FlowWatchApp.MenuDisplayMode(storedValue: displayModeRaw)
        if mode.rawValue != displayModeRaw {
            displayModeRaw = mode.rawValue
        }
        return mode
    }

    init(monitor: NetworkUsageMonitor) {
        self.monitor = monitor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            statusBarDisplayControls
            speedGrid
            Spacer()
            footerButtons
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [Color.blue.opacity(0.08), Color.purple.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(l10n.t("content.title"))
                    .font(.headline)
                Text(l10n.t("content.subtitle"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Circle()
                .fill(monitor.isActive ? Color.green.opacity(0.8) : Color.red.opacity(0.7))
                .frame(width: 10, height: 10)
            Text(monitor.isActive ? l10n.t("content.status.running") : l10n.t("content.status.paused"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var statusBarDisplayControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.t("content.statusbarDisplay"))
                .font(.caption)
                .foregroundColor(.secondary)
            FlowWatchSegmentedControl(
                options: FlowWatchApp.MenuDisplayMode.allCases.map { (l10n.t($0.titleKey), $0.rawValue) },
                selection: $displayModeRaw,
                tint: .blue
            )
            Text(l10n.t("content.hint.openMenu"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var speedGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                statCard(title: l10n.t("daily.download"), value: monitor.formattedSpeed(monitor.downloadBps), color: gradientColor(for: monitor.downloadBps), systemName: "arrow.down.circle.fill")
                statCard(title: l10n.t("daily.upload"), value: monitor.formattedSpeed(monitor.uploadBps), color: gradientColor(for: monitor.uploadBps), systemName: "arrow.up.circle.fill")
            }
        }
    }


    private var footerButtons: some View {
        HStack {
            Button(monitor.isActive ? l10n.t("content.action.pause") : l10n.t("content.action.resume")) {
                monitor.toggle()
            }
            .buttonStyle(FlowWatchActionButtonStyle(tint: monitor.isActive ? .orange : .green))
            Button(l10n.t("content.action.quitApp")) {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(FlowWatchActionButtonStyle(tint: .red, isDestructive: true))
            Spacer()
        }
    }

    private func statCard(title: String, value: String, color: Color, systemName: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemName)
                .font(.subheadline)
                .foregroundColor(color)
            Text(value)
                .font(.title2.monospacedDigit())
                .bold()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
        .cornerRadius(12)
    }

    private func gradientColor(for bps: Double) -> Color {
        let kb = max(bps, 0) / 1024
        // 0 KB/s -> green, 5 MB/s -> yellow, 50 MB/s -> red
        let low: Double = 5 * 1024    // KB/s
        let high: Double = 50 * 1024  // KB/s
        let t = min(max((kb - low) / (high - low), 0), 1)

        let green = Color.green
        let yellow = Color.yellow
        let red = Color.red

        if t < 0.5 {
            let k = t / 0.5
            return blend(from: green, to: yellow, fraction: k)
        } else {
            let k = (t - 0.5) / 0.5
            return blend(from: yellow, to: red, fraction: k)
        }
    }

    private func blend(from: Color, to: Color, fraction: Double) -> Color {
        let f = max(0, min(1, fraction))
        let fromRGB = from.components
        let toRGB = to.components
        return Color(
            red: fromRGB.red + (toRGB.red - fromRGB.red) * f,
            green: fromRGB.green + (toRGB.green - fromRGB.green) * f,
            blue: fromRGB.blue + (toRGB.blue - fromRGB.blue) * f
        )
    }
}

#if DEBUG
#Preview {
    ContentView(monitor: NetworkUsageMonitor())
        .environmentObject(LocalizationManager.shared)
        .environment(\.locale, LocalizationManager.shared.locale)
}
#endif

#if os(macOS)
private extension Color {
    var components: (red: Double, green: Double, blue: Double) {
        let ns = NSColor(self)
        guard let rgb = ns.usingColorSpace(.deviceRGB) else {
            return (0, 0, 0)
        }
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        rgb.getRed(&r, green: &g, blue: &b, alpha: nil)
        return (Double(r), Double(g), Double(b))
    }
}
#endif
