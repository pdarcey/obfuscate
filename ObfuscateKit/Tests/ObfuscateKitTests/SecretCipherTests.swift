//
/*
 Project: obfuscate
 File: SecretCipherTests

 Created by Paul Darcey on 25/9/2026

 © 2025–2026 Xerodonia Pty Ltd. MIT License; see LICENSE.

 ---------------------------------------------------- */

import CryptoKit
import Foundation
import ObfuscateKit
import Testing

/// Tests for encryption, decryption, and the round-trip check behind `--check`.
@Suite("SecretCipher")
struct SecretCipherTests {
    @Test("Secrets round-trip", arguments: [
        "sk-live-4f9a2b7c1d3e5f60",
        "QWxhZGRpbjpvcGVuIHNlc2FtZQ==",
        "has spaces in the middle",
        "ünïcødé-🔑-sécret",
        "quote\"and\\backslash",
        ""
    ])
    func roundTrip(secret: String) throws {
        let encrypted = try SecretCipher.encrypt(secret)
        #expect(try SecretCipher.decrypt(encrypted) == secret)
    }

    @Test("The key is 256 bits, and the content is nonce + ciphertext + tag")
    func sizes() throws {
        let secret = "twelve bytes"
        let encrypted = try SecretCipher.encrypt(secret)
        #expect(encrypted.key.count == 32)
        #expect(encrypted.content.count == 12 + secret.utf8.count + 16)
    }

    @Test("Each encryption uses a new random key")
    func randomKeys() throws {
        let first = try SecretCipher.encrypt("same secret")
        let second = try SecretCipher.encrypt("same secret")
        #expect(first.key != second.key)
        #expect(first.content != second.content)
    }

    @Test("Changing any byte makes decryption fail", arguments: [0, 12, 20])
    func tampered(index: Int) throws {
        let encrypted = try SecretCipher.encrypt("tamper with me")
        var content = encrypted.content
        content[index] ^= 0x01

        let error = #expect(throws: ObfuscateError.self) {
            try SecretCipher.decrypt(EncryptedSecret(content: content, key: encrypted.key))
        }
        guard case .decryptionFailed = error else {
            Issue.record("Expected decryptionFailed, got \(String(describing: error))")
            return
        }
    }

    @Test("The wrong key makes decryption fail")
    func wrongKey() throws {
        let encrypted = try SecretCipher.encrypt("secret")
        let other = try SecretCipher.encrypt("secret")
        let error = #expect(throws: ObfuscateError.self) {
            try SecretCipher.decrypt(EncryptedSecret(content: encrypted.content, key: other.key))
        }
        guard case .decryptionFailed = error else {
            Issue.record("Expected decryptionFailed, got \(String(describing: error))")
            return
        }
    }

    @Test("Bytes that aren't UTF-8 are reported as invalidUTF8")
    func invalidUTF8() throws {
        let key = SymmetricKey(size: .bits256)
        let sealed = try ChaChaPoly.seal(Data([0xFF, 0xFE, 0xFD]), using: key)
        let encrypted = EncryptedSecret(content: [UInt8](sealed.combined), key: key.withUnsafeBytes { [UInt8]($0) })

        let error = #expect(throws: ObfuscateError.self) {
            try SecretCipher.decrypt(encrypted)
        }
        guard case .invalidUTF8 = error else {
            Issue.record("Expected invalidUTF8, got \(String(describing: error))")
            return
        }
    }
}

/// Tests for `--check`, including the failure paths the command-line tests can't reach.
@Suite("RoundTripResult")
struct RoundTripResultTests {
    @Test("A correct secret passes")
    func passes() throws {
        let secret = NamedSecret(value: "sk-good", number: 1)
        let result = RoundTripResult(checking: secret, encrypted: try SecretCipher.encrypt(secret.value))
        #expect(result.passed)
        #expect(result.report == "✅ apiKey1 decodes correctly")
    }

    @Test("A secret that decrypts to a different value fails as a mismatch")
    func mismatch() throws {
        let secret = try NamedSecret(parsing: "openAI=sk-expected", position: 1)
        let result = RoundTripResult(checking: secret, encrypted: try SecretCipher.encrypt("sk-something-else"))
        #expect(!result.passed)
        #expect(result.report == "❌ openAI didn't decode to the original secret")
        guard case .mismatch = result.outcome else {
            Issue.record("Expected mismatch, got \(result.outcome)")
            return
        }
    }

    @Test("A secret that can't be decrypted fails, with the reason")
    func failed() throws {
        let secret = NamedSecret(value: "sk-corrupted", number: 1)
        let encrypted = try SecretCipher.encrypt(secret.value)
        var content = encrypted.content
        content[0] ^= 0x01

        let result = RoundTripResult(checking: secret, encrypted: EncryptedSecret(content: content, key: encrypted.key))
        #expect(!result.passed)
        let expectedPrefix = "❌ apiKey1 couldn't be decrypted: Couldn't decrypt a secret. CryptoKit reported: "
        #expect(result.report.hasPrefix(expectedPrefix))
        guard case .failed(.decryptionFailed) = result.outcome else {
            Issue.record("Expected failed(decryptionFailed), got \(result.outcome)")
            return
        }
    }

    @Test("Reports never include the secret or the decrypted value")
    func reportsNeverIncludeSecrets() throws {
        let secret = NamedSecret(value: "sk-never-print-me", number: 1)
        let passing = RoundTripResult(checking: secret, encrypted: try SecretCipher.encrypt(secret.value))
        let mismatched = RoundTripResult(checking: secret, encrypted: try SecretCipher.encrypt("sk-other-value"))
        for result in [passing, mismatched] {
            #expect(!result.report.contains("sk-never-print-me"))
            #expect(!result.report.contains("sk-other-value"))
        }
    }
}

/// Tests for the tool's error messages.
@Suite("ObfuscateError")
struct ObfuscateErrorTests {
    struct Underlying: Error, LocalizedError {
        var errorDescription: String? { "the underlying reason" }
    }

    @Test("All four LocalizedError properties", arguments: [
        ObfuscateError.encryptionFailed(underlying: Underlying()),
        ObfuscateError.decryptionFailed(underlying: Underlying()),
        ObfuscateError.invalidUTF8
    ])
    func localizedErrorProperties(error: ObfuscateError) {
        #expect(error.errorDescription?.isEmpty == false)
        #expect(error.failureReason?.isEmpty == false)
        #expect(error.recoverySuggestion?.contains("This should never happen") == true)
        #expect(error.helpAnchor == nil)
    }

    @Test("The failure reason includes CryptoKit's own message")
    func underlyingReason() {
        let error = ObfuscateError.decryptionFailed(underlying: Underlying())
        #expect(error.failureReason == "CryptoKit reported: the underlying reason")
    }

    @Test("fullMessage is the description, reason and suggestion, one per line")
    func fullMessage() {
        let error = ObfuscateError.invalidUTF8
        #expect(error.fullMessage.split(separator: "\n").map(String.init)
                == [error.errorDescription, error.failureReason, error.recoverySuggestion].compactMap { $0 })
    }
}
