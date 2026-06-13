import HelperProtocol
import Testing

struct ProtocolTests {
    @Test func constantsAreStable() {
        // These strings are an ABI between app and helper — pin them.
        #expect(HelperConstants.machServiceName == "dev.clowder.ClowderHelper.xpc")
        #expect(HelperConstants.daemonPlistName == "dev.clowder.ClowderHelper.plist")
        #expect(HelperConstants.version == 1)
        #expect(HelperConstants.chargeLimitRange == 50...100)
    }
}
