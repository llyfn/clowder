import Foundation
import IOKit

public struct SMCKey: Equatable, Hashable, Sendable {
    public let code: UInt32

    public init(_ string: String) {
        precondition(string.utf8.count == 4, "SMC keys are exactly 4 ASCII chars")
        self.code = string.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    public init(code: UInt32) { self.code = code }

    public var string: String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }
}

public enum SMCValueDecoder {
    /// Decodes an SMC value to a Double. Returns nil for unsupported types.
    public static func decode(type: String, bytes: [UInt8]) -> Double? {
        switch type {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let raw = bytes[0..<4].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            return Double(Float(bitPattern: UInt32(littleEndian: raw)))
        case "fpe2":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case "sp78":
            guard bytes.count >= 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        case "ui8 ":
            guard bytes.count >= 1 else { return nil }
            return Double(bytes[0])
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            return Double(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16
                          | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
        default:
            return nil
        }
    }
}

public struct SMCKeyInfo: Equatable, Sendable {
    public var dataSize: UInt32
    public var dataType: String
    public init(dataSize: UInt32, dataType: String) {
        self.dataSize = dataSize; self.dataType = dataType
    }
}

public protocol SMCConnecting: Sendable {
    func keyCount() throws -> Int
    func key(atIndex index: Int) throws -> SMCKey
    func keyInfo(_ key: SMCKey) throws -> SMCKeyInfo
    func readBytes(_ key: SMCKey, info: SMCKeyInfo) throws -> [UInt8]
}

public extension SMCConnecting {
    /// Read a key and decode it, or nil if the key/type is unsupported.
    func readValue(_ key: SMCKey) -> Double? {
        guard let info = try? keyInfo(key), info.dataSize > 0,
              let bytes = try? readBytes(key, info: info) else { return nil }
        return SMCValueDecoder.decode(type: info.dataType, bytes: bytes)
    }
}

// MARK: - IOKit implementation

/// Wire struct for the AppleSMC user client (selector 2). Field layout must match the C ABI exactly (80 bytes).
/// KeyInfoData is 12 bytes in C (3 bytes of implicit padding after dataAttributes) — we replicate that explicitly.
struct SMCParamStruct {
    struct Version { var major: UInt8 = 0; var minor: UInt8 = 0; var build: UInt8 = 0
                     var reserved: UInt8 = 0; var release: UInt16 = 0 }
    struct PLimitData { var version: UInt16 = 0; var length: UInt16 = 0
                        var cpuPLimit: UInt32 = 0; var gpuPLimit: UInt32 = 0; var memPLimit: UInt32 = 0 }
    struct KeyInfoData { var dataSize: UInt32 = 0; var dataType: UInt32 = 0; var dataAttributes: UInt8 = 0
                         var _pad: (UInt8, UInt8, UInt8) = (0, 0, 0) }  // matches C padding to UInt32 alignment

    var key: UInt32 = 0
    var vers = Version()
    var pLimitData = PLimitData()
    var keyInfo = KeyInfoData()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var _pad: UInt8 = 0                                                  // C pads here before UInt32 data32
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

public final class SMCClient: SMCConnecting, @unchecked Sendable {
    private enum Selector: UInt8 {
        case readKey = 5, writeKey = 6, keyAtIndex = 8, keyInfo = 9
    }

    private let connection: io_connect_t
    private let lock = NSLock()

    public init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SensorError.unavailable("AppleSMC service") }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == kIOReturnSuccess else {
            throw SensorError.unavailable("AppleSMC open")
        }
        self.connection = conn
    }

    deinit { IOServiceClose(connection) }

    private func call(_ input: SMCParamStruct) throws -> SMCParamStruct {
        lock.lock()
        defer { lock.unlock() }
        var input = input
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride
        let rc = IOConnectCallStructMethod(connection, 2, &input,
                                           MemoryLayout<SMCParamStruct>.stride,
                                           &output, &outputSize)
        guard rc == kIOReturnSuccess, output.result == 0 else {
            throw SensorError.readFailed("SMC call rc=\(rc) result=\(output.result)")
        }
        return output
    }

    public func keyCount() throws -> Int {
        let info = try keyInfo(SMCKey("#KEY"))
        let bytes = try readBytes(SMCKey("#KEY"), info: info)
        guard let count = SMCValueDecoder.decode(type: "ui32", bytes: bytes) else {
            throw SensorError.readFailed("#KEY decode")
        }
        return Int(count)
    }

    public func key(atIndex index: Int) throws -> SMCKey {
        var input = SMCParamStruct()
        input.data8 = Selector.keyAtIndex.rawValue
        input.data32 = UInt32(index)
        let output = try call(input)
        return SMCKey(code: output.key)
    }

    public func keyInfo(_ key: SMCKey) throws -> SMCKeyInfo {
        var input = SMCParamStruct()
        input.key = key.code
        input.data8 = Selector.keyInfo.rawValue
        let output = try call(input)
        return SMCKeyInfo(dataSize: output.keyInfo.dataSize,
                          dataType: SMCKey(code: output.keyInfo.dataType).string)
    }

    public func readBytes(_ key: SMCKey, info: SMCKeyInfo) throws -> [UInt8] {
        var input = SMCParamStruct()
        input.key = key.code
        input.keyInfo.dataSize = info.dataSize
        input.data8 = Selector.readKey.rawValue
        let output = try call(input)
        return withUnsafeBytes(of: output.bytes) { Array($0.prefix(Int(info.dataSize))) }
    }
}
