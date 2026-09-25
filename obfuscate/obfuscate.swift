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
/// trivially easy to do so. It just means they have to be motivated enough to do *some* work, rather than have the keys in plain sight.
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
    var fileName: String? = nil

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
        // Set up random salt
        let salt = SymmetricKey(size: .bits256)
        let saltData = salt.withUnsafeBytes { Data(Array($0)) }
        let saltBytes = [UInt8](saltData)
        let saltString = saltBytes.map(\.hexLiteral).joined(separator: ", ")

        var keys: [String] = []
        var playgrounds = ""
        var index = 1
        var checks: [(secret: NamedSecret, encrypted: Encrypted)] = []
        for secret in try allSecrets() {
            let encrypted = encrypt(secret.value)
            let aByteString = encrypted.content.map(\.hexLiteral).joined(separator: ", ")
            let bByteString = encrypted.key.map(\.hexLiteral).joined(separator: ", ")

            // Never include the secret itself in the output, not even in a comment:
            // the generated file is meant to be committed to source control.
            let docComment = if secret.hasGeneratedName {
                """
                    /// Obfuscated secret.
                    ///
                    /// Rename `\(secret.name)` (here and in the `#Playground` below) to describe what it's for.
                """
            } else {
                "    /// Obfuscated secret `\(secret.name)`."
            }
            let key = """
            \(docComment)
                static var \(secret.name): String {
                    let a: [UInt8] = [
                        \(aByteString)
                    ]

                    let b: [UInt8] = [
                        \(bByteString)
                    ]

                    return decrypt(a, b)
                }
            """
            keys.append(key)

            let playground = "let check\(index) = Secrets.\(secret.name)\n"
            playgrounds += playground
            index += 1
            checks.append((secret, encrypted))
        }
        // Generate and print a Swift file to decode the API
        let outputString = """
        import Foundation
        import CryptoKit
        import Playgrounds
        
        // Secrets.swift
        
        /// `Secrets` lets us obfuscate secrets, such as API keys, without committing the actual keys to source control
        ///
        /// This enum was generated by the in-house CLI tool `obfuscate`, and should not be altered. See `obfuscate -h` for more info on the tool
        ///
        /// - Note: This method of obfuscating secrets was based on a blog post at [NSHipster](https://nshipster.com/secrets/)
        ///
        /// - Important: This is **not** high-tech encryption. It's merely obfuscation. If *anyone* wants to crack this, it's trivially easy to do so. It just means they have to be motivated enough to do *some* work, rather than have the keys in plain sight.
        enum Secrets {
            private static let salt: [UInt8] = [
                \(saltString)
            ]

        \(keys.joined(separator: "\n\n"))

            /// Decrypt some bytes and return the clear text
            /// - Parameters:
            ///   - content: The encrypted content to be decrypted
            ///   - key: The key to use to decrypt it
            /// - Returns: The unencrypted string
            static func decrypt(_ content: [UInt8], _ key: [UInt8]) -> String {
                let encryptedContent = Data(content)
                let keyData = Data(key)
                let key = SymmetricKey(data: keyData)
                let sealedBox = try! ChaChaPoly.SealedBox(combined: encryptedContent)
                let unencryptedData = try! ChaChaPoly.open(sealedBox, using: key)
            return String(decoding: unencryptedData, as: UTF8.self)
            }
        }
        
        #Playground("Check API Coding") {
        \(playgrounds)
        }
        """
        // The generated Swift goes to the file if one was given, otherwise to stdout.
        // Everything else goes to stderr. Check first, so a failure never leaves output behind.
        var standardError = StandardError()

        if check {
            try verifyRoundTrip(checks)
        }

        guard let fileName else {
            print(outputString)
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
            if decrypt(encrypted.content, encrypted.key) == secret.value {
                print("✅ \(secret.name) decodes correctly", to: &standardError)
            } else {
                print("❌ \(secret.name) didn't decode to the original secret", to: &standardError)
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

    /// Encrypts clearText using the ChaChaPoly algorithm
    /// - Parameter clearText: Any text to encrypt
    /// - Returns: An ``Encrypted`` struct, containing the encrypted text plus the key used to encrypt it
    func encrypt(_ clearText: String) -> Encrypted {
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data(Array($0)) }
        let keyBytes = [UInt8](keyData)
        let data = Data(clearText.utf8)
        let encryptedContent = try! ChaChaPoly.seal(data, using: key).combined
        let encryptedBytes = [UInt8](encryptedContent)
        // Output keyBytes, encryptedBytes
        return Encrypted(content: encryptedBytes, key: keyBytes)
    }

    /// Decrypt some bytes and return the clear text
    /// - Parameters:
    ///   - content: The encrypted content to be decrypted
    ///   - key: The key to use to decrypt it
    /// - Returns: The unencrypted string
    func decrypt(_ content: [UInt8], _ key: [UInt8]) -> String {
        let encryptedContent = Data(content)
        let keyData = Data(key)
        let key = SymmetricKey(data: keyData)
        let sealedBox = try! ChaChaPoly.SealedBox(combined: encryptedContent)
        let unencryptedData = try! ChaChaPoly.open(sealedBox, using: key)
        return String(decoding: unencryptedData, as: UTF8.self)
    }
}
