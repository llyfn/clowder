import Testing
import Foundation
@testable import ClowderKit

@MainActor
private final class FakeAsserter: PowerAsserting {
    var active: UInt32?
    var nextID: UInt32 = 7
    func create(reason: String) -> UInt32? { active = nextID; return nextID }
    func release(_ id: UInt32) { if active == id { active = nil } }
}

@MainActor
struct KeepAwakeTests {
    @Test func enableIndefinitelyCreatesAssertion() {
        let asserter = FakeAsserter()
        var now = Date(timeIntervalSinceReferenceDate: 0)
        let engine = KeepAwakeEngine(asserter: asserter, now: { now })
        engine.enable(for: nil)
        #expect(engine.state == .on(until: nil))
        #expect(asserter.active != nil)
        now += 100_000
        engine.tick()
        #expect(engine.state == .on(until: nil))   // never expires
    }

    @Test func timedEnableExpiresViaTick() {
        let asserter = FakeAsserter()
        var now = Date(timeIntervalSinceReferenceDate: 0)
        let engine = KeepAwakeEngine(asserter: asserter, now: { now })
        engine.enable(for: 900)
        #expect(engine.state == .on(until: Date(timeIntervalSinceReferenceDate: 900)))
        now = Date(timeIntervalSinceReferenceDate: 899)
        engine.tick()
        #expect(asserter.active != nil)
        now = Date(timeIntervalSinceReferenceDate: 901)
        engine.tick()
        #expect(engine.state == .off)
        #expect(asserter.active == nil)            // assertion released
    }

    @Test func disableReleases() {
        let asserter = FakeAsserter()
        let engine = KeepAwakeEngine(asserter: asserter, now: { Date() })
        engine.enable(for: nil)
        engine.disable()
        #expect(engine.state == .off)
        #expect(asserter.active == nil)
    }

    @Test func reenableReplacesTimer() {
        let asserter = FakeAsserter()
        var now = Date(timeIntervalSinceReferenceDate: 0)
        let engine = KeepAwakeEngine(asserter: asserter, now: { now })
        engine.enable(for: 60)
        engine.enable(for: 3600)
        now = Date(timeIntervalSinceReferenceDate: 100)
        engine.tick()
        #expect(engine.state == .on(until: Date(timeIntervalSinceReferenceDate: 3600)))
    }
}
