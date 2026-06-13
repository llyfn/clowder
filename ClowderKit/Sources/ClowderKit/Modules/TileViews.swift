import SwiftUI

/// The shared stat-tile look: icon + small caps label, headline value, secondary subline.
public struct StatTile: View {
    let label: String
    let headline: String
    let subline: String
    let icon: String

    public init(label: String, headline: String, subline: String, icon: String) {
        self.label = label
        self.headline = headline
        self.subline = subline
        self.icon = icon
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(label, systemImage: icon)
                .font(.caption2).foregroundStyle(.secondary)
            Text(headline).font(.title3.weight(.semibold)).monospacedDigit()
            Text(subline).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }
}
