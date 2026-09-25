//
/*
 Project: obfuscate
 File: SecretCipher

 Created by Paul Darcey on 25/9/2026

 © 2025–2026 Xerodonia Pty Ltd. MIT License; see LICENSE.

 ---------------------------------------------------- */

import CryptoKit
import Foundation

/// Encrypts and decrypts secrets with ChaCha20-Poly1305, using a new random key for each secret.
///
/// ``decrypt(_:)`` mirrors the `decrypt` function in the generated file, so the tool can check a
/// secret round-trips before writing any output.
public enum SecretCipher {
    /// Encrypts a secret with a new random 256-bit key.
    /// - Parameter clearText: The secret to encrypt.
    /// - Returns: The sealed box and the key that decrypts it.
    /// - Throws: ``ObfuscateError/encryptionFailed(underlying:)`` if CryptoKit can't encrypt it.
    public static func encrypt(_ clearText: String) throws(ObfuscateError) -> EncryptedSecret {
        let key = SymmetricKey(size: .bits256)
        let keyBytes = key.withUnsafeBytes { [UInt8]($0) }
        do {
            let sealedBox = try ChaChaPoly.seal(Data(clearText.utf8), using: key)
            return EncryptedSecret(content: [UInt8](sealedBox.combined), key: keyBytes)
        } catch {
            throw .encryptionFailed(underlying: error)
        }
    }

    /// Decrypts a secret and returns the clear text.
    /// - Parameter encrypted: The sealed box and its key.
    /// - Returns: The decrypted secret.
    /// - Throws: ``ObfuscateError/decryptionFailed(underlying:)`` if CryptoKit can't decrypt it (for
    ///   example, because a byte has changed), or ``ObfuscateError/invalidUTF8`` if the result isn't
    ///   valid UTF-8.
    public static func decrypt(_ encrypted: EncryptedSecret) throws(ObfuscateError) -> String {
        let decrypted: Data
        do {
            let sealedBox = try ChaChaPoly.SealedBox(combined: Data(encrypted.content))
            decrypted = try ChaChaPoly.open(sealedBox, using: SymmetricKey(data: Data(encrypted.key)))
        } catch {
            throw .decryptionFailed(underlying: error)
        }

        guard let clearText = String(bytes: decrypted, encoding: .utf8) else {
            throw .invalidUTF8
        }
        return clearText
    }
}
