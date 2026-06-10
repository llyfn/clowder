import ClowderKit
import SwiftUI

struct CPUExpandedView: View {
    let module: CPUModule

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array((module.stats?.perCore ?? []).enumerated()), id: \.offset) { i, load in
                HStack(spacing: 6) {
                    Text("\(i)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 16, alignment: .trailing)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary)
                            Capsule().fill(.tint).frame(width: geo.size.width * load)
                        }
                    }
                    .frame(height: 6)
                    Text(Format.percent(load)).font(.caption2.monospacedDigit())
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
        .padding(12)
    }
}

struct TempsExpandedView: View {
    let module: TempsModule

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(module.temps) { reading in
                        HStack {
                            Text(reading.id).font(.caption.monospaced())
                            Spacer()
                            Text(Format.temp(reading.celsius)).font(.caption.monospacedDigit())
                        }
                    }
                    if !module.fans.isEmpty {
                        Divider()
                        ForEach(module.fans) { fan in
                            HStack {
                                Text("Fan \(fan.id)").font(.caption)
                                Spacer()
                                Text("\(Int(fan.rpm.rounded())) rpm").font(.caption.monospacedDigit())
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .padding(12)
    }
}
