import ClowderKit
import SwiftUI

/// The Control Center-style tile grid.
struct PanelView: View {
    let environment: AppEnvironment

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 10) {
                LazyVGrid(columns: columns, spacing: 10) {
                    tile(environment.cpu.tileView)
                    tile(environment.temps.tileView)
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
