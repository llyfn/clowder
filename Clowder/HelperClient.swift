import ClowderKit
import Foundation
import HelperProtocol
import Observation
import ServiceManagement

@Observable @MainActor
final class HelperClient: PowerControlling {
    private(set) var availability: PowerAvailability = .notRegistered

    @ObservationIgnored private var connection: NSXPCConnection?
    @ObservationIgnored private var didAttemptReinstall = false
    // nonisolated(unsafe): written on MainActor only; deinit is the sole non-isolated reader.
    @ObservationIgnored nonisolated(unsafe) private var heartbeatTimer: Timer?

    deinit { heartbeatTimer?.invalidate() }

    func connect() {
        // Spec: SMC write features are Apple Silicon only; Intel Macs get a clear refusal.
        #if !arch(arm64)
            availability = .unavailable("battery and fan control require Apple Silicon")
            return
        #endif
        let service = SMAppService.daemon(plistName: HelperConstants.daemonPlistName)
        switch service.status {
        case .enabled:
            establishConnection()
        case .requiresApproval:
            availability = .requiresApproval
            SMAppService.openSystemSettingsLoginItems()
        case .notRegistered, .notFound:
            do {
                try service.register()
                if service.status == .enabled {
                    establishConnection()
                } else {
                    availability = .requiresApproval
                    SMAppService.openSystemSettingsLoginItems()
                }
            } catch {
                availability = .unavailable(error.localizedDescription)
            }
        @unknown default:
            availability = .unavailable("unknown SMAppService status")
        }
    }

    private func establishConnection() {
        connection?.invalidate()
        let conn = NSXPCConnection(
            machServiceName: HelperConstants.machServiceName,
            options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: ClowderHelperProtocol.self)
        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.stopHeartbeat()
                self?.availability = .unavailable("helper connection invalidated")
            }
        }
        // launchd interrupts (not invalidates) the connection if the helper dies;
        // the service relaunches on demand, so re-run the handshake.
        conn.interruptionHandler = { [weak self] in
            Task { @MainActor in self?.establishConnection() }
        }
        conn.resume()
        connection = conn

        // Version handshake before declaring ready.
        guard
            let proxy = conn.remoteObjectProxyWithErrorHandler({ [weak self] error in
                Task { @MainActor in self?.availability = .unavailable(error.localizedDescription) }
            }) as? ClowderHelperProtocol
        else {
            availability = .unavailable("bad proxy")
            return
        }
        proxy.getVersion { [weak self] version in
            Task { @MainActor in
                guard let self else { return }
                if version == HelperConstants.version {
                    self.availability = .ready
                    self.didAttemptReinstall = false
                    self.startHeartbeat()
                } else if self.didAttemptReinstall {
                    // One reinstall attempt only — never loop against a stale binary.
                    self.availability = .unavailable(
                        "helper version \(version) ≠ app \(HelperConstants.version) after reinstall"
                    )
                } else {
                    self.availability = .unavailable(
                        "helper version \(version) ≠ app \(HelperConstants.version) — re-registering"
                    )
                    self.didAttemptReinstall = true
                    self.reinstall()
                }
            }
        }
    }

    private func reinstall() {
        let service = SMAppService.daemon(plistName: HelperConstants.daemonPlistName)
        try? service.unregister()
        connect()
    }

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        let t = Timer(timeInterval: HelperConstants.heartbeatInterval, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.proxy()?.heartbeat() }
        }
        RunLoop.main.add(t, forMode: .common)
        heartbeatTimer = t
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func proxy() -> ClowderHelperProtocol? {
        connection?.remoteObjectProxyWithErrorHandler { [weak self] error in
            Task { @MainActor in self?.availability = .unavailable(error.localizedDescription) }
        } as? ClowderHelperProtocol
    }

    /// Wraps a reply-style helper call into async. Returns an error string or nil.
    private func call(
        _ body: (ClowderHelperProtocol, @escaping @Sendable (String?) -> Void) -> Void
    )
        async -> String?
    {
        guard availability == .ready, let proxy = proxy() else { return "helper not available" }
        return await withCheckedContinuation { continuation in
            body(proxy) { error in continuation.resume(returning: error) }
        }
    }

    func setChargeLimit(enabled: Bool, percent: Int) async -> String? {
        await call { proxy, reply in
            proxy.setChargeLimit(enabled: enabled, percent: percent, reply: reply)
        }
    }

    func setFansAuto() async -> String? {
        await call { proxy, reply in proxy.setFansAuto(reply: reply) }
    }

    func setFanTargets(_ rpms: [Double]) async -> String? {
        await call { proxy, reply in proxy.setFanTargets(rpms, reply: reply) }
    }
}
