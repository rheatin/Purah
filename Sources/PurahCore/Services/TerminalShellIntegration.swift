// Sources/PurahCore/Services/TerminalShellIntegration.swift
import Foundation

/// Everything needed to give a freshly launched shell the `??` hooks.
///
/// One entry point so `TerminalManager` stays a terminal and does not grow a
/// second job: install the managed startup files, make sure the loopback
/// listener is up, and write the variables the shell function reads.
public enum TerminalShellIntegration {

    /// The switch the user flips if they would rather have a bare shell.
    public static let defaultsKey = "purah.isTerminalCommandSuggestEnabled"

    public static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true
    }

    /// Installs the files and brings the listener up ahead of time.
    ///
    /// `NWListener` reports readiness asynchronously, and `prepare` has to wait
    /// for the port before the shell starts. Doing that wait at launch, off the
    /// main thread, means the wait is already over by the time anyone opens the
    /// terminal drawer.
    public static func prewarm() {
        guard isEnabled else { return }
        let bridge = TerminalSuggestionBridge.shared
        if bridge.onSuggest == nil {
            bridge.onSuggest = { mode, form in
                try await CommandSuggestionService.shared.suggest(
                    mode: mode,
                    description: form["description"] ?? "",
                    workingDirectory: form["cwd"] ?? NSHomeDirectory(),
                    lastCommand: form["last"],
                    lastExitStatus: Int32(form["status"] ?? ""),
                    // The shell's PATH, not the app's: it is the one the
                    // command will run under when Return is pressed.
                    pathList: form["path"],
                    // Its aliases too — `find` is `fd` in this shell, and the
                    // flags are not the same — plus the last few exchanges.
                    history: form["history"],
                    aliases: form["aliases"]
                )
            }
        }
        _ = ZshSuggestionIntegration.installIfNeeded()
        _ = bridge.startIfNeeded()
    }

    /// Adds `ZDOTDIR` and the bridge variables to a shell's environment.
    ///
    /// - Returns: true when the environment was prepared. False means the shell
    ///   will start exactly as it would without Purah — no managed files, no
    ///   variables — so a failure here can never half-install the feature.
    @discardableResult
    public static func prepare(environment: inout [String: String], shellPath: String) -> Bool {
        guard isEnabled else { return false }
        // The hooks are zsh only: `print -z`, `precmd` and the alias-expansion
        // rule that makes `??` work are zsh behaviour, not POSIX.
        guard (shellPath as NSString).lastPathComponent == "zsh" else { return false }
        guard let managedDirectory = ZshSuggestionIntegration.installIfNeeded() else { return false }

        let bridge = TerminalSuggestionBridge.shared
        if bridge.onSuggest == nil {
            prewarm()
        }
        guard let endpoint = bridge.startIfNeeded() else { return false }

        // The real dotfiles usually live in $HOME, but a person who already set
        // ZDOTDIR meant it. Unless it is our own directory — a Purah embedded in
        // Purah's terminal would otherwise source itself forever.
        let inherited = environment["ZDOTDIR"]
        let realDirectory: String = {
            guard let inherited, !inherited.isEmpty,
                  URL(fileURLWithPath: inherited).standardizedFileURL != managedDirectory.standardizedFileURL
            else { return NSHomeDirectory() }
            return inherited
        }()

        environment["PURAH_REAL_ZDOTDIR"] = realDirectory
        environment["PURAH_MANAGED_ZDOTDIR"] = managedDirectory.path
        environment["ZDOTDIR"] = managedDirectory.path
        environment["PURAH_AI_PORT"] = String(endpoint.port)
        environment["PURAH_BRIDGE_TOKEN"] = endpoint.token
        return true
    }
}
