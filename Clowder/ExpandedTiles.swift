import Charts
import ClowderKit
import SwiftUI

/// Small reusable multi-series line chart over (index, value) points.
private struct MiniChart: View {
    let series: [(name: String, values: [Double], color: Color)]
    var yDomain: ClosedRange<Double>? = nil

    var body: some View {
        Chart {
            ForEach(series, id: \.name) { s in
                ForEach(Array(s.values.enumerated()), id: \.offset) { i, v in
                    LineMark(x: .value("t", i), y: .value(s.name, v),
                             series: .value("series", s.name))
                        .foregroundStyle(s.color)
                }
            }
        }
        .chartXAxis(.hidden)
        .chartLegend(.hidden)
        .modifier(YDomainModifier(domain: yDomain))
        .frame(height: 90)
    }
}

private struct YDomainModifier: ViewModifier {
    let domain: ClosedRange<Double>?
    func body(content: Content) -> some View {
        if let domain { content.chartYScale(domain: domain) } else { content }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String
    var color: Color = .secondary
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(color)
        }
        .font(.caption)
    }
}

struct CPUExpandedView: View {
    let module: CPUModule
    var body: some View {
        let h = module.history.elements
        VStack(alignment: .leading, spacing: 8) {
            MiniChart(series: [
                ("User", h.map(\.userLoad), .green),
                ("System", h.map(\.systemLoad), .red),
            ], yDomain: 0...1)
            DetailRow(label: "System", value: Format.percent(module.stats?.systemLoad ?? 0), color: .red)
            DetailRow(label: "User", value: Format.percent(module.stats?.userLoad ?? 0), color: .green)
            DetailRow(label: "Idle", value: Format.percent(module.stats?.idleLoad ?? 0))
        }
        .padding(12)
    }
}

struct MemoryExpandedView: View {
    let module: MemoryModule
    var body: some View {
        let h = module.history.elements
        VStack(alignment: .leading, spacing: 8) {
            MiniChart(series: [
                ("App", h.map { Double($0.appBytes) }, .blue),
                ("Wired", h.map { Double($0.wiredBytes) }, .orange),
                ("Compressed", h.map { Double($0.compressedBytes) }, .purple),
            ])
            DetailRow(label: "App Memory", value: module.appLine, color: .blue)
            DetailRow(label: "Wired", value: module.wiredLine, color: .orange)
            DetailRow(label: "Compressed", value: module.compressedLine, color: .purple)
            DetailRow(label: "Pressure", value: module.stats?.pressure.displayName ?? "—")
        }
        .padding(12)
    }
}

struct NetworkExpandedView: View {
    let module: NetworkModule
    var body: some View {
        let h = module.history.elements
        VStack(alignment: .leading, spacing: 8) {
            MiniChart(series: [
                ("Down", h.map(\.downBytesPerSec), .green),
                ("Up", h.map(\.upBytesPerSec), .blue),
            ])
            DetailRow(label: "Download", value: module.downLine, color: .green)
            DetailRow(label: "Upload", value: module.upLine, color: .blue)
        }
        .padding(12)
    }
}

struct StorageExpandedView: View {
    let module: DiskModule
    var body: some View {
        let h = module.ioHistory.elements
        VStack(alignment: .leading, spacing: 8) {
            MiniChart(series: [
                ("Read", h.map(\.readBytesPerSec), .green),
                ("Write", h.map(\.writeBytesPerSec), .red),
            ])
            DetailRow(label: "Read", value: module.readLine, color: .green)
            DetailRow(label: "Write", value: module.writeLine, color: .red)
            if let s = module.stats {
                DetailRow(label: "Used", value: Format.bytes(s.totalBytes - s.freeBytes))
                DetailRow(label: "Free", value: Format.bytes(s.freeBytes))
                DetailRow(label: "Total", value: Format.bytes(s.totalBytes))
            }
        }
        .padding(12)
    }
}

struct TempsExpandedView: View {
    let environment: AppEnvironment
    private var module: TempsModule { environment.temps }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !module.history.elements.isEmpty {
                MiniChart(series: [("Temp", module.history.elements, .orange)])
            }
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
                                Text("\(Int(fan.rpm.rounded())) RPM").font(.caption.monospacedDigit())
                            }
                        }
                        // Spec: per-fan sliders live here in manual mode only.
                        if environment.config.power.fanMode == .manual,
                           environment.helper.availability == .ready {
                            Divider()
                            FanRPMSliders(config: environment.config, fans: module.fans)
                                .font(.caption)
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .padding(12)
    }
}
