import Charts
import ClowderKit
import SwiftUI

struct BatteryExpandedView: View {
    let module: BatteryModule
    @State private var pendingError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if module.batteryHistory.count > 1 {
                Chart(module.batteryHistory) { point in
                    LineMark(x: .value("Time", point.date), y: .value("Level", point.level))
                        .foregroundStyle(.green)
                }
                .chartYScale(domain: 0...100)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .frame(height: 90)
            } else {
                Text("Collecting battery history…")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 90)
            }

            Text(statusText).font(.caption).foregroundStyle(.secondary)

            Divider()

            HStack {
                Label("Charge Limit", systemImage: "battery.75percent").font(.caption)
                Spacer()
                switch module.availability {
                case .ready:
                    Stepper("\(module.config.power.chargeLimitPercent)%",
                            value: Binding(
                                get: { module.config.power.chargeLimitPercent },
                                set: { newValue in
                                    Task { pendingError = await module.applyChargeLimit(
                                        enabled: module.config.power.chargeLimitEnabled, percent: newValue) }
                                }),
                            in: 50...100, step: 5)
                        .font(.caption).fixedSize()
                    Toggle("", isOn: Binding(
                        get: { module.config.power.chargeLimitEnabled },
                        set: { on in
                            Task { pendingError = await module.applyChargeLimit(
                                enabled: on, percent: module.config.power.chargeLimitPercent) }
                        }))
                        .toggleStyle(.switch).labelsHidden()
                case .requiresApproval:
                    Button("Approve in System Settings") { module.requestHelper() }.font(.caption)
                default:
                    Button("Enable") { module.requestHelper() }.font(.caption)
                }
            }
            if let pendingError {
                Text(pendingError).font(.caption2).foregroundStyle(.red).lineLimit(1)
            }
        }
        .padding(12)
    }

    private var statusText: String {
        guard let s = module.stats else { return "No Battery" }
        if s.isCharging { return "Charging · \(s.levelPercent)%" }
        if s.isOnAC { return "Plugged In · \(s.levelPercent)%" }
        return "On Battery · \(s.levelPercent)%"
    }
}
