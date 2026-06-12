import ClowderKit
import SwiftUI

/// The Control Center-style tile grid.
struct PanelView: View {
    // Plain `let` is enough for reactivity: body reads properties of the
    // @Observable module classes held by the environment, and SwiftUI tracks
    // those objects directly. Holds only as long as modules are mutated, not replaced.
    let environment: AppEnvironment

    @State private var expanded: ModuleID?

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 10) {
                if isEnabled(.cpu) || isEnabled(.temps) {
                    HStack(alignment: .top, spacing: 10) {
                        if isEnabled(.cpu) {
                            expandableTile(.cpu, collapsed: environment.cpu.tileView)
                        }
                        if isEnabled(.temps) {
                            expandableTile(.temps, collapsed: environment.temps.tileView)
                        }
                    }
                }
                if expanded == .cpu, isEnabled(.cpu) {
                    detailCard(AnyView(CPUExpandedView(module: environment.cpu)))
                }
                if expanded == .temps, isEnabled(.temps) {
                    detailCard(AnyView(TempsExpandedView(environment: environment)))
                }
                if isEnabled(.memory) || isEnabled(.network) || isEnabled(.disk) {
                    HStack(alignment: .top, spacing: 10) {
                        if isEnabled(.memory) { tile(environment.memory.tileView) }
                        if isEnabled(.network) {
                            tile(networkDiskTile)
                        } else if isEnabled(.disk) {
                            tile(environment.disk.tileView)
                        }
                    }
                }
                if isEnabled(.keepAwake) { tile(environment.keepAwake.tileView) }
                if isEnabled(.battery) { tile(environment.battery.tileView) }
                footer
            }
            .padding(12)
        }
        .frame(width: 340)
        // Clear a stale selection when the expanded module is disabled, so
        // re-enabling it doesn't auto-expand the card.
        .onChange(of: expanded.map(isEnabled)) { _, stillEnabled in
            if stillEnabled == false { expanded = nil }
        }
    }

    private func isEnabled(_ id: ModuleID) -> Bool {
        environment.config.config(for: id).enabled
    }

    /// Network tile carries the disk subline, per the approved panel design —
    /// unless disk is disabled.
    private var networkDiskTile: AnyView {
        let subline = isEnabled(.disk)
            ? "\(environment.network.upLine) · \(environment.disk.headline)"
            : environment.network.upLine
        return AnyView(VStack(alignment: .leading, spacing: 2) {
            Label("Network", systemImage: "network")
                .font(.caption2).foregroundStyle(.secondary)
            Text(environment.network.downLine).font(.title3.weight(.semibold)).monospacedDigit()
            Text(subline)
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12))
    }

    private func tile(_ content: AnyView) -> some View {
        content
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private func expandableTile(_ id: ModuleID, collapsed: AnyView) -> some View {
        collapsed
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
            .onTapGesture {
                withAnimation(.snappy) { expanded = expanded == id ? nil : id }
            }
    }

    private func detailCard(_ content: AnyView) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
            .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var footer: some View {
        HStack {
            Button { SettingsOpener.shared.open() } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.plain)
            Spacer()
            Button { NSApp.terminate(nil) } label: { Label("Quit", systemImage: "power") }
                .buttonStyle(.plain)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }
}
