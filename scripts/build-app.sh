#!/usr/bin/env bash
# Build FnCaps.app (or FnCapsSpike.app) from the SwiftPM product and sign it.
# Signing: "FnCaps Dev Local" identity if present (stable Accessibility grant), else ad-hoc.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="release"
ARCH_FLAGS=()
FORCE_ADHOC=0
REQUIRE_IDENTITY=0
PRODUCT_KIND="app"
VERSION_OVERRIDE=""

usage() {
  cat <<USAGE
사용법: scripts/build-app.sh [--product app|spike] [--debug] [--universal] [--adhoc]
                           [--require-identity] [--version X.Y.Z] [--help]
  --product           app(FnCaps.app, 기본) 또는 spike(FnCapsSpike.app)
  --debug             debug 구성으로 빌드 (기본: release)
  --universal         arm64 + x86_64 유니버설 빌드 (기본: arm64만)
  --adhoc             인증서가 있어도 ad-hoc 서명
  --require-identity  서명 인증서를 못 찾으면 ad-hoc으로 넘어가지 않고 실패
  --version X.Y.Z     번들 사본의 CFBundleShortVersionString만 바꿈(원본 plist는 그대로)
  --help              이 도움말
환경 변수:
  FNCAPS_SIGN_IDENTITY  서명 인증서 이름 (기본: FnCaps Dev Local)
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --product) [ "$#" -ge 2 ] || { echo "--product 값이 필요합니다" >&2; usage >&2; exit 2; }; PRODUCT_KIND="$2"; shift ;;
    --product=*) PRODUCT_KIND="${1#--product=}" ;;
    --version) [ "$#" -ge 2 ] || { echo "--version 값이 필요합니다" >&2; usage >&2; exit 2; }; VERSION_OVERRIDE="$2"; shift ;;
    --version=*) VERSION_OVERRIDE="${1#--version=}" ;;
    --debug) CONFIG="debug" ;;
    --universal) ARCH_FLAGS=(--arch arm64 --arch x86_64) ;;
    --adhoc) FORCE_ADHOC=1 ;;
    --require-identity) REQUIRE_IDENTITY=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "알 수 없는 옵션: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done
# 값 검사는 빌드 전에 끝낸다.
if [ -n "$VERSION_OVERRIDE" ] && ! printf '%s' "$VERSION_OVERRIDE" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "오류: --version 값은 X.Y.Z 형식이어야 합니다: $VERSION_OVERRIDE" >&2
  exit 2
fi
if [ "$REQUIRE_IDENTITY" -eq 1 ] && [ "$FORCE_ADHOC" -eq 1 ]; then
  echo "오류: --adhoc과 --require-identity는 함께 쓸 수 없습니다" >&2
  exit 1
fi
case "$PRODUCT_KIND" in
  app)
    PRODUCT="FnCaps"; BUNDLE_ID="io.github.seo650.fncaps"; APP="build/FnCaps.app"; PLIST="Resources/FnCaps-Info.plist" ;;
  spike)
    PRODUCT="FnCapsSpike"; BUNDLE_ID="dev.fncaps.spike"; APP="build/FnCapsSpike.app"; PLIST="Resources/FnCapsSpike-Info.plist" ;;
  *) echo "알 수 없는 제품: $PRODUCT_KIND (app 또는 spike)" >&2; usage >&2; exit 2 ;;
esac
if [ "${#ARCH_FLAGS[@]}" -eq 0 ]; then ARCH_FLAGS=(--arch arm64); fi

IDENTITY_NAME="${FNCAPS_SIGN_IDENTITY:-FnCaps Dev Local}"

# SwiftPM 기본 엔진은 바이너리에 sdk 14.0을 적어 macOS 26/27에서 예전 모양으로 실행된다(04-RESEARCH-BUILD B7~B9, PA1).
# 최소 버전은 Package.swift의 .macOS(.v14)와 같은 14.0, SDK 값은 실제 SDK 버전을 적는다.
MIN_OS="14.0"
SDKVER="$(xcrun --show-sdk-version)"
SDK_FLAGS=(-Xlinker -platform_version -Xlinker macos -Xlinker "$MIN_OS" -Xlinker "$SDKVER")

swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" "${SDK_FLAGS[@]}" --product "$PRODUCT"
BIN="$(swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" -Xlinker -platform_version -Xlinker macos -Xlinker "$MIN_OS" -Xlinker "$SDKVER" --show-bin-path)/$PRODUCT"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/$PRODUCT"
cp "$PLIST" "$APP/Contents/Info.plist"
# 시험용 번들 버전. Resources/ 원본 plist는 바꾸지 않는다.
if [ -n "$VERSION_OVERRIDE" ]; then
  plutil -replace CFBundleShortVersionString -string "$VERSION_OVERRIDE" "$APP/Contents/Info.plist"
fi

# LC_BUILD_VERSION 검사: minos는 14.0, sdk는 14.0이 아닌 실제 SDK 버전이어야 한다.
BUILD_VERSION="$(otool -l "$APP/Contents/MacOS/$PRODUCT" | grep -A4 LC_BUILD_VERSION || true)"
GOT_MINOS="$(printf '%s\n' "$BUILD_VERSION" | awk '$1 == "minos" {print $2; exit}')"
GOT_SDK="$(printf '%s\n' "$BUILD_VERSION" | awk '$1 == "sdk" {print $2; exit}')"
if [ "$GOT_MINOS" != "$MIN_OS" ] || [ -z "$GOT_SDK" ] || [ "$GOT_SDK" = "14.0" ] || [ "$GOT_SDK" != "$SDKVER" ]; then
  echo "오류: 실행 파일의 LC_BUILD_VERSION이 맞지 않습니다(minos ${GOT_MINOS:-없음}, sdk ${GOT_SDK:-없음}). 기대값: minos $MIN_OS, sdk $SDKVER" >&2
  exit 1
fi

if [ "$PRODUCT_KIND" = "app" ]; then
  RES="$APP/Contents/Resources"
  mkdir -p "$RES"
  cp -R Resources/*.lproj "$RES/"
  for n in on on@2x on@3x permission permission@2x permission@3x; do
    cp "Resources/Assets/menubar/$n.png" "$RES/$n.png"
  done
  for n in bmc-cup bmc-cup@2x bmc-cup@3x bmc-cup-dark bmc-cup-dark@2x bmc-cup-dark@3x; do
    cp "Resources/Assets/buymeacoffee/$n.png" "$RES/$n.png"
  done
  for n in github-mark github-mark@2x github-mark@3x github-mark-dark github-mark-dark@2x github-mark-dark@3x; do
    cp "Resources/Assets/github/$n.png" "$RES/$n.png"
  done
  ICON_TMP="$(mktemp -d)"
  trap 'rm -rf "$ICON_TMP"' EXIT
  ICONSET="$ICON_TMP/AppIcon.iconset"
  mkdir -p "$ICONSET"
  SRC="Resources/Assets/app-icon.png"
  for sz in 16 32 128 256 512; do
    sips -z "$sz" "$sz" "$SRC" --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null
    sips -z "$((sz * 2))" "$((sz * 2))" "$SRC" --out "$ICONSET/icon_${sz}x${sz}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$RES/AppIcon.icns"
  plutil -lint "$APP/Contents/Info.plist"
  # 번들 안 복사본을 검사해 복사 누락도 잡는다. 문법이 틀리면 set -e로 빌드가 멈춘다.
  for f in "$RES"/*.lproj/Localizable.strings; do
    plutil -lint "$f"
  done
  # 기대 개수는 Info.plist의 CFBundleLocalizations에서 읽는다. Resources 수와 비교하면
  # 소스에서 lproj가 빠져도 둘이 같이 줄어 검사를 통과하므로 선언 목록과 맞춘다.
  WANT_LPROJ=$(plutil -extract CFBundleLocalizations raw Resources/FnCaps-Info.plist)
  APP_LPROJ=$(find "$RES" -maxdepth 1 -type d -name '*.lproj' | wc -l | tr -d ' ')
  if [ "$WANT_LPROJ" -ne "$APP_LPROJ" ]; then
    echo "lproj 수가 다릅니다: CFBundleLocalizations ${WANT_LPROJ}개, 앱 번들 ${APP_LPROJ}개" >&2
    exit 1
  fi
  for d in "$RES"/*.lproj; do
    if [ ! -f "$d/Localizable.strings" ]; then
      echo "Localizable.strings가 없습니다: $d" >&2
      exit 1
    fi
  done
fi

SHA1="$(security find-identity -v -p codesigning | grep -F "\"$IDENTITY_NAME\"" | awk '{print $2}' | head -n1 || true)"

# 릴리스는 ad-hoc으로 떨어지면 업데이트 요건이 깨지므로 실패하게 한다.
if [ "$REQUIRE_IDENTITY" -eq 1 ] && [ -z "${FNCAPS_SIGN_IDENTITY:-}" ]; then
  echo "오류: --require-identity에는 FNCAPS_SIGN_IDENTITY를 지정해야 합니다(개발용 인증서로 릴리스가 서명되는 것을 막음)" >&2
  exit 1
fi
if [ "$REQUIRE_IDENTITY" -eq 1 ] && [ -z "$SHA1" ]; then
  echo "오류: 서명 인증서 「$IDENTITY_NAME」를 찾지 못했습니다" >&2
  exit 1
fi

MODE="ADHOC"
if [ -n "$SHA1" ] && [ "$FORCE_ADHOC" -eq 0 ]; then
  codesign --force --options runtime --timestamp=none --identifier "$BUNDLE_ID" \
    --sign "$SHA1" \
    --requirements "=designated => identifier \"$BUNDLE_ID\" and certificate leaf = H\"$SHA1\"" \
    "$APP"
  MODE="LOCAL"
else
  codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
  echo "경고: ad-hoc 서명입니다. 다시 빌드할 때마다 손쉬운 사용 권한이 풀립니다(cdhash 요건)." >&2
  echo "      scripts/make-local-identity.sh 로 로컬 인증서를 만드세요." >&2
fi

codesign -dr- "$APP" || true
echo "서명 모드: $MODE"
if [ "$MODE" = "LOCAL" ]; then
  echo "서명 인증서: $IDENTITY_NAME"
fi
echo "앱: $APP"
if [ "$PRODUCT_KIND" = "app" ]; then
  echo "권한 시험은 반드시 'open $APP'으로 실행하세요. 터미널에서 바이너리를 직접 실행하면 터미널의 손쉬운 사용 권한을 물려받습니다."
fi
