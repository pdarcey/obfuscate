//
/*
 Project: obfuscate
 File: main

 Created by Paul Darcey on 3/11/2025

 © 2025 Xerodonia Pty Ltd. All rights reserved

 ---------------------------------------------------- */

import Foundation
import ArgumentParser
import CryptoKit

/// CLI command `obfuscate` to create a Swift file you can use in an app that obfuscates the input.
/// Typically, the input is an API secret key.
///
/// The command will print the output to the console or, optionally, to a file in the cwd
///
/// You then have a file that produces a `Secrets` enum, which allows you to retrieve the original API key
/// without having the key anywhere in your source control system. It is also not directly within the `Secrets` file.
///
/// - Note: Each time the command is run, it will produce different output, because it generates a random seed for the
/// encoding/decoding process.
///
/// - Note: This method of obfuscating secrets was based on a blog post at [NSHipster](https://nshipster.com/secrets/)
///
/// - Important: This is **not** high-tech encryption. It's merely obfuscation. If *anyone* wants to crack this, it's
/// trivially easy to do so. It just means they have to be motivated enough to do *some* work, rather than have the
/// keys in plain sight.
@main
struct Obfuscate: ParsableCommand {
    /// Flag to run a check that the output file will decode the input correctly
    @Flag(
        name: .shortAndLong,
        help: "Check every secret decodes correctly before writing any output. Reports pass/fail on stderr."
    )
    var check = false

    /// You can optionally write the output to a file, so you can import it into your app
    @Option(
        name: .shortAndLong,
        help: "Write the generated Swift to this file instead of stdout. [Will add .swift, if necessary]"
    )
    var fileName: String?

    /// Secrets with a chosen property name, each given as `name=secret`
    @Option(
        name: .shortAndLong,
        help: ArgumentHelp(
            "A secret, and the name of the Secrets property that returns it. Repeat for more secrets.",
            valueName: "name=secret"
        )
    )
    var key: [String] = []

    /// The secret you wish to obfuscate. Typically an API key
    @Argument(help: "Secret(s) to obfuscate, separated by spaces. These become Secrets.apiKey1, apiKey2, …")
    var secrets: [String] = []

    mutating func validate() throws {
        _ = try allSecrets()
    }

    /// Every secret to obfuscate: the `--key` secrets first, in order, then the plain ones as `apiKey1`, `apiKey2`, …
    /// - Throws: `ValidationError` if there are no secrets, a `--key` is malformed, or two secrets share a name.
    func allSecrets() throws -> [NamedSecret] {
        let named = try key.enumerated().map { offset, argument in
            try NamedSecret(parsing: argument, position: offset + 1)
        }
        let unnamed = secrets.enumerated().map { offset, value in
            NamedSecret(value: value, number: offset + 1)
        }
        let all = named + unnamed

        guard !all.isEmpty else {
            throw ValidationError("Provide at least one secret, either as an argument or with --key name=secret.")
        }

        var seenNames: Set<String> = []
        for secret in all where !seenNames.insert(secret.name).inserted {
            throw ValidationError("The name '\(secret.name)' is used more than once. Each secret needs its own name.")
        }

        return all
    }

    mutating func run() throws {
        // ArgumentParser only prints an error's `errorDescription`, so print all of an
        // ObfuscateError's messages ourselves.
        do {
            try generate()
        } catch let error as ObfuscateError {
            var standardError = StandardError()
            print("error: \(error.fullMessage)", to: &standardError)
            throw ExitCode.failure
        }
    }

    /// Encrypts every secret, then writes the generated `Secrets.swift` to the file (with `-f`) or stdout.
    ///
    /// The generated Swift goes to the file if one was given, otherwise to stdout. Everything else goes
    /// to stderr. With `--check`, the check runs first, so a failure never leaves output behind.
    ///
    /// - Throws: `ObfuscateError` if encryption fails, or `ExitCode.failure` if the check fails or the
    ///   file can't be written.
    func generate() throws {
        let secrets = try allSecrets()
        var properties: [String] = []
        var checks: [(secret: NamedSecret, encrypted: Encrypted)] = []
        for secret in secrets {
            let encrypted = try encrypt(secret.value)
            properties.append(GeneratedSource.property(for: secret, encrypted: encrypted))
            checks.append((secret, encrypted))
        }
        let outputString = GeneratedSource.file(properties: properties, propertyNames: secrets.map(\.name))

        var standardError = StandardError()

        if check {
            try verifyRoundTrip(checks)
        }

        guard let fileName else {
            // The source already ends with a newline.
            print(outputString, terminator: "")
            return
        }

        let path = fileName.hasSuffix(".swift") ? fileName : fileName + ".swift"
        do {
            try outputString.write(toFile: path, atomically: true, encoding: .utf8)
        } catch {
            print("error: Unable to write to \(path): \(error.localizedDescription)", to: &standardError)
            throw ExitCode.failure
        }
        print("Saved to \(path)", to: &standardError)
    }

    /// Checks that every secret decodes back to its original value, reporting a pass or fail
    /// for each on stderr.
    ///
    /// Only the property names are reported. The secrets and decoded values are never printed,
    /// so they don't end up in terminal scrollback or screen shares.
    ///
    /// - Parameter checks: Each secret, with the encrypted form that the generated file will contain.
    /// - Throws: `ExitCode.failure` if any secret fails to decode correctly.
    func verifyRoundTrip(_ checks: [(secret: NamedSecret, encrypted: Encrypted)]) throws {
        var standardError = StandardError()
        var allPassed = true

        for (secret, encrypted) in checks {
            do {
                if try decrypt(encrypted.content, encrypted.key) == secret.value {
                    print("✅ \(secret.name) decodes correctly", to: &standardError)
                } else {
                    print("❌ \(secret.name) didn't decode to the original secret", to: &standardError)
                    allPassed = false
                }
            } catch {
                let reason = [error.errorDescription, error.failureReason].compactMap { $0 }.joined(separator: " ")
                print("❌ \(secret.name) couldn't be decrypted: \(reason)", to: &standardError)
                allPassed = false
            }
        }

        guard allPassed else {
            print("error: Check failed, so no output was written.", to: &standardError)
            throw ExitCode.failure
        }
    }

    /// Struct to hold encrypted content and the key used to encrypt it
    struct Encrypted {
        let content: [UInt8]
        let key: [UInt8]
    }

    /// Encrypts clearText using the ChaChaPoly algorithm, with a new random key.
    /// - Parameter clearText: Any text to encrypt
    /// - Returns: An ``Encrypted`` struct, containing the encrypted text plus the key used to encrypt it
    /// - Throws: ``ObfuscateError/encryptionFailed(underlying:)`` if CryptoKit can't encrypt it.
    func encrypt(_ clearText: String) throws(ObfuscateError) -> Encrypted {
        let key = SymmetricKey(size: .bits256)
        let keyBytes = key.withUnsafeBytes { [UInt8]($0) }
        do {
            let sealedBox = try ChaChaPoly.seal(Data(clearText.utf8), using: key)
            return Encrypted(content: [UInt8](sealedBox.combined), key: keyBytes)
        } catch {
            throw ObfuscateError.encryptionFailed(underlying: error)
        }
    }

    /// Decrypts some bytes and returns the clear text.
    /// - Parameters:
    ///   - content: The encrypted content to be decrypted
    ///   - key: The key to use to decrypt it
    /// - Returns: The decrypted string
    /// - Throws: ``ObfuscateError/decryptionFailed(underlying:)`` if CryptoKit can't decrypt it, or
    ///   ``ObfuscateError/invalidUTF8`` if the result isn't valid UTF-8.
    func decrypt(_ content: [UInt8], _ key: [UInt8]) throws(ObfuscateError) -> String {
        let decrypted: Data
        do {
            let sealedBox = try ChaChaPoly.SealedBox(combined: Data(content))
            decrypted = try ChaChaPoly.open(sealedBox, using: SymmetricKey(data: Data(key)))
        } catch {
            throw ObfuscateError.decryptionFailed(underlying: error)
        }

        guard let clearText = String(bytes: decrypted, encoding: .utf8) else {
            throw ObfuscateError.invalidUTF8
        }
        return clearText
    }
}
