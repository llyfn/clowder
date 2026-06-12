import Foundation
import IOKit.pwr_mgt
import Observation
import SwiftUI

@MainActor
public protocol PowerAsserting {
    func create(reason: String) -> UInt32?
    func release(_ id: UInt32)
}

@MainActor
public final class IOPMPowerAsserter: PowerAsserting {
    public init() {}

    public func create(reason: String) -> UInt32? {
        var id: IOPMAssertionID = 0
        // Prevents both display and idle system sleep — "keep awake" means the screen stays on.
        let rc = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString, &id)
        return rc == kIOReturnSuccess ? id : nil
    }

    public func release(_ id: UInt32) {
        IOPMAssertionRelease(id)
    }
}

public enum KeepAwakeState: Equatable, Sendable {
    case off
    case on(until: Date?)   // nil = indefinitely
}

@Observable @MainActor
public final class KeepAwakeEngine {
    public private(set) var state: KeepAwakeState = .off

    @ObservationIgnored private let asserter: any PowerAsserting
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var assertionID: UInt32?

    public init(asserter: any PowerAsserting, now: @escaping () -> Date = { Date() }) {
        self.asserter = asserter
        self.now = now
    }

    public func enable(for duration: TimeInterval?) {
        releaseAssertion()
        guard let id = asserter.create(reason: "Clowder keep-awake") else {
            state = .off
            return
        }
        assertionID = id
        state = .on(until: duration.map { now().addingTimeInterval($0) })
    }

    public func disable() {
        releaseAssertion()
        state = .off
    }

    /// Called from the poll loop; expires a timed assertion.
    public func tick() {
        if case .on(let until?) = state, now() >= until { disable() }
    }

    public var remaining: TimeInterval? {
        if case .on(let until?) = state { return max(0, until.timeIntervalSince(now())) }
        return nil
    }

    private func releaseAssertion() {
        if let id = assertionID { asserter.release(id) }
        assertionID = nil
    }
}

@Observable @MainActor
public final class KeepAwakeModule: Module {
    public let id = ModuleID.keepAwake
    public let engine: KeepAwakeEngine

    public init(engine: KeepAwakeEngine) {
        self.engine = engine
    }

    public func refresh(_ snapshot: SensorSnapshot) {
        engine.tick()
    }

    public var tileView: AnyView { AnyView(KeepAwakeTile(module: self)) }
    public var barItemView: AnyView? { AnyView(Image(systemName: iconName)) }

    private var iconName: String {
        engine.state == .off ? "cup.and.saucer" : "cup.and.saucer.fill"
    }
}

/// Wide control tile: toggle + timer menu (15 m / 1 h / indefinitely).
struct KeepAwakeTile: View {
    let module: KeepAwakeModule

    var body: some View {
        HStack {
            Label("Keep Awake", systemImage: module.engine.state == .off ? "cup.and.saucer" : "cup.and.saucer.fill")
            if let remaining = module.engine.remaining {
                Text(Duration.seconds(remaining).formatted(.time(pattern: .hourMinute)))
                    .foregroundStyle(.secondary).font(.caption)
            }
            Spacer()
            Menu {
                Button("15 Minutes") { module.engine.enable(for: 15 * 60) }
                Button("1 Hour") { module.engine.enable(for: 60 * 60) }
                Button("Until Turned Off") { module.engine.enable(for: nil) }
            } label: { Image(systemName: "timer") }
            .menuStyle(.borderlessButton).fixedSize()
            Toggle("", isOn: Binding(
                get: { module.engine.state != .off },
                set: { $0 ? module.engine.enable(for: nil) : module.engine.disable() }
            )).toggleStyle(.switch).labelsHidden()
        }
        .padding(12)
    }
}
