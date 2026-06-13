import Foundation
import HelperProtocol
import Observation

public enum FanControlMode: String, Codable, Equatable, Sendable, CaseIterable {
    case auto, manual, curve
}

public struct PowerConfig: Codable, Equatable, Sendable {
    public var chargeLimitEnabled = false
    public var chargeLimitPercent = 80  // clamped to HelperConstants.chargeLimitRange
    public var fanMode: FanControlMode = .auto
    public var manualRPMs: [Int: Double] = [:]  // fan index → target
    public var curve = FanCurve(points: [
        CurvePoint(celsius: 50, rpm: 1500),
        CurvePoint(celsius: 90, rpm: 6000),
    ])
    public init() {}
}

public struct GeneralConfig: Codable, Equatable, Sendable {
    public var pollInterval: TimeInterval = 2
    public var character: RunnerCharacter = .clowder
    public init() {}

    private enum CodingKeys: String, CodingKey { case pollInterval, character }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pollInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .pollInterval) ?? 2
        // A removed/unknown runner (e.g. "dog", "rocket") decodes to clowder
        // instead of failing the whole config load.
        character = (try? c.decode(RunnerCharacter.self, forKey: .character)) ?? .clowder
    }
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
        var power: PowerConfig?
    }

    @ObservationIgnored private var _general: GeneralConfig
    public var general: GeneralConfig {
        get {
            access(keyPath: \.general)
            return _general
        }
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
        get {
            access(keyPath: \.modules)
            return _modules
        }
        set {
            withMutation(keyPath: \.modules) {
                _modules = newValue
                save()
            }
        }
    }

    @ObservationIgnored private var _power: PowerConfig
    public var power: PowerConfig {
        get {
            access(keyPath: \.power)
            return _power
        }
        set {
            withMutation(keyPath: \.power) {
                _power = newValue
                _power.chargeLimitPercent = min(
                    max(
                        _power.chargeLimitPercent,
                        HelperConstants.chargeLimitRange.lowerBound),
                    HelperConstants.chargeLimitRange.upperBound)
                save()
            }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var general = GeneralConfig()
        var modules: [String: ModuleConfig] = [:]
        var power = PowerConfig()
        if let data = defaults.data(forKey: Self.key),
            let p = try? JSONDecoder().decode(Persisted.self, from: data)
        {
            general = p.general
            modules = p.modules
            power = p.power ?? PowerConfig()
        }
        general.pollInterval = min(max(general.pollInterval, 1), 10)
        power.chargeLimitPercent = min(
            max(
                power.chargeLimitPercent,
                HelperConstants.chargeLimitRange.lowerBound),
            HelperConstants.chargeLimitRange.upperBound)
        self._general = general
        self._modules = modules
        self._power = power
    }

    public func config(for id: ModuleID) -> ModuleConfig {
        modules[id.rawValue] ?? ModuleConfig()
    }

    public func setConfig(_ config: ModuleConfig, for id: ModuleID) {
        modules[id.rawValue] = config
    }

    private func save() {
        let p = Persisted(general: _general, modules: _modules, power: _power)
        defaults.set(try? JSONEncoder().encode(p), forKey: Self.key)
    }
}
