import ClowderKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let environment: AppEnvironment

    var body: some View {
        TabView {
            GeneralSettingsTab(environment: environment)
                .tabItem { Label("General", systemImage: "gearshape") }
            PowerSettingsTab(environment: environment)
                .tabItem { Label("Power", systemImage: "bolt.fill") }
            ModulesSettingsTab(environment: environment)
                .tabItem { Label("Modules", systemImage: "square.grid.2x2") }
            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 500, height: 440)
    }
}

private struct GeneralSettingsTab: View {
    @Bindable var config: ConfigStore
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    init(environment: AppEnvironment) {
        self.config = environment.config
    }

    var body: some View {
        Form {
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    do {
                        if on {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            LabeledContent("Update Every") {
                Slider(value: $config.general.pollInterval, in: 1...10, step: 1) {
                    EmptyView()
                } minimumValueLabel: { Text("1s") } maximumValueLabel: { Text("10s") }
                .frame(width: 220)
            }
            Picker("Runner", selection: $config.general.character) {
                ForEach(RunnerCharacter.allCases, id: \.self) { c in
                    Text(c.rawValue.capitalized).tag(c)
                }
            }
            .pickerStyle(.segmented)
        }
        .formStyle(.grouped)
    }
}

private struct ModulesSettingsTab: View {
    let environment: AppEnvironment

    var body: some View {
        Form {
            ForEach(environment.allModules, id: \.id) { module in
                let binding = configBinding(for: module.id)
                Section(module.id.displayName) {
                    Toggle("Enabled", isOn: binding.enabled)
                    if module.barItemView != nil {
                        Toggle("Show in Menu Bar", isOn: binding.promotedToBar)
                            .disabled(!binding.enabled.wrappedValue)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func configBinding(for id: ModuleID) -> (enabled: Binding<Bool>, promotedToBar: Binding<Bool>) {
        let config = environment.config
        return (
            enabled: Binding(get: { config.config(for: id).enabled },
                             set: { var c = config.config(for: id); c.enabled = $0; config.setConfig(c, for: id) }),
            promotedToBar: Binding(get: { config.config(for: id).promotedToBar },
                                   set: { var c = config.config(for: id); c.promotedToBar = $0; config.setConfig(c, for: id) })
        )
    }
}

private extension ModuleID {
    /// Title Case display names; raw values are lowercased identifiers
    /// (`keepAwake`.capitalized would render as "Keepawake").
    var displayName: String {
        switch self {
        case .cpu: "CPU"
        case .keepAwake: "Keep Awake"
        case .temps: "Temperatures"
        case .fans: "Fans"
        case .battery: "Battery"
        case .network: "Network"
        case .memory: "Memory"
        case .disk: "Disk"
        }
    }
}
