//
/*
 Project: obfuscate
 File: UInt8+HexLiteral

 Created by Paul Darcey on 25/9/2026

 © 2025–2026 Xerodonia Pty Ltd. MIT License; see LICENSE.

 ---------------------------------------------------- */

extension UInt8 {
    /// The byte as a Swift hexadecimal literal, always two uppercase digits: `0x0F`, `0xA3`.
    var hexLiteral: String {
        let digits = String(self, radix: 16, uppercase: true)
        return digits.count == 1 ? "0x0\(digits)" : "0x\(digits)"
    }
}
