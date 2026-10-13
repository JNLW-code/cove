#!/bin/sh
# Makes a self-signed code-signing certificate in the login keychain, once.
# Same certificate every build means macOS keeps Cove's permission grants (Automation, Calendar).
# Needs no Apple ID, no trust-settings change and no password prompt: codesign is allowed to use the key at import.
set -eu
NAME="${1:-Cove Dev}"
if security find-identity -p codesigning 2>/dev/null | grep -q "\"$NAME\""; then
  exit 0
fi
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cfg" <<CFG
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$NAME
[ext]
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
basicConstraints=critical,CA:false
subjectKeyIdentifier=hash
CFG
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cfg" >/dev/null 2>&1
# -legacy: macOS's keychain importer does not read OpenSSL 3's default PKCS12 format
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/id.p12" -passout pass:cove -name "$NAME" >/dev/null 2>&1
security import "$TMP/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P cove \
  -T /usr/bin/codesign -T /usr/bin/security
echo "Created signing certificate \"$NAME\" in the login keychain."
