import Foundation
import HelperCore
import HelperProtocol
import SMCCore

/// All state lives on one serial queue; XPC calls hop onto it.
final class HelperService: NSObject, ClowderHelperProtocol, @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.clowder.helper")
    private let smc: (any SMCWriting)?

    private var chargeLimitEnabled = false
    private var chargeLimitPercent = 80
    private var isInhibited = false
    private var fansManual = false
    private var lastHeartbeat = Date()
    private var timer: DispatchSourceTimer?

    private static let inhibitKeys = [SMCKey("CH0B"), SMCKey("CH0C")]

    override init() {
        smc = try? SMCClient()
        super.init()
    }

    func start() {
        queue.async { [self] in
            restoreDefaultsInternal()
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + 30, repeating: 30)
            t.setEventHandler { [weak self] in self?.controlTick() }
            t.resume()
            timer = t
        }
    }

    // MARK: control loop (always on `queue`)

    private func controlTick() {
        if WatchdogLogic.shouldRestoreFans(lastHeartbeat: lastHeartbeat, now: Date(),
                                           fansManual: fansManual) {
            _ = setFansAutoInternal()
        }
        chargeTick()
    }

    private func chargeTick() {
        guard chargeLimitEnabled, let level = BatteryLevel.read() else { return }
        switch ChargeControl.action(level: level, target: chargeLimitPercent,
                                    isInhibited: isInhibited) {
        case .inhibit: setInhibited(true)
        case .resume: setInhibited(false)
        case .none: break
        }
    }

    private func setInhibited(_ inhibit: Bool) {
        guard let smc else { return }
        let byte: [UInt8] = [inhibit ? 0x02 : 0x00]
        var ok = true
        for key in Self.inhibitKeys {
            do { try smc.writeBytes(key, bytes: byte) } catch { ok = false }
        }
        if ok { isInhibited = inhibit }
    }

    private func setFansAutoInternal() -> String? {
        guard let smc else { return "SMC unavailable" }
        guard let count = smc.readValue(SMCKey("FNum")), count > 0 else {
            fansManual = false
            return nil   // fanless: auto is trivially true
        }
        for i in 0..<Int(count) {
            try? smc.writeBytes(SMCKey("F\(i)Md"), bytes: [0x00])
        }
        fansManual = false
        return nil
    }

    private func restoreDefaultsInternal() {
        _ = setFansAutoInternal()
        setInhibited(false)
        chargeLimitEnabled = false
    }

    // MARK: ClowderHelperProtocol (XPC entry points)

    func getVersion(reply: @escaping @Sendable (Int) -> Void) {
        reply(HelperConstants.version)
    }

    func setChargeLimit(enabled: Bool, percent: Int, reply: @escaping @Sendable (String?) -> Void) {
        queue.async { [self] in
            guard smc != nil else { return reply("SMC unavailable") }
            chargeLimitEnabled = enabled
            chargeLimitPercent = min(max(percent, HelperConstants.chargeLimitRange.lowerBound),
                                     HelperConstants.chargeLimitRange.upperBound)
            if enabled {
                chargeTick()           // apply immediately, don't wait for the loop
            } else {
                setInhibited(false)    // disabling always resumes normal charging
            }
            reply(nil)
        }
    }

    func setFansAuto(reply: @escaping @Sendable (String?) -> Void) {
        queue.async { [self] in reply(setFansAutoInternal()) }
    }

    func setFanTargets(_ rpms: [Double], reply: @escaping @Sendable (String?) -> Void) {
        queue.async { [self] in
            guard let smc else { return reply("SMC unavailable") }
            guard let count = smc.readValue(SMCKey("FNum")), count > 0 else {
                return reply("no fans on this Mac")
            }
            let fanCount = Int(count)
            guard rpms.count == fanCount else {
                return reply("expected \(fanCount) targets, got \(rpms.count)")
            }
            // Validate every target against the hardware floor BEFORE writing any.
            var clamped: [Double] = []
            for (i, rpm) in rpms.enumerated() {
                let minRPM = smc.readValue(SMCKey("F\(i)Mn")) ?? 0
                let maxRPM = smc.readValue(SMCKey("F\(i)Mx")) ?? .greatestFiniteMagnitude
                guard let target = FanRules.clampedTarget(rpm, minRPM: minRPM, maxRPM: maxRPM) else {
                    return reply("fan \(i): \(Int(rpm)) rpm is below the hardware minimum \(Int(minRPM))")
                }
                clamped.append(target)
            }
            for (i, target) in clamped.enumerated() {
                guard let bytes = SMCValueEncoder.encode(target, type: "flt ") else { continue }
                try? smc.writeBytes(SMCKey("F\(i)Md"), bytes: [0x01])
                try? smc.writeBytes(SMCKey("F\(i)Tg"), bytes: bytes)
            }
            fansManual = true
            lastHeartbeat = Date()   // a control action counts as liveness
            reply(nil)
        }
    }

    func restoreDefaults(reply: @escaping @Sendable (String?) -> Void) {
        queue.async { [self] in
            restoreDefaultsInternal()
            reply(nil)
        }
    }

    func heartbeat() {
        queue.async { [self] in lastHeartbeat = Date() }
    }
}
