import Foundation
import Security

enum ConnectionValidator {
    /// Accept only processes whose code signature satisfies our requirement.
    /// Dev builds are ad-hoc signed (no team ID), so the requirement is identifier-only.
    /// TODO(Plan 3): anchor to the Developer ID team for release builds.
    static func isValid(_ connection: NSXPCConnection) -> Bool {
        let pid = connection.processIdentifier
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: pid] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
            let code
        else { return false }
        var requirement: SecRequirement?
        guard
            SecRequirementCreateWithString(
                "identifier \"dev.clowder.Clowder\"" as CFString, [], &requirement)
                == errSecSuccess,
            let requirement
        else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}
