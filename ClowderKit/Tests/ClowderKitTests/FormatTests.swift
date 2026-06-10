import Testing
@testable import ClowderKit

struct FormatTests {
    @Test func byteRates() {
        #expect(Format.byteRate(0) == "0 B/s")
        #expect(Format.byteRate(512) == "512 B/s")
        #expect(Format.byteRate(340_000) == "340 KB/s")
        #expect(Format.byteRate(2_140_000) == "2.1 MB/s")
        #expect(Format.byteRate(1_280_000_000) == "1.3 GB/s")
    }

    @Test func bytes() {
        #expect(Format.bytes(0) == "0 B")
        #expect(Format.bytes(18_200_000_000) == "18.2 GB")
        #expect(Format.bytes(412_000_000_000) == "412 GB")
        #expect(Format.bytes(1_500_000_000_000) == "1.5 TB")
    }

    @Test func tempAndPercent() {
        #expect(Format.temp(48.3) == "48°")
        #expect(Format.percent(0.382) == "38%")
        #expect(Format.percent(1.0) == "100%")
    }
}
