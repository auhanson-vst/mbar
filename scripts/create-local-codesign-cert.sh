#!/usr/bin/env bash
set -euo pipefail

identity="${MBAR_CODESIGN_IDENTITY:-mbar Local Code Signing}"
keychain="${MBAR_CODESIGN_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"

if security find-identity -v -p codesigning "$keychain" 2>/dev/null | grep -F "\"$identity\"" >/dev/null; then
  echo "$identity"
  exit 0
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cat > "$tmp_dir/openssl.cnf" <<EOF
[ req ]
distinguished_name = req_distinguished_name
x509_extensions = v3_codesign
prompt = no

[ req_distinguished_name ]
CN = $identity

[ v3_codesign ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
EOF

openssl req \
  -new \
  -newkey rsa:2048 \
  -nodes \
  -x509 \
  -days 3650 \
  -config "$tmp_dir/openssl.cnf" \
  -keyout "$tmp_dir/key.pem" \
  -out "$tmp_dir/cert.pem" >/dev/null 2>&1

openssl rsa -in "$tmp_dir/key.pem" -traditional -out "$tmp_dir/rsa-key.pem" >/dev/null 2>&1

security import "$tmp_dir/rsa-key.pem" \
  -k "$keychain" \
  -f openssl \
  -A >/dev/null

security import "$tmp_dir/cert.pem" \
  -k "$keychain" \
  -t cert >/dev/null

security add-trusted-cert \
  -d \
  -r trustRoot \
  -p codeSign \
  -k "$keychain" \
  "$tmp_dir/cert.pem" >/dev/null

echo "$identity"
