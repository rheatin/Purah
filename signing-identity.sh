#!/usr/bin/env bash
# ==============================================================================
# signing-identity.sh - Which codesign identity build.sh and release.sh use
# ==============================================================================
#
# macOS keys every TCC grant (calendar, reminders, microphone) to the app's
# signature. An ad-hoc signature carries no certificate, so the designated
# requirement falls back to the cdhash — a hash of the binary that changes on
# every build. The result is that each update looks like a new app and the
# user is asked to grant access again. One stable certificate fixes that.
#
# Resolution order: APPLE_SIGNING_IDENTITY, PURAH_SIGN_IDENTITY, then the only
# valid codesigning identity on the machine. More than one identity means the
# choice belongs to the machine's owner, so we do not guess.
purah_resolve_signing_identity() {
    if [ -n "${APPLE_SIGNING_IDENTITY:-}" ]; then
        printf '%s' "$APPLE_SIGNING_IDENTITY"
        return
    fi
    if [ -n "${PURAH_SIGN_IDENTITY:-}" ]; then
        printf '%s' "$PURAH_SIGN_IDENTITY"
        return
    fi

    local identities
    identities="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/"/ {print $2}')"
    if [ "$(printf '%s\n' "$identities" | grep -c .)" -eq 1 ]; then
        printf '%s' "$identities"
    fi
}
