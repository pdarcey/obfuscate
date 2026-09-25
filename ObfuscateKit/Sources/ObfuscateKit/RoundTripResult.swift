//
/*
 Project: obfuscate
 File: RoundTripResult

 Created by Paul Darcey on 25/9/2026

 © 2025–2026 Xerodonia Pty Ltd. MIT License; see LICENSE.

 ---------------------------------------------------- */

/// The result of checking that one secret decrypts back to its original value (`--check`).
///
/// - Important: ``report`` names the secret's property but never includes the secret or the
///   decrypted value, so it can safely be printed to a terminal.
public struct RoundTripResult: Sendable {
    /// How the check went.
    public enum Outcome: Sendable {
        /// The secret decrypted to its original value.
        case passed

        /// The secret decrypted, but to a different value.
        case mismatch

        /// The secret couldn't be decrypted.
        case failed(ObfuscateError)
    }

    /// The name of the secret's `Secrets` property.
    public let name: String

    /// How the check went.
    public let outcome: Outcome

    /// Checks that `encrypted` decrypts back to `secret`'s value.
    /// - Parameters:
    ///   - secret: The secret, with its property name and original value.
    ///   - encrypted: The encrypted form that the generated file will contain.
    public init(checking secret: NamedSecret, encrypted: EncryptedSecret) {
        self.name = secret.name
        do {
            let decrypted = try SecretCipher.decrypt(encrypted)
            self.outcome = decrypted == secret.value ? .passed : .mismatch
        } catch {
            self.outcome = .failed(error)
        }
    }

    /// Whether the secret decrypted to its original value.
    public var passed: Bool {
        if case .passed = outcome {
            return true
        }
        return false
    }

    /// A one-line report for stderr, e.g. `✅ openAI decodes correctly`.
    public var report: String {
        switch outcome {
        case .passed:
            "✅ \(name) decodes correctly"
        case .mismatch:
            "❌ \(name) didn't decode to the original secret"
        case .failed(let error):
            "❌ \(name) couldn't be decrypted: "
            + [error.errorDescription, error.failureReason].compactMap { $0 }.joined(separator: " ")
        }
    }
}
