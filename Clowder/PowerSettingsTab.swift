// Clowder/PowerSettingsTab.swift
import ClowderKit
import SwiftUI

struct PowerSettingsTab: View {
    @Bindable var config: ConfigStore
    let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        self.config = environment.config
    }

    var body: some View {
        Form {
            helperSection
            chargeSection
            fanSection
        }
        .formStyle(.grouped)
    }

    private var helperSection: some View {
        Section("Privileged helper") {
            switch environment.helper.availability {
            case .ready:
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .requiresApproval:
                LabeledContent("Waiting for approval") {
                    Button("Open System Settings") { environment.helper.connect() }
                }
            case .unavailable(let reason):
                LabeledContent(reason) {
                    Button("Retry") { environment.helper.connect() }
                }
            case .notRegistered:
                LabeledContent("Battery and fan control need a privileged helper") {
                    Button("Enable") { environment.helper.connect() }
                }
            }
        }
    }

    private var chargeSection: some View {
        Section("Battery") {
            Toggle("Limit charging", isOn: Binding(
                get: { config.power.chargeLimitEnabled },
                set: { on in Task { _ = await environment.battery.applyChargeLimit(
                    enabled: on, percent: config.power.chargeLimitPercent) } }))
            Stepper("Charge limit: \(config.power.chargeLimitPercent)%",
                    value: Binding(
                        get: { config.power.chargeLimitPercent },
                        set: { v in Task { _ = await environment.battery.applyChargeLimit(
                            enabled: config.power.chargeLimitEnabled, percent: v) } }),
                    in: 50...100, step: 5)
                .disabled(!config.power.chargeLimitEnabled)
        }
        .disabled(environment.helper.availability != .ready)
    }

    @ViewBuilder
    private var fanSection: some View {
        Section("Fans") {
            if environment.store.snapshot.fans.isEmpty {
                Text("No fans on this Mac").foregroundStyle(.secondary)
            } else {
                Picker("Mode", selection: Binding(
                    get: { config.power.fanMode },
                    set: { mode in var p = config.power; p.fanMode = mode; config.power = p })) {
                    ForEach(FanControlMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue.capitalized).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if config.power.fanMode == .manual {
                    ForEach(environment.store.snapshot.fans) { fan in
                        LabeledContent("Fan \(fan.id)") {
                            Slider(value: Binding(
                                get: { config.power.manualRPMs[fan.id] ?? fan.minRPM },
                                set: { v in var p = config.power
                                       p.manualRPMs[fan.id] = v.rounded(); config.power = p }),
                                in: fan.minRPM...fan.maxRPM)
                            Text("\(Int(config.power.manualRPMs[fan.id] ?? fan.minRPM)) rpm")
                                .font(.caption.monospacedDigit()).frame(width: 70)
                        }
                    }
                }

                if config.power.fanMode == .curve {
                    CurveEditor(config: config)
                }

                if let error = environment.fanControl.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .disabled(environment.helper.availability != .ready)
    }
}

/// Point-based curve editor: 2–5 (temperature, RPM) rows with add/remove.
private struct CurveEditor: View {
    @Bindable var config: ConfigStore

    var body: some View {
        ForEach(config.power.curve.points.indices, id: \.self) { i in
            HStack {
                Stepper("\(Int(config.power.curve.points[i].celsius)) °C",
                        value: bindingFor(i, \.celsius), in: 30...110, step: 5)
                Stepper("\(Int(config.power.curve.points[i].rpm)) rpm",
                        value: bindingFor(i, \.rpm), in: 1000...7000, step: 250)
                Button(role: .destructive) { removePoint(i) } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
                .disabled(config.power.curve.points.count <= 2)
            }
            .font(.caption)
        }
        Button {
            var p = config.power
            var points = p.curve.points
            points.append(CurvePoint(celsius: 100, rpm: 6500))
            p.curve = FanCurve(points: points)
            config.power = p
        } label: { Label("Add point", systemImage: "plus.circle") }
        .disabled(config.power.curve.points.count >= 5)
    }

    private func bindingFor(_ index: Int, _ keyPath: WritableKeyPath<CurvePoint, Double>) -> Binding<Double> {
        Binding(
            get: { config.power.curve.points[index][keyPath: keyPath] },
            set: { value in
                var p = config.power
                var points = p.curve.points
                points[index][keyPath: keyPath] = value
                p.curve = FanCurve(points: points)   // re-sorts by temperature
                config.power = p
            })
    }

    private func removePoint(_ index: Int) {
        var p = config.power
        var points = p.curve.points
        points.remove(at: index)
        p.curve = FanCurve(points: points)
        config.power = p
    }
}
