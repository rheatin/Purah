// Sources/PurahCore/Services/ZshSuggestionIntegration.swift
import Foundation

/// Installs the zsh side of `??`.
///
/// The alias has to exist in the *interactive shell*, which means it has to
/// arrive through one of zsh's startup files. Purah will not edit the person's
/// dotfiles — that is their file, and a merge there is a merge that eventually
/// loses. Instead the shell is launched with `ZDOTDIR` pointing at a managed
/// directory whose files source the real ones first and add the hooks second.
/// Removing the feature is then just not setting the variable.
///
/// `??` is an **alias**, not a function. zsh filename-generates command words:
/// with a two-character file in the working directory, a `??` command expands
/// to that filename and the shell reports "command not found: j1". Alias
/// expansion happens before globbing, so the alias always wins.
public enum ZshSuggestionIntegration {

    public static let fileNameMarker = "# Managed by Purah"

    public static var directory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("Purah/ShellIntegration/zsh", isDirectory: true)
    }

    /// Writes the managed startup files, replacing them only when their content
    /// changed. Returns the directory to hand to `ZDOTDIR`, or nil if it could
    /// not be written (in which case the shell starts untouched).
    @discardableResult
    public static func installIfNeeded() -> URL? {
        let fm = FileManager.default
        let dir = directory
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            DiagnosticLogger.shared.warn("Terminal", "Could not create shell integration directory: \(error.localizedDescription)")
            return nil
        }

        let files: [(String, String)] = [
            (".zshenv", zshenv),
            (".zprofile", zprofile),
            (".zshrc", zshrc),
            (".zlogin", zlogin),
        ]
        for (name, content) in files {
            let url = dir.appendingPathComponent(name)
            if let existing = try? String(contentsOf: url, encoding: .utf8), existing == content {
                continue
            }
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                DiagnosticLogger.shared.warn("Terminal", "Could not write \(name): \(error.localizedDescription)")
                return nil
            }
        }
        return dir
    }

    // MARK: - Startup files

    /// Sourced for every shell, so it must do nothing but hand off to the real
    /// `.zshenv` and put `ZDOTDIR` back so the rest of the managed chain loads.
    public static let zshenv = """
    \(fileNameMarker). Regenerated on launch; edits here are overwritten.
    #
    # The shell is started with ZDOTDIR pointing at this directory so Purah can
    # add `??` without editing your dotfiles. Each file in here sources the real
    # one from PURAH_REAL_ZDOTDIR and then restores ZDOTDIR to this directory.

    __purah_real_zdotdir="${PURAH_REAL_ZDOTDIR:-$HOME}"
    __purah_managed_zdotdir="${ZDOTDIR:-$HOME}"

    if [[ -f "$__purah_real_zdotdir/.zshenv" ]]; then
      ZDOTDIR="$__purah_real_zdotdir"
      source "$__purah_real_zdotdir/.zshenv"
    fi
    export ZDOTDIR="$__purah_managed_zdotdir"
    """

    public static let zprofile = """
    \(fileNameMarker). Regenerated on launch; edits here are overwritten.

    __purah_real_zdotdir="${PURAH_REAL_ZDOTDIR:-$HOME}"
    __purah_managed_zdotdir="${ZDOTDIR:-$HOME}"

    if [[ -f "$__purah_real_zdotdir/.zprofile" ]]; then
      ZDOTDIR="$__purah_real_zdotdir"
      source "$__purah_real_zdotdir/.zprofile"
    fi
    export ZDOTDIR="$__purah_managed_zdotdir"
    """

    public static let zlogin = """
    \(fileNameMarker). Regenerated on launch; edits here are overwritten.

    __purah_real_zdotdir="${PURAH_REAL_ZDOTDIR:-$HOME}"
    __purah_managed_zdotdir="${ZDOTDIR:-$HOME}"

    if [[ -f "$__purah_real_zdotdir/.zlogin" ]]; then
      ZDOTDIR="$__purah_real_zdotdir"
      source "$__purah_real_zdotdir/.zlogin"
    fi
    export ZDOTDIR="$__purah_managed_zdotdir"
    """

    /// The real `.zshrc` first — anything it defines (prompt, aliases, PATH)
    /// must look exactly like a normal shell — then the `??` hooks.
    public static let zshrc = """
    \(fileNameMarker). Regenerated on launch; edits here are overwritten.

    __purah_real_zdotdir="${PURAH_REAL_ZDOTDIR:-$HOME}"
    __purah_managed_zdotdir="${ZDOTDIR:-$HOME}"

    if [[ -f "$__purah_real_zdotdir/.zshrc" ]]; then
      ZDOTDIR="$__purah_real_zdotdir"
      source "$__purah_real_zdotdir/.zshrc"
    fi
    export ZDOTDIR="$__purah_managed_zdotdir"

    # --- `??` natural-language command suggestions -------------------------
    # `?? what you want in your own words` asks Purah for one command and puts
    # it on the input line. Nothing runs until you press Return.
    if [[ -n "$PURAH_AI_PORT" && -n "$PURAH_BRIDGE_TOKEN" ]]; then
      typeset -g __purah_last_status=0
      typeset -g __purah_last_command=""

      # precmd keeps the last exit status and command line for `???`.
      __purah_precmd() {
        __purah_last_status=$?
        __purah_last_command="$(fc -ln -1 2>/dev/null)"
        __purah_last_command="${__purah_last_command##[[:space:]]#}"
      }
      autoload -Uz add-zsh-hook 2>/dev/null && add-zsh-hook precmd __purah_precmd

      __purah_ask() {
        emulate -L zsh
        local mode="$1"
        shift
        local description="$*"
        local response

        # A local model that reasons first can take 20-30 seconds, which is a
        # long time to stare at a prompt that looks stuck. The banner is
        # replaced by the answer once it arrives.
        print -P "%F{213}%B⚡ Purah 正在思考…%b%f"

        # `Expect:` suppresses curl's 100-continue wait on larger bodies.
        response=$(/usr/bin/curl -sS -m 120 -H "Expect:" \\
          -H "Authorization: Bearer $PURAH_BRIDGE_TOKEN" \\
          --data-urlencode "mode=$mode" \\
          --data-urlencode "description=$description" \\
          --data-urlencode "cwd=$PWD" \\
          --data-urlencode "last=$__purah_last_command" \\
          --data-urlencode "status=$__purah_last_status" \\
          --data-urlencode "path=$PATH" \\
          "http://127.0.0.1:$PURAH_AI_PORT/v1/suggest" 2>&1)

        # Drop the banner line so the answer takes its place.
        printf '\\e[1A\\e[2K\\r'

        if [[ -z "$response" ]]; then
          print -u2 "purah: no answer — is Purah running?"
          return 1
        fi

        local -a lines
        lines=("${(@f)response}")

        if [[ "${lines[1]}" != "#risk="* ]]; then
          if [[ "${lines[1]}" == "#error" ]]; then
            print -u2 "purah: ${lines[2]:-the assistant gave no reason}"
          else
            print -u2 "purah: ${lines[1]:-no answer} — is Purah running?"
          fi
          return 1
        fi

        local risk="${lines[1]#\\#risk=}"
        local command="${lines[2]}"
        local explanation="${lines[3]}"

        if [[ -z "$command" ]]; then
          print -u2 "purah: the answer contained no command"
          return 1
        fi

        if [[ "$risk" == "dangerous" ]]; then
          print -P "%F{red}⚠ this one can destroy data — read it before pressing Return%f"
          [[ -n "$explanation" ]] && print -P "%F{red}$explanation%f"
        elif [[ "$risk" == "caution" ]]; then
          print -P "%F{yellow}• $explanation%f"
        elif [[ -n "$explanation" ]]; then
          print -P "%F{240}$explanation%f"
        fi

        print -z -- "$command"
      }

      __purah_suggest() {
        if [[ $# -eq 0 ]]; then
          print -u2 "usage: ?? <describe what you want to do>"
          return 1
        fi
        __purah_ask suggest "$@"
      }

      __purah_explain() {
        __purah_ask explain "$@"
      }

      alias '??'='__purah_suggest'
      alias '???'='__purah_explain'

      # Typing `??` is the mode indicator. Foreground colour and italics only: a
      # background block paints the whole cell, fights every theme, and looks
      # like a selection rather than a state. The hint itself lives in the
      # drawer footer, so the input line stays clean.
      #
      # Anything already redrawing the line (a syntax highlighter) is chained
      # rather than replaced, and only our own entry is removed between frames.
      typeset -g __purah_prior_pre_redraw="${widgets[zle-line-pre-redraw]:-}"

      __purah_mode_chip() {
        # Drop our own entry from the previous frame by its exact text; the
        # pattern is quoted so `#` in the colour cannot be read as a glob.
        region_highlight=(${region_highlight:#"0 2 fg=#FF5FA2,bold,italic"})
        region_highlight=(${region_highlight:#"0 3 fg=#FF5FA2,bold,italic"})
        if [[ "$BUFFER" == \\?\\?\\?* ]]; then
          region_highlight+=("0 3 fg=#FF5FA2,bold,italic")
        elif [[ "$BUFFER" == \\?\\?* ]]; then
          region_highlight+=("0 2 fg=#FF5FA2,bold,italic")
        fi
      }

      zle-line-pre-redraw() {
        if [[ -n "$__purah_prior_pre_redraw" && "$__purah_prior_pre_redraw" != zle-line-pre-redraw ]]; then
          "$__purah_prior_pre_redraw"
        fi
        __purah_mode_chip
      }
      zle -N zle-line-pre-redraw
    fi
    """
}
