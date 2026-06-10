import Testing
@testable import ClowderKit

struct SMCTests {
    @Test func keyCodecRoundTrips() {
        let key = SMCKey("Tp01")
        #expect(key.code == 0x54703031)
        #expect(key.string == "Tp01")
        #expect(SMCKey(code: 0x464E756D).string == "FNum")
    }

    @Test func decodesFlt() {
        // 48.5 as little-endian IEEE-754 float
        let bytes: [UInt8] = [0x00, 0x00, 0x42, 0x42]
        #expect(SMCValueDecoder.decode(type: "flt ", bytes: bytes) == 48.5)
    }

    @Test func decodesFpe2() {
        // fpe2: big-endian UInt16, value = raw / 4. 0x1234 = 4660 / 4 = 1165
        #expect(SMCValueDecoder.decode(type: "fpe2", bytes: [0x12, 0x34]) == 1165)
    }

    @Test func decodesSp78() {
        // sp78: big-endian Int16, value = raw / 256. 0x3080 = 12416 / 256 = 48.5
        #expect(SMCValueDecoder.decode(type: "sp78", bytes: [0x30, 0x80]) == 48.5)
    }

    @Test func decodesUnsignedInts() {
        #expect(SMCValueDecoder.decode(type: "ui8 ", bytes: [3]) == 3)
        #expect(SMCValueDecoder.decode(type: "ui16", bytes: [0x01, 0x00]) == 256)
        #expect(SMCValueDecoder.decode(type: "ui32", bytes: [0, 0, 1, 0]) == 256)
    }

    @Test func unknownTypeYieldsNil() {
        #expect(SMCValueDecoder.decode(type: "ch8*", bytes: [65]) == nil)
    }

    @Test func tempKeyFilterKeepsPlausibleCPUSensors() {
        #expect(TempsFansSource.isCPUTempKey("Tp01", celsius: 48))
        #expect(TempsFansSource.isCPUTempKey("Tg0D", celsius: 52))   // GPU group included
        #expect(!TempsFansSource.isCPUTempKey("Ts0P", celsius: 30))  // other sensor groups excluded
        #expect(!TempsFansSource.isCPUTempKey("Tp01", celsius: 0))   // implausible readings dropped
        #expect(!TempsFansSource.isCPUTempKey("Tp01", celsius: 130))
    }
}
