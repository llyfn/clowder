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
        .frame(width: 420)
        .padding(20)
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
            Toggle("Launch at login", isOn: $launchAtLogin)
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
            LabeledContent("Update every") {
                Slider(value: $config.general.pollInterval, in: 1...10, step: 1) {
                    EmptyView()
                } minimumValueLabel: { Text("1s") } maximumValueLabel: { Text("10s") }
                .frame(width: 200)
            }
            Picker("Runner", selection: $config.general.character) {
                ForEach(RunnerCharacter.allCases, id: \.self) { c in
                    Text(c.rawValue.capitalized).tag(c)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

private struct ModulesSettingsTab: View {
    let environment: AppEnvironment

    var body: some View {
        Form {
            ForEach(environment.allModules, id: \.id) { module in
                let binding = configBinding(for: module.id)
                Section(module.id.rawValue.capitalized) {
                    Toggle("Enabled", isOn: binding.enabled)
                    if module.barItemView != nil {
                        Toggle("Show in menu bar", isOn: binding.promotedToBar)
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
