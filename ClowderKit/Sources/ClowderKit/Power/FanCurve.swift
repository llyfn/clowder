// ClowderKit/Sources/ClowderKit/Power/FanCurve.swift
import Foundation
import Observation

public struct CurvePoint: Codable, Equatable, Sendable {
    public var celsius: Double
    public var rpm: Double
    public init(celsius: Double, rpm: Double) {
        self.celsius = celsius; self.rpm = rpm
    }
}

/// Piecewise-linear temperature→RPM mapping over 2–5 points (sorted by temperature).
public struct FanCurve: Codable, Equatable, Sendable {
    public var points: [CurvePoint]

    public init(points: [CurvePoint]) {
        self.points = points.sorted { $0.celsius < $1.celsius }
    }

    public func rpm(at celsius: Double) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if celsius <= first.celsius { return first.rpm }
        if celsius >= last.celsius { return last.rpm }
        for (a, b) in zip(points, points.dropFirst()) where celsius <= b.celsius {
            let fraction = (celsius - a.celsius) / (b.celsius - a.celsius)
            return a.rpm + fraction * (b.rpm - a.rpm)
        }
        return last.rpm
    }
}

/// Evaluates the curve each poll tick with ±3 °C hysteresis so fans don't oscillate.
@Observable @MainActor
public final class FanCurveEngine {
    public var curve: FanCurve
    @ObservationIgnored private var lastEvaluatedTemp: Double?
    private let hysteresis: Double

    public init(curve: FanCurve, hysteresis: Double = 3) {
        self.curve = curve
        self.hysteresis = hysteresis
    }

    /// Returns a new RPM target, or nil when the temperature hasn't moved enough.
    public func evaluate(temp: Double) -> Double? {
        if let last = lastEvaluatedTemp, abs(temp - last) < hysteresis { return nil }
        lastEvaluatedTemp = temp
        return curve.rpm(at: temp)
    }

    /// Forget history (e.g. on mode switch) so the next evaluation always emits.
    public func reset() {
        lastEvaluatedTemp = nil
    }
}
