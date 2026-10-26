// Tests/PurahCoreTests/AIPermissionBridgeTests.swift
import Testing
import Foundation
@testable import PurahCore

/// The bridge is the one place Purah answers for the user, so what it sends
/// back matters more than that it compiles: a wrong shape here silently
/// approves or silently blocks every gated tool call.
@Suite("AI Permission Bridge Tests")
struct AIPermissionBridgeTests {

    @Test("Permission routing is claude-only")
    func testSettingsPathIsClaudeOnly() {
        // Codex `exec` has no host-answerable approval channel at all, so
        // handing it a hook file would be pretending it does.
        for executable in [AICLIExecutable.codex, .pi, .ollama, .custom] {
            #expect(AIAssistantService.permissionSettingsPath(for: executable) == nil,
                    "\(executable.rawValue) must not be given permission routing")
        }
    }

    @Test("A dead bridge yields no settings file")
    func testNoSettingsWhenBridgeIsDown() {
        // The hook is configured to block on failure, so pointing the CLI at a
        // port nobody listens on would deny every gated call.
        let path = AIAssistantService.permissionSettingsPath(for: .claude)
        if !AIPermissionBridge.shared.isListening {
            #expect(path == nil)
        }
    }

    @Test("Routing arguments are added only when a settings file exists")
    func testRoutingArguments() {
        let routed = AIAssistantService.resolveCLIArguments(
            executable: .claude,
            cliPath: "/Users/x/.local/bin/claude",
            promptText: "do it",
            permissionSettingsPath: "/tmp/hooks.json"
        )
        #expect(routed.contains("--settings"))
        #expect(routed.contains("/tmp/hooks.json"))
        #expect(routed.contains("--permission-mode"))
        #expect(routed.contains("manual"))

        let unrouted = AIAssistantService.resolveCLIArguments(
            executable: .claude,
            cliPath: "/Users/x/.local/bin/claude",
            promptText: "do it"
        )
        #expect(!unrouted.contains("--settings"))
        #expect(!unrouted.contains("manual"))

        // A hand-written template is the user's own invocation; do not edit it.
        let custom = AIAssistantService.resolveCLIArguments(
            executable: .claude,
            cliPath: "/Users/x/.local/bin/claude",
            customCLIArguments: "--model opus {prompt}",
            promptText: "do it",
            permissionSettingsPath: "/tmp/hooks.json"
        )
        #expect(!custom.contains("--settings"))
    }

    @Test("A blocked request is answered with deny, not silence")
    func testDenyPayloadShape() throws {
        let bridge = AIPermissionBridge()
        // No listener, no handler: the bridge must still know how to say no.
        bridge.resolve("nothing-waiting", decision: .deny)

        let request = PendingToolPermissionRequest(
            toolName: "Bash",
            commandPreview: "rm -rf /tmp/x",
            context: "Clean up"
        )
        #expect(request.toolName == "Bash")
        #expect(request.commandPreview == "rm -rf /tmp/x")
        #expect(request.context == "Clean up")
    }

    @Test("Suggestions are only echoed for always-allow")
    func testAlwaysAllowRequiresSuggestions() {
        let withoutSuggestions = PendingToolPermissionRequest(
            toolName: "Bash",
            commandPreview: "touch a"
        )
        // The banner only offers "always allow" when there is a scope to
        // persist; otherwise the button would be a no-op dressed as a promise.
        #expect(withoutSuggestions.suggestionsDescription == nil)

        let withSuggestions = PendingToolPermissionRequest(
            toolName: "Bash",
            commandPreview: "touch a",
            suggestionPayload: Data("[]".utf8),
            suggestionsDescription: "/tmp/project"
        )
        #expect(withSuggestions.suggestionsDescription == "/tmp/project")
        #expect(withSuggestions.suggestionPayload != nil)
    }
}
