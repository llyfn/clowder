import Foundation

/// Fixed-capacity FIFO. Appending past capacity drops the oldest elements.
public struct RingBuffer<Element>: Sendable where Element: Sendable {
    public private(set) var elements: [Element] = []
    public let capacity: Int

    public init(capacity: Int) { self.capacity = max(0, capacity) }

    public mutating func append(_ element: Element) {
        guard capacity > 0 else { return }
        elements.append(element)
        if elements.count > capacity { elements.removeFirst(elements.count - capacity) }
    }
}

/// One battery-level reading for the 12-hour history chart.
public struct BatteryPoint: Equatable, Sendable, Identifiable {
    public let date: Date
    public let level: Int
    public var id: Date { date }
    public init(date: Date, level: Int) {
        self.date = date
        self.level = level
    }
}
