#!/usr/bin/env bash
# Dev-only self-signed code-signing identity "FnCaps Dev Local".
# Not for distribution: release builds use scripts/make-release-identity.sh.
# Release signing policy is decided in plan 01-09. Pattern after gksdud setup-local-signing.
set -euo pipefail

NAME="FnCaps Dev Local"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
BACKUP_DIR="$HOME/.fncaps-signing"

EXISTING="$(security find-identity -v -p codesigning | grep "\"$NAME\"" || true)"
if [ -n "$EXISTING" ]; then
  echo "이미 인증서가 있습니다:"
  echo "$EXISTING"
  exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/openssl.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -config "$WORK/openssl.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null

P12="$WORK/identity.p12"
# macOS LibreSSL p12 is accepted by security import; newer OpenSSL 3 needs -legacy.
LEGACY=()
if openssl pkcs12 -help 2>&1 | grep -q -- '-legacy'; then LEGACY=(-legacy); fi
# 전송 비밀번호는 일회용이다. openssl은 환경 변수로 받아 ps에 남기지 않는다.
# security import -P는 인자로만 받으므로 import 순간에만 짧게 보인다(M-06 수용 범위).
# ${LEGACY[@]+...}: macOS bash 3.2 treats an empty array as unbound under set -u.
FNCAPS_P12_PASSWORD="$(openssl rand -hex 16)"
export FNCAPS_P12_PASSWORD
openssl pkcs12 -export ${LEGACY[@]+"${LEGACY[@]}"} -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -name "$NAME" -out "$P12" -passout env:FNCAPS_P12_PASSWORD

security import "$P12" -k "$KEYCHAIN" -T /usr/bin/codesign -P "$FNCAPS_P12_PASSWORD"
unset FNCAPS_P12_PASSWORD

echo "다음 단계에서 macOS가 로그인 암호 또는 Touch ID를 물어봅니다. 코드 서명 용도로만 이 인증서를 신뢰하도록 설정합니다."
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

# 개발용 인증서는 백업하지 않는다(전송 비밀번호를 버리므로 p12를 다시 열 수 없다). 잃으면 이 스크립트로 새로 만든다.

echo
security find-identity -v -p codesigning | grep "$NAME"
echo "완료: 「${NAME}」 인증서를 만들었습니다."
