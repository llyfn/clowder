import Foundation
import Observation

public struct GeneralConfig: Codable, Equatable, Sendable {
    public var pollInterval: TimeInterval = 2
    public var character: RunnerCharacter = .cat
    public init() {}
}

public struct ModuleConfig: Codable, Equatable, Sendable {
    public var enabled: Bool = true
    public var promotedToBar: Bool = false
    public init() {}
}

@Observable @MainActor
public final class ConfigStore {
    private static let key = "clowder.config.v1"

    private struct Persisted: Codable {
        var general: GeneralConfig
        var modules: [String: ModuleConfig]
    }

    @ObservationIgnored private var _general: GeneralConfig
    public var general: GeneralConfig {
        get { access(keyPath: \.general); return _general }
        set {
            withMutation(keyPath: \.general) {
                _general = newValue
                _general.pollInterval = min(max(_general.pollInterval, 1), 10)
                save()
            }
        }
    }

    @ObservationIgnored private var _modules: [String: ModuleConfig]
    private var modules: [String: ModuleConfig] {
        get { access(keyPath: \.modules); return _modules }
        set {
            withMutation(keyPath: \.modules) {
                _modules = newValue
                save()
            }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var general = GeneralConfig()
        var modules: [String: ModuleConfig] = [:]
        if let data = defaults.data(forKey: Self.key),
           let p = try? JSONDecoder().decode(Persisted.self, from: data) {
            general = p.general
            modules = p.modules
        }
        general.pollInterval = min(max(general.pollInterval, 1), 10)
        self._general = general
        self._modules = modules
    }

    public func config(for id: ModuleID) -> ModuleConfig {
        modules[id.rawValue] ?? ModuleConfig()
    }

    public func setConfig(_ config: ModuleConfig, for id: ModuleID) {
        modules[id.rawValue] = config
    }

    private func save() {
        let p = Persisted(general: _general, modules: _modules)
        defaults.set(try? JSONEncoder().encode(p), forKey: Self.key)
    }
}
