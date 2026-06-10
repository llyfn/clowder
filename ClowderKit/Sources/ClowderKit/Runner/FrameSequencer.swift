import Foundation

public struct FrameSequencer: Sendable {
    public let frameCount: Int
    public private(set) var index: Int = 0

    public init(frameCount: Int) {
        self.frameCount = max(frameCount, 1)
    }

    public mutating func advance() {
        index = (index + 1) % frameCount
    }

    /// Maps CPU load (0...1) to seconds-per-frame, linearly from slowest to fastest.
    public static func interval(forLoad load: Double,
                                slowest: TimeInterval = 0.45,
                                fastest: TimeInterval = 0.06) -> TimeInterval {
        let clamped = min(max(load, 0), 1)
        return slowest + (fastest - slowest) * clamped
    }
}
