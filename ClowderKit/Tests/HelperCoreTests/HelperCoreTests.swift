import Foundation
import Testing

@testable import HelperCore

struct ChargeControlTests {
    @Test func inhibitsAtOrAboveTarget() {
        #expect(ChargeControl.action(level: 80, target: 80, isInhibited: false) == .inhibit)
        #expect(ChargeControl.action(level: 85, target: 80, isInhibited: false) == .inhibit)
        #expect(ChargeControl.action(level: 80, target: 80, isInhibited: true) == .none)
    }

    @Test func holdsInsideHysteresisBand() {
        // target 80, hysteresis 3: levels 78-79 keep current state
        #expect(ChargeControl.action(level: 79, target: 80, isInhibited: true) == .none)
        #expect(ChargeControl.action(level: 78, target: 80, isInhibited: true) == .none)
        #expect(ChargeControl.action(level: 79, target: 80, isInhibited: false) == .none)
    }

    @Test func resumesBelowBand() {
        #expect(ChargeControl.action(level: 77, target: 80, isInhibited: true) == .resume)
        #expect(ChargeControl.action(level: 77, target: 80, isInhibited: false) == .none)
    }
}

struct FanRulesTests {
    @Test func clampsToMaxAndRefusesBelowFloor() {
        #expect(FanRules.clampedTarget(7000, minRPM: 1200, maxRPM: 6800) == 6800)
        #expect(FanRules.clampedTarget(2000, minRPM: 1200, maxRPM: 6800) == 2000)
        // safety floor refuses
        #expect(FanRules.clampedTarget(900, minRPM: 1200, maxRPM: 6800) == nil)
    }
}

struct WatchdogTests {
    @Test func firesOnlyWhenManualAndStale() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        #expect(WatchdogLogic.shouldRestoreFans(lastHeartbeat: t0, now: t0 + 91, fansManual: true))
        #expect(!WatchdogLogic.shouldRestoreFans(lastHeartbeat: t0, now: t0 + 89, fansManual: true))
        // boundary: strictly greater fires
        #expect(!WatchdogLogic.shouldRestoreFans(lastHeartbeat: t0, now: t0 + 90, fansManual: true))
        #expect(
            !WatchdogLogic.shouldRestoreFans(lastHeartbeat: t0, now: t0 + 9_999, fansManual: false))
    }
}
