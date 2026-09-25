//
/*
 Project: obfuscate
 File: EncryptedSecret

 Created by Paul Darcey on 25/9/2026

 © 2025–2026 Xerodonia Pty Ltd. MIT License; see LICENSE.

 ---------------------------------------------------- */

/// A secret encrypted by ``SecretCipher``, as the two byte arrays written into the generated file.
public struct EncryptedSecret: Equatable, Sendable {
    /// The ChaCha20-Poly1305 sealed box in its combined form: a 12-byte nonce, the ciphertext,
    /// and a 16-byte authentication tag. Written as `alice` in the generated file.
    public let content: [UInt8]

    /// The 256-bit key that decrypts ``content``. Written as `bob` in the generated file.
    public let key: [UInt8]

    /// Creates an encrypted secret from its two byte arrays.
    /// - Parameters:
    ///   - content: The combined sealed box (nonce, ciphertext and tag).
    ///   - key: The 256-bit key that decrypts it.
    public init(content: [UInt8], key: [UInt8]) {
        self.content = content
        self.key = key
    }
}
