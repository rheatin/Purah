// Tests/PurahCoreTests/ClipboardTextFormatterTests.swift
import Foundation
import Testing
@testable import PurahCore

@Suite("Clipboard Text Formatter")
struct ClipboardTextFormatterTests {

    private func output(_ action: ClipboardTextFormatter.Action, _ text: String) -> String? {
        ClipboardTextFormatter.output(of: action, for: text)
    }

    @Test("A plain sentence offers no JSON or Base64 decode")
    func testPlainTextMenu() {
        let actions = ClipboardTextFormatter.availableActions(for: "just some words I copied")
        #expect(!actions.contains(.prettyJSON))
        #expect(!actions.contains(.decodeBase64))
        #expect(actions.contains(.encodeBase64))
        #expect(actions.contains(.encodePercent))
    }

    /// The glyph that opens the menu is shown on the strength of the *detected*
    /// list. Keying it off the full list put it on every card, because
    /// "Encode as Base64" applies to any string.
    @Test("Only detected conversions light up the affordance")
    func testDetectedActions() {
        #expect(ClipboardTextFormatter.detectedActions(for: "just some words I copied").isEmpty)
        #expect(!ClipboardTextFormatter.detectedActions(for: #"{"a":1}"#).isEmpty)
        #expect(!ClipboardTextFormatter.detectedActions(for: "SGVsbG8sIFB1cmFo").isEmpty)
        #expect(!ClipboardTextFormatter.detectedActions(for: "a%20b%2Fc").isEmpty)
    }

    @Test("JSON offers both directions of whitespace and a YAML/TOML target")
    func testJSONMenu() {
        let actions = ClipboardTextFormatter.availableActions(for: #"{"name":"purah"}"#)
        #expect(actions.contains(.prettyJSON))
        #expect(actions.contains(.minifyJSON))
        #expect(actions.contains(.asYAML))
        #expect(actions.contains(.asTOML))
    }

    @Test("Prettifying sorts keys and keeps the values")
    func testPrettyJSON() throws {
        let pretty = try #require(output(.prettyJSON, #"{"b":2,"a":{"c":[1,true]}}"#))
        #expect(pretty.contains("\n"))
        #expect(pretty.contains("\"a\""))
        #expect(pretty.contains("\"c\""))
        let firstKey = try #require(pretty.range(of: "\"a\""))
        let secondKey = try #require(pretty.range(of: "\"b\""))
        #expect(firstKey.lowerBound < secondKey.lowerBound)
        // Round-trips: the pretty form is still valid JSON.
        #expect(output(.minifyJSON, pretty) == #"{"a":{"c":[1,true]},"b":2}"#)
    }

    @Test("Invalid JSON produces nothing rather than a half-formatted blob")
    func testInvalidJSON() {
        #expect(output(.prettyJSON, #"{"a":}"#) == nil)
        #expect(output(.asYAML, "not json") == nil)
        #expect(output(.asTOML, "not json") == nil)
    }

    @Test("Base64 decodes text and refuses binary")
    func testBase64() throws {
        let encoded = try #require(output(.encodeBase64, "Hello, Purah"))
        #expect(encoded == "SGVsbG8sIFB1cmFo")
        #expect(output(.decodeBase64, encoded) == "Hello, Purah")

        // A word that happens to sit in the alphabet is not base64.
        #expect(!ClipboardTextFormatter.availableActions(for: "abcdefgh").contains(.decodeBase64))
    }

    @Test("URL coding goes both ways and only decodes when there is something to decode")
    func testPercentCoding() throws {
        let decoded = try #require(output(.decodePercent, "a%20b%2Fc"))
        #expect(decoded == "a b/c")
        #expect(output(.encodePercent, "a b") == "a%20b")
        #expect(!ClipboardTextFormatter.availableActions(for: "no coding here").contains(.decodePercent))
    }

    @Test("YAML emits nested blocks the way a config file reads")
    func testYAML() throws {
        let yaml = try #require(output(
            .asYAML,
            #"{"name":"purah","on":true,"empty":null,"tags":["a","b"],"server":{"port":8080}}"#
        ))
        // `on` is quoted because unquoted it is a boolean in YAML 1.1.
        #expect(yaml == """
            empty: null
            name: purah
            'on': true
            server:
              port: 8080
            tags:
              - a
              - b

            """)
    }

    @Test("Strings that would read as another YAML type are quoted")
    func testYAMLQuoting() throws {
        let yaml = try #require(output(.asYAML, #"{"a":"yes","b":"1.0","c":"plain"}"#))
        #expect(yaml.contains("a: 'yes'"))
        #expect(yaml.contains("b: '1.0'"))
        #expect(yaml.contains("c: plain"))
    }

    @Test("TOML quotes strings and nests tables")
    func testTOML() throws {
        let toml = try #require(output(
            .asTOML,
            #"{"title":"Purah","port":8080,"debug":true,"server":{"host":"localhost"}}"#
        ))
        #expect(toml.contains("title = \"Purah\""))
        #expect(toml.contains("port = 8080"))
        #expect(toml.contains("debug = true"))
        #expect(toml.contains("[server]"))
        #expect(toml.contains("host = \"localhost\""))
    }

    /// TOML has no null, so a document carrying one must not be offered a
    /// half-valid file — the conversion returns nothing.
    @Test("TOML refuses what it cannot express")
    func testTOMLRefuses() {
        #expect(output(.asTOML, #"{"a":null}"#) == nil)
        #expect(output(.asTOML, #"{"a":[{"b":1}]}"#) == nil)
    }

    @Test("Oversized text offers nothing at all")
    func testSizeCap() {
        let huge = String(repeating: "a", count: ClipboardTextFormatter.maximumLength + 1)
        #expect(ClipboardTextFormatter.availableActions(for: huge).isEmpty)
    }
}
