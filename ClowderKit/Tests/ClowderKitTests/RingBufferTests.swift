import Testing
@testable import ClowderKit

struct RingBufferTests {
    @Test func appendsUpToCapacity() {
        var b = RingBuffer<Int>(capacity: 3)
        b.append(1); b.append(2); b.append(3)
        #expect(b.elements == [1, 2, 3])
    }

    @Test func dropsOldestBeyondCapacity() {
        var b = RingBuffer<Int>(capacity: 3)
        for n in 1...5 { b.append(n) }
        #expect(b.elements == [3, 4, 5])
    }

    @Test func capacityOfZeroKeepsNothing() {
        var b = RingBuffer<Int>(capacity: 0)
        b.append(1)
        #expect(b.elements.isEmpty)
    }
}
