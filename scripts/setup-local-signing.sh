#!/usr/bin/env bash
# ==============================================================================
# setup-local-signing.sh - Provision a stable local code-signing certificate
# ==============================================================================
#
# macOS ties TCC grants (Calendar, Reminders, Microphone, Accessibility) to an
# app's designated requirement. Ad-hoc builds carry no certificate, so the
# requirement falls back to cdhash and resets permissions on every rebuild.
# This script provisions a 10-year self-signed X.509 v3 code-signing identity
# ("Purah Local" by default) in the user's login keychain so local builds and
# self-signed releases keep a stable designated requirement across updates.
#
set -euo pipefail

BOLD="\033[1m"
GREEN="\033[0;32m"
CYAN="\033[0;36m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
RESET="\033[0m"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$REPO_ROOT/signing-identity.sh"

CERT_NAME="${PURAH_LOCAL_CERT_NAME:-Purah Local}"
FORCE=false

print_usage() {
    echo -e "${BOLD}Usage:${RESET} ./scripts/setup-local-signing.sh [options]

Provision a local self-signed code-signing identity ('${CERT_NAME}') in your
login keychain so macOS TCC permissions persist across local rebuilds.

${BOLD}Options:${RESET}
      --force     Provision '${CERT_NAME}' even if another signing identity is already resolved
  -h, --help      Show this help message

${BOLD}Environment Variables:${RESET}
  PURAH_LOCAL_CERT_NAME   Certificate common name to create (default: Purah Local)
  APPLE_SIGNING_IDENTITY  Overrides automatic identity resolution if set
  PURAH_SIGN_IDENTITY     Overrides automatic identity resolution if set
"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)
            FORCE=true
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${RESET}" >&2
            print_usage
            exit 1
            ;;
    esac
done

LOGIN_KEYCHAIN="$(security login-keychain 2>/dev/null | tr -d ' "\n')"
if [ -z "$LOGIN_KEYCHAIN" ]; then
    LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
fi

existing="$(purah_resolve_signing_identity)"
if [ -n "$existing" ] && [ "$FORCE" != true ]; then
    echo -e "${GREEN}✅ Active code-signing identity already resolved: ${BOLD}${existing}${RESET}"
    echo -e "   No new certificate created (pass ${BOLD}--force${RESET} to provision '${CERT_NAME}' anyway)."
    exit 0
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if security find-certificate -c "$CERT_NAME" "$LOGIN_KEYCHAIN" >/dev/null 2>&1; then
    if security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"$CERT_NAME\""; then
        if [ "$FORCE" != true ]; then
            echo -e "${GREEN}✅ Code-signing identity '${CERT_NAME}' is already valid in ${LOGIN_KEYCHAIN}.${RESET}"
            echo -e "   Multiple identities exist on this Mac; select it with:"
            echo -e "   ${BOLD}export PURAH_SIGN_IDENTITY=\"${CERT_NAME}\"${RESET}"
            exit 0
        fi
        echo -e "${RED}Error: Certificate '${CERT_NAME}' already exists in ${LOGIN_KEYCHAIN}.${RESET}" >&2
        echo -e "   Creating a duplicate CN would make 'codesign' ambiguous." >&2
        echo -e "   Delete the existing one first if you want to replace it:" >&2
        echo -e "   ${BOLD}security delete-certificate -c \"${CERT_NAME}\" \"${LOGIN_KEYCHAIN}\"${RESET}" >&2
        exit 1
    fi

    if security find-identity -p codesigning "$LOGIN_KEYCHAIN" 2>/dev/null | grep -Fq "\"$CERT_NAME\""; then
        echo -e "${YELLOW}⚠️  Found an untrusted '${CERT_NAME}' identity in ${LOGIN_KEYCHAIN}.${RESET}"
        security find-certificate -c "$CERT_NAME" -p "$LOGIN_KEYCHAIN" > "$TMP_DIR/cert.pem"
        echo -e "${YELLOW}🔐 macOS will now show a Touch ID / password prompt to trust '${CERT_NAME}' for code signing...${RESET}"
        security add-trusted-cert -r trustRoot -p codeSign -k "$LOGIN_KEYCHAIN" "$TMP_DIR/cert.pem"
    else
        echo -e "${RED}Error: A certificate named '${CERT_NAME}' already exists in ${LOGIN_KEYCHAIN}, but it has no matching private key or code-signing trust.${RESET}" >&2
        echo -e "   Inspect it in Keychain Access or remove the stale certificate before re-running:" >&2
        echo -e "   ${BOLD}security delete-certificate -c \"${CERT_NAME}\" \"${LOGIN_KEYCHAIN}\"${RESET}" >&2
        exit 1
    fi
else
    echo -e "${CYAN}🔏 Generating 2048-bit RSA key and 10-year X.509 v3 code-signing certificate ('${CERT_NAME}')...${RESET}"

    cat > "$TMP_DIR/openssl.cnf" <<EOF
[ req ]
distinguished_name = req_distinguished_name
x509_extensions = v3_codesign
prompt = no

[ req_distinguished_name ]
CN = ${CERT_NAME}
O = Purah Local Development

[ v3_codesign ]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

    # Explicitly use macOS system LibreSSL (/usr/bin/openssl): Homebrew OpenSSL 3
    # defaults to AES-256 PKCS#12 encryption, which `security import` rejects
    # without `-legacy`.
    if ! /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes \
        -keyout "$TMP_DIR/key.pem" \
        -out "$TMP_DIR/cert.pem" \
        -days 3650 \
        -subj "/CN=${CERT_NAME}/O=Purah Local Development" \
        -config "$TMP_DIR/openssl.cnf" \
        -extensions v3_codesign 2>"$TMP_DIR/openssl.err"; then
        cat "$TMP_DIR/openssl.err" >&2
        echo -e "${RED}Error: /usr/bin/openssl failed to generate the certificate.${RESET}" >&2
        exit 1
    fi

    P12_PASS="$(/usr/bin/openssl rand -base64 24)"
    /usr/bin/openssl pkcs12 -export \
        -out "$TMP_DIR/codesign.p12" \
        -inkey "$TMP_DIR/key.pem" \
        -in "$TMP_DIR/cert.pem" \
        -name "$CERT_NAME" \
        -passout "pass:${P12_PASS}"

    echo -e "${CYAN}📥 Importing identity into ${LOGIN_KEYCHAIN}...${RESET}"
    security import "$TMP_DIR/codesign.p12" \
        -k "$LOGIN_KEYCHAIN" \
        -P "$P12_PASS" \
        -T /usr/bin/codesign \
        -T /usr/bin/security

    echo -e "${YELLOW}🔐 macOS will now show a Touch ID / password prompt to trust '${CERT_NAME}' for code signing...${RESET}"
    security add-trusted-cert -r trustRoot -p codeSign -k "$LOGIN_KEYCHAIN" "$TMP_DIR/cert.pem"
fi

echo -e "${CYAN}🔍 Verifying code-signing identity...${RESET}"
VALID_IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
if ! printf '%s\n' "$VALID_IDENTITIES" | grep -Fq "\"$CERT_NAME\""; then
    echo -e "${RED}Error: '${CERT_NAME}' is not listed as a valid code-signing identity.${RESET}" >&2
    printf '%s\n' "$VALID_IDENTITIES" | sed 's/^/   /' >&2
    echo -e "   Check Keychain Access -> '${CERT_NAME}' -> Trust -> Code Signing: Always Trust." >&2
    exit 1
fi

RESOLVED_IDENTITY="$(purah_resolve_signing_identity)"
if [ -n "$RESOLVED_IDENTITY" ]; then
    echo -e "${GREEN}✅ Local code-signing identity ready: ${BOLD}${RESOLVED_IDENTITY}${RESET}"
    echo -e "   ${BOLD}./build.sh${RESET} and ${BOLD}./release.sh${RESET} will now use it automatically."
else
    VALID_COUNT="$(printf '%s\n' "$VALID_IDENTITIES" | awk -F'"' '/"/ {print $2}' | grep -c . || true)"
    if [ "$VALID_COUNT" -gt 1 ]; then
        echo -e "${GREEN}✅ '${CERT_NAME}' is valid in ${LOGIN_KEYCHAIN}.${RESET}"
        echo -e "${YELLOW}⚠️  Multiple valid code-signing identities exist on this Mac (${VALID_COUNT} total),${RESET}"
        echo -e "   so purah_resolve_signing_identity does not pick one automatically."
        echo -e "   Select it explicitly with: ${BOLD}export PURAH_SIGN_IDENTITY=\"${CERT_NAME}\"${RESET}"
    else
        echo -e "${RED}Error: purah_resolve_signing_identity could not resolve '${CERT_NAME}'.${RESET}" >&2
        printf '%s\n' "$VALID_IDENTITIES" | sed 's/^/   /' >&2
        exit 1
    fi
fi
