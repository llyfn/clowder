import Observation
import SwiftUI

@Observable @MainActor
public final class BatteryModule: Module {
    public let id = ModuleID.battery
    public private(set) var stats: BatteryStats?

    public let config: ConfigStore
    private let power: any PowerControlling

    public init(config: ConfigStore, power: any PowerControlling) {
        self.config = config
        self.power = power
    }

    public func refresh(_ snapshot: SensorSnapshot) {
        stats = snapshot.battery
    }

    public var headline: String { stats.map { "\($0.levelPercent)%" } ?? "—" }
    public var subline: String {
        guard let stats else { return "no battery" }
        let charge = stats.isCharging ? "charging" : "on battery"
        return config.power.chargeLimitEnabled
            ? "limit \(config.power.chargeLimitPercent)% · \(charge)" : charge
    }
    public var availability: PowerAvailability { power.availability }

    /// Persists the limit and pushes it to the helper. Returns an error string or nil.
    @discardableResult
    public func applyChargeLimit(enabled: Bool, percent: Int) async -> String? {
        var p = config.power
        p.chargeLimitEnabled = enabled
        p.chargeLimitPercent = percent
        config.power = p   // setter clamps; read back the clamped value for the helper
        return await power.setChargeLimit(enabled: config.power.chargeLimitEnabled,
                                          percent: config.power.chargeLimitPercent)
    }

    public func requestHelper() {
        power.connect()
    }

    public var tileView: AnyView { AnyView(ChargeLimitTile(module: self)) }
    public var barItemView: AnyView? { AnyView(Text(headline).monospacedDigit()) }
}

/// Wide control tile: battery status + limit toggle and stepper, or a helper-enable CTA.
struct ChargeLimitTile: View {
    let module: BatteryModule
    @State private var pendingError: String?

    var body: some View {
        HStack {
            Label("Charge limit", systemImage: "battery.75percent")
            Text(module.headline + " · " + module.subline)
                .font(.caption).foregroundStyle(.secondary)
            if let pendingError {
                Text(pendingError).font(.caption2).foregroundStyle(.red).lineLimit(1)
            }
            Spacer()
            switch module.availability {
            case .ready:
                Stepper("\(module.config.power.chargeLimitPercent)%",
                        value: Binding(
                            get: { module.config.power.chargeLimitPercent },
                            set: { newValue in
                                Task { pendingError = await module.applyChargeLimit(
                                    enabled: module.config.power.chargeLimitEnabled,
                                    percent: newValue) }
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
                Button("Approve in System Settings") { module.requestHelper() }
                    .font(.caption)
            default:
                Button("Enable") { module.requestHelper() }
                    .font(.caption)
            }
        }
        .padding(12)
    }
}
