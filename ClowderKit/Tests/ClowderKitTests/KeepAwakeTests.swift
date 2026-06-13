import Foundation
import Testing

@testable import ClowderKit

@MainActor
private final class FakeAsserter: PowerAsserting {
    var active: UInt32?
    var nextID: UInt32 = 7
    var createCallCount: Int = 0
    func create(reason: String) -> UInt32? {
        let id = nextID
        nextID += 1
        createCallCount += 1
        active = id
        return id
    }
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
        #expect(engine.state == .on(until: nil))  // never expires
    }

    @Test func timedEnableExpiresViaTick() {
        let asserter = FakeAsserter()
        var now = Date(timeIntervalSinceReferenceDate: 0)
        let engine = KeepAwakeEngine(asserter: asserter, now: { now })
        engine.enable(for: 900)
        #expect(engine.state == .on(until: Date(timeIntervalSinceReferenceDate: 900)))
        now = Date(timeIntervalSinceReferenceDate: 899)
        engine.tick()
        #expect(asserter.active != nil)  // still on at t=899
        now = Date(timeIntervalSinceReferenceDate: 900)
        engine.tick()
        #expect(engine.state == .off)
        #expect(asserter.active == nil)  // assertion released at exact boundary
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
        #expect(asserter.createCallCount == 2)
    }
}
