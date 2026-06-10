import Foundation

/// Display formatting. Decimal (1000-based) units, matching Activity Monitor.
public enum Format {
    private static func scaled(_ value: Double) -> (Double, String) {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = value
        var i = 0
        while v >= 1000, i < units.count - 1 { v /= 1000; i += 1 }
        return (v, units[i])
    }

    private static func trim(_ v: Double) -> String {
        v >= 100 || v == v.rounded() ? String(Int(v.rounded())) : String(format: "%.1f", v)
    }

    public static func byteRate(_ bytesPerSec: Double) -> String {
        let (v, unit) = scaled(max(bytesPerSec, 0))
        return "\(trim(v)) \(unit)/s"
    }

    public static func bytes(_ bytes: UInt64) -> String {
        let (v, unit) = scaled(Double(bytes))
        return "\(trim(v)) \(unit)"
    }

    public static func temp(_ celsius: Double) -> String {
        "\(Int(celsius.rounded()))°"
    }

    public static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }
}
