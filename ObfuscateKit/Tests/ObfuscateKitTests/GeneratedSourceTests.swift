//
/*
 Project: obfuscate
 File: GeneratedSourceTests

 Created by Paul Darcey on 25/9/2026

 © 2025–2026 Xerodonia Pty Ltd. MIT License; see LICENSE.

 ---------------------------------------------------- */

import Foundation
import ObfuscateKit
import Testing

/// Tests for the generated `Secrets.swift` source.
///
/// The command-line tests also compile the generated file and lint it; these check its structure.
@Suite("GeneratedSource")
struct GeneratedSourceTests {
    /// A generated file with one named and one plain secret.
    private static func sampleFile() throws -> (source: String, secrets: [NamedSecret]) {
        let secrets = try SecretList.make(named: ["openAI=sk-sample-secret-value"], plain: ["plain-sample-secret"])
        var properties: [String] = []
        for secret in secrets {
            properties.append(GeneratedSource.property(for: secret, encrypted: try SecretCipher.encrypt(secret.value)))
        }
        return (GeneratedSource.file(properties: properties, propertyNames: secrets.map(\.name)), secrets)
    }

    @Test("The file never contains a secret")
    func noPlaintextSecrets() throws {
        let (source, secrets) = try Self.sampleFile()
        for secret in secrets {
            #expect(!source.contains(secret.value))
        }
    }

    @Test("Each secret becomes a throwing property with alice and bob byte arrays")
    func propertyShape() throws {
        let secret = try NamedSecret(parsing: "openAI=sk-x", position: 1)
        let property = GeneratedSource.property(for: secret, encrypted: try SecretCipher.encrypt(secret.value))
        #expect(property.contains("    static var openAI: String {\n        get throws {"))
        #expect(property.contains("let alice: [UInt8] = ["))
        #expect(property.contains("let bob: [UInt8] = ["))
        #expect(property.contains("return try decrypt(alice, bob)"))
    }

    @Test("Only generated names ask to be renamed")
    func renameComment() throws {
        let generated = NamedSecret(value: "x", number: 1)
        let named = try NamedSecret(parsing: "openAI=x", position: 1)
        let encrypted = try SecretCipher.encrypt("x")
        #expect(GeneratedSource.property(for: generated, encrypted: encrypted).contains("Rename `apiKey1`"))
        #expect(!GeneratedSource.property(for: named, encrypted: encrypted).contains("Rename"))
    }

    @Test("Byte arrays wrap at 12 bytes per line, as two-digit uppercase hex")
    func byteWrapping() throws {
        let secret = NamedSecret(value: String(repeating: "x", count: 40), number: 1)
        let property = GeneratedSource.property(for: secret, encrypted: try SecretCipher.encrypt(secret.value))
        let byteLines = property
            .split(separator: "\n")
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("0x") }
        #expect(!byteLines.isEmpty)
        for line in byteLines {
            let bytes = line
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            #expect(bytes.count <= 12)
            #expect(bytes.allSatisfy { $0.wholeMatch(of: #/0x[0-9A-F]{2}/#) != nil })
        }
    }

    @Test("The #Playground block reads every secret with _ = try")
    func playground() throws {
        let (source, _) = try Self.sampleFile()
        let expected = """
            #Playground("Check API Coding") {
                _ = try Secrets.openAI
                _ = try Secrets.apiKey1
            }
            """
        #expect(source.contains(expected))
        #expect(!source.contains("let check"))
    }

    @Test("No line is longer than 120 characters, and the file ends with one newline")
    func formatting() throws {
        let (source, _) = try Self.sampleFile()
        #expect(source.split(separator: "\n", omittingEmptySubsequences: false).allSatisfy { $0.count <= 120 })
        #expect(source.hasSuffix("}\n"))
        #expect(!source.hasSuffix("\n\n"))
    }

    @Test("The file has no force-try, salt, or lossy String(decoding:)")
    func noUnsafePatterns() throws {
        let (source, _) = try Self.sampleFile()
        #expect(!source.contains("try!"))
        #expect(!source.lowercased().contains("salt"))
        #expect(!source.contains("String(decoding:"))
    }

    @Test("Every member of the generated Secrets enum is a reserved --key name")
    func reservedNamesCoverGeneratedMembers() throws {
        let (source, secrets) = try Self.sampleFile()
        let secretNames = Set(secrets.map(\.name))
        // Members declared at one level of indentation inside `enum Secrets`.
        let members = source.matches(of: #/\n    (?:static )?(?:func|var|let|enum|struct|class) (\w+)/#)
            .map { String($0.output.1) }
            .filter { !secretNames.contains($0) }
        #expect(!members.isEmpty)
        for member in members {
            #expect(NamedSecret.reservedNames.contains(member), "'\(member)' should be a reserved --key name")
        }
    }
}

/// Tests for the byte formatting used in the generated file.
@Suite("UInt8.hexLiteral")
struct HexLiteralTests {
    @Test("Examples", arguments: [(0x00, "0x00"), (0x0F, "0x0F"), (0xA3, "0xA3"), (0xFF, "0xFF")] as [(UInt8, String)])
    func examples(byte: UInt8, expected: String) {
        #expect(byte.hexLiteral == expected)
    }

    @Test("Every byte is two uppercase hex digits and parses back to itself")
    func allBytes() {
        for byte in UInt8.min...UInt8.max {
            let literal = byte.hexLiteral
            #expect(literal.wholeMatch(of: #/0x[0-9A-F]{2}/#) != nil)
            #expect(UInt8(literal.dropFirst(2), radix: 16) == byte)
        }
    }
}
