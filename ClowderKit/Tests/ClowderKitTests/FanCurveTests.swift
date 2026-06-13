// ClowderKit/Tests/ClowderKitTests/FanCurveTests.swift
import Testing

@testable import ClowderKit

struct FanCurveTests {
    private let curve = FanCurve(points: [
        CurvePoint(celsius: 50, rpm: 1500),
        CurvePoint(celsius: 90, rpm: 6000),
    ])

    @Test func interpolatesLinearly() {
        #expect(curve.rpm(at: 50) == 1500)
        #expect(curve.rpm(at: 90) == 6000)
        #expect(curve.rpm(at: 70) == 3750)  // midpoint
    }

    @Test func clampsOutOfRange() {
        #expect(curve.rpm(at: 20) == 1500)
        #expect(curve.rpm(at: 110) == 6000)
    }

    @Test func sortsUnorderedPoints() {
        let c = FanCurve(points: [
            CurvePoint(celsius: 90, rpm: 6000),
            CurvePoint(celsius: 50, rpm: 1500),
        ])
        #expect(c.rpm(at: 70) == 3750)
    }

    @Test func threePointCurve() {
        let c = FanCurve(points: [
            CurvePoint(celsius: 40, rpm: 1200),
            CurvePoint(celsius: 70, rpm: 3000),
            CurvePoint(celsius: 95, rpm: 6800),
        ])
        #expect(c.rpm(at: 55) == 2100)  // halfway 40→70
        #expect(abs(c.rpm(at: 80) - 4520) < 0.0001)  // 3000 + (10/25)*3800
    }
}

@MainActor
struct FanCurveEngineTests {
    private func makeEngine() -> FanCurveEngine {
        FanCurveEngine(
            curve: FanCurve(points: [
                CurvePoint(celsius: 50, rpm: 1500),
                CurvePoint(celsius: 90, rpm: 6000),
            ]))
    }

    @Test func firstEvaluationEmits() {
        let engine = makeEngine()
        #expect(engine.evaluate(temp: 70) == 3750)
    }

    @Test func smallTempChangesAreHysteresisSuppressed() {
        let engine = makeEngine()
        _ = engine.evaluate(temp: 70)
        #expect(engine.evaluate(temp: 71) == nil)  // |Δ| < 3 → no new target
        #expect(engine.evaluate(temp: 72.9) == nil)
        #expect(engine.evaluate(temp: 73) != nil)  // |Δ| >= 3 → re-evaluate
    }

    @Test func resetForgetsHistory() {
        let engine = makeEngine()
        _ = engine.evaluate(temp: 70)
        engine.reset()
        #expect(engine.evaluate(temp: 70) == 3750)
    }
}
