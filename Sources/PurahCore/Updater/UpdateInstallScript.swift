// Sources/PurahCore/Updater/UpdateInstallScript.swift
import Foundation

/// The shell script that swaps a downloaded bundle into place after Purah quits.
///
/// It lives in its own type so it can be tested. It is several hundred lines of
/// bash inside a Swift string literal: nothing type-checks it, and a syntax
/// error is only discovered by a user whose app has already quit and cannot
/// come back. `UpdateInstallScriptTests` writes the generated script to disk and
/// runs `bash -n` over it, then exercises the failure branches against real
/// archives.
///
/// Two rules the script has to hold:
///
/// 1. **Every failure writes a reason to `markerPath` and reopens the original
///    app.** The pre-0.6.1 script exited 1 silently after the app had quit, so
///    a rejected download looked like the app deleting itself.
/// 2. **Never modify `target` unless the replacement is fully verified.** The
///    swap moves the old bundle aside, moves the new one in, and puts the old
///    one back if that fails.
public enum UpdateInstallScript {

    /// Arguments, in order: pid, archive, target, expected team id, script path
    /// (bash's `$0`).
    ///
    /// - Parameters:
    ///   - markerPath: Where a failure writes its reason.
    ///   - workRoot: Directory for extraction and DMG mount points. Defaults to
    ///     `/tmp`; tests point it at a scratch directory.
    public static func source(markerPath: String, workRoot: String = "/tmp") -> String {
        let marker = shellQuoted(markerPath)
        let root = shellQuoted(workRoot)

        return """
        #!/bin/bash
        PID="$1"
        ARCHIVE="$2"
        TARGET="$3"
        EXPECTED_TEAM_ID="$4"
        SCRIPT_SELF="$0"
        MARKER=\(marker)
        WORK_ROOT=\(root)

        # 1. Wait for the current instance to exit. The app calls `terminate`
        # right after spawning this script, so the sleep is normally short.
        while kill -0 "$PID" 2>/dev/null; do
            sleep 0.1
        done

        # Every failure path funnels through here: record why, discard the
        # download, and bring the original app back. Never leave the user with
        # nothing running.
        abandon() {
            /bin/echo "$1" > "$MARKER"
            [[ -n "$TEMP_DIR" ]] && /bin/rm -rf "$TEMP_DIR"
            [[ -n "$MOUNT_DIR" ]] && /bin/rm -rf "$MOUNT_DIR"
            /bin/rm -f "$ARCHIVE"
            /usr/bin/open "$TARGET" 2>/dev/null || true
            /bin/rm -f "$SCRIPT_SELF"
            exit 1
        }

        TEMP_DIR=""
        MOUNT_DIR=""
        TEMP_DIR=$(mktemp -d "$WORK_ROOT/purah_update_extracted.XXXXXX") || abandon "Could not create a workspace for the update."

        # 2. Extract into a clean workspace
        if [[ "$ARCHIVE" == *.zip ]]; then
            /usr/bin/ditto -xk "$ARCHIVE" "$TEMP_DIR" || abandon "Could not extract the downloaded archive."
        elif [[ "$ARCHIVE" == *.dmg ]]; then
            MOUNT_DIR=$(mktemp -d "$WORK_ROOT/purah_dmg.XXXXXX") || abandon "Could not create a mount point for the update."
            if ! /usr/bin/hdiutil attach "$ARCHIVE" -mountpoint "$MOUNT_DIR" -nobrowse -quiet; then
                abandon "Could not open the downloaded disk image."
            fi
            /bin/cp -R "$MOUNT_DIR"/*.app "$TEMP_DIR/" 2>/dev/null || true
            /usr/bin/hdiutil detach "$MOUNT_DIR" -quiet > /dev/null 2>&1 || true
            /bin/rm -rf "$MOUNT_DIR"
            MOUNT_DIR=""
        else
            abandon "The downloaded file is neither a .zip nor a .dmg."
        fi

        # 3. Locate the new Purah.app
        NEW_APP=$(/usr/bin/find "$TEMP_DIR" -maxdepth 2 -name "Purah.app" -type d 2>/dev/null | head -n 1)
        if [[ -z "$NEW_APP" || ! -d "$NEW_APP" ]]; then
            abandon "The downloaded archive does not contain Purah.app."
        fi

        # 4. Integrity: the bundle matches its own signature.
        if ! /usr/bin/codesign --verify --deep --strict "$NEW_APP" > /dev/null 2>&1; then
            abandon "The downloaded app could not be verified."
        fi

        # 5. Publisher: the signature belongs to Purah's Developer ID team.
        # `codesign --verify` accepts any signer, so without this check a
        # replaced download would be trusted.
        TEAM_ID=$(/usr/bin/codesign -dv --verbose=4 "$NEW_APP" 2>&1 \\
            | /usr/bin/awk -F= '/^TeamIdentifier/ {print $2; exit}')
        if [[ -z "$EXPECTED_TEAM_ID" ]]; then
            abandon "This build has no signing team to verify an update against."
        fi
        if [[ "$TEAM_ID" != "$EXPECTED_TEAM_ID" ]]; then
            # No apostrophes inside `${VAR:-default}`: bash applies quoting
            # rules within the expansion, and one would open a quote that never
            # closes. That is how this line broke the first time it was run.
            /bin/echo "The downloaded app was signed by ${TEAM_ID:-an unknown team}, not ${EXPECTED_TEAM_ID:-the expected team}." > "$MARKER"
            [[ -n "$TEMP_DIR" ]] && /bin/rm -rf "$TEMP_DIR"
            /bin/rm -f "$ARCHIVE"
            /usr/bin/open "$TARGET" 2>/dev/null || true
            /bin/rm -f "$SCRIPT_SELF"
            exit 1
        fi

        # 6. Notarization / Gatekeeper assessment.
        if ! /usr/sbin/spctl --assess --type execute --verbose=2 "$NEW_APP" > /dev/null 2>&1; then
            abandon "The downloaded app did not pass Gatekeeper assessment."
        fi

        # 7. Swap. The old bundle is moved aside first and restored if the new
        # one cannot take its place, so a failure here is still recoverable.
        BACKUP="${TARGET}.backup.$$"
        if ! /bin/mv "$TARGET" "$BACKUP"; then
            abandon "The current app could not be moved aside for the update."
        fi
        if ! /bin/mv "$NEW_APP" "$TARGET"; then
            /bin/mv "$BACKUP" "$TARGET"
            abandon "The new version could not be moved into place."
        fi

        /bin/rm -rf "$BACKUP"
        /bin/rm -rf "$TEMP_DIR"
        /bin/rm -f "$ARCHIVE"
        /usr/bin/xattr -cr "$TARGET" 2>/dev/null || true
        /usr/bin/open "$TARGET"
        /bin/rm -f "$SCRIPT_SELF"
        exit 0
        """
    }

    /// Single-quotes a path for the generated script. Bundles under
    /// `~/Library`, `/Applications` names and usernames routinely contain
    /// spaces and apostrophes; an unquoted path silently becomes two arguments
    /// and the marker lands somewhere unintended.
    public static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
