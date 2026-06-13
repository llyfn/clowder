import Testing

@testable import ClowderKit

@Test func packageBuilds() {
    #expect(ClowderKitInfo.version == "0.1.0")
}
