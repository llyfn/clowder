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

                if isEnabled(.memory) || isEnabled(.network) {
                    HStack(alignment: .top, spacing: 10) {
                        if isEnabled(.memory) {
                            expandableTile(.memory, collapsed: environment.memory.tileView)
                        }
                        if isEnabled(.network) {
                            expandableTile(.network, collapsed: environment.network.tileView)
                        }
                    }
                }
                if expanded == .memory, isEnabled(.memory) {
                    detailCard(AnyView(MemoryExpandedView(module: environment.memory)))
                }
                if expanded == .network, isEnabled(.network) {
                    detailCard(AnyView(NetworkExpandedView(module: environment.network)))
                }

                if isEnabled(.disk) || isEnabled(.battery) {
                    HStack(alignment: .top, spacing: 10) {
                        if isEnabled(.disk) {
                            expandableTile(.disk, collapsed: environment.disk.tileView)
                        }
                        if isEnabled(.battery) {
                            expandableTile(.battery, collapsed: environment.battery.tileView)
                        }
                    }
                }
                if expanded == .disk, isEnabled(.disk) {
                    detailCard(AnyView(StorageExpandedView(module: environment.disk)))
                }
                if expanded == .battery, isEnabled(.battery) {
                    detailCard(AnyView(BatteryExpandedView(module: environment.battery)))
                }

                if isEnabled(.keepAwake) { tile(environment.keepAwake.tileView) }
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
            Button {
                SettingsOpener.shared.open()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.plain)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }
}
