import ClowderKit
import SwiftUI

/// The Control Center-style tile grid.
struct PanelView: View {
    // Plain `let` is enough for reactivity: body reads properties of the
    // @Observable module classes held by the environment, and SwiftUI tracks
    // those objects directly. Holds only as long as modules are mutated, not replaced.
    let environment: AppEnvironment

    @State private var expanded: ModuleID?

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 10) {
                LazyVGrid(columns: columns, spacing: 10) {
                    expandableTile(.cpu, collapsed: environment.cpu.tileView,
                                   expanded: AnyView(CPUExpandedView(module: environment.cpu)))
                    expandableTile(.temps, collapsed: environment.temps.tileView,
                                   expanded: AnyView(TempsExpandedView(module: environment.temps)))
                    tile(environment.memory.tileView)
                    tile(networkDiskTile)
                }
                tile(environment.keepAwake.tileView)   // wide control tile
                footer
            }
            .padding(12)
        }
        .frame(width: 340)
    }

    /// Network tile carries the disk subline, per the approved panel design.
    private var networkDiskTile: AnyView {
        AnyView(VStack(alignment: .leading, spacing: 2) {
            Label("NETWORK", systemImage: "network")
                .font(.caption2).foregroundStyle(.secondary)
            Text(environment.network.downLine).font(.title3.weight(.semibold)).monospacedDigit()
            Text("\(environment.network.upLine) · \(environment.disk.headline)")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12))
    }

    private func tile(_ content: AnyView) -> some View {
        content
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }

    private func expandableTile(_ id: ModuleID, collapsed: AnyView, expanded expandedView: AnyView) -> some View {
        Group {
            if expanded == id { expandedView } else { collapsed }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .onTapGesture {
            withAnimation(.snappy) { expanded = expanded == id ? nil : id }
        }
    }

    private var footer: some View {
        HStack {
            SettingsLink { Label("Settings", systemImage: "gearshape") }
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
