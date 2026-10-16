#!/bin/bash
# Builds NextCharge.app (universal), signs it, wraps it in a DMG, and notarizes.
#
# Usage:
#   scripts/build-release.sh                 # ad-hoc signed, no notarization
#   SIGN_IDENTITY="Developer ID Application: ..." NOTARY_PROFILE=my-profile scripts/build-release.sh
#
# NOTARY_PROFILE is a notarytool keychain profile created with:
#   xcrun notarytool store-credentials <name> --apple-id ... --team-id ...
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${VERSION:-1.0.0}"
BUILD="${BUILD:-1}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

APP_NAME="NextCharge"
OUT="build"
APP="${OUT}/${APP_NAME}.app"
DMG="${OUT}/${APP_NAME}-${VERSION}.dmg"
SDK="$(xcrun --show-sdk-path)"

rm -rf "${APP}" "${DMG}" "${OUT}/dmg" "${OUT}/AppIcon.iconset"
mkdir -p "${OUT}"

echo "==> Compiling"
for arch in arm64 x86_64; do
  swiftc -swift-version 5 -parse-as-library -O \
    -target "${arch}-apple-macos14.0" -sdk "${SDK}" \
    Sources/*.swift -o "${OUT}/${APP_NAME}-${arch}"
done

echo "==> Assembling ${APP}"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
lipo -create "${OUT}/${APP_NAME}-arm64" "${OUT}/${APP_NAME}-x86_64" -output "${APP}/Contents/MacOS/${APP_NAME}"
sed -e "s/__VERSION__/${VERSION}/" -e "s/__BUILD__/${BUILD}/" Resources/Info.plist > "${APP}/Contents/Info.plist"
printf 'APPL????' > "${APP}/Contents/PkgInfo"

ICONSET="${OUT}/AppIcon.iconset"
mkdir -p "${ICONSET}"
for size in 16 32 128 256 512; do
  sips -z $size $size Resources/icon-1024.png --out "${ICONSET}/icon_${size}x${size}.png" >/dev/null
  sips -z $((size*2)) $((size*2)) Resources/icon-1024.png --out "${ICONSET}/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "${ICONSET}" -o "${APP}/Contents/Resources/AppIcon.icns"

echo "==> Signing (${SIGN_IDENTITY})"
if [ "${SIGN_IDENTITY}" = "-" ]; then
  codesign --force --sign - "${APP}"
else
  codesign --force --options runtime --timestamp --sign "${SIGN_IDENTITY}" "${APP}"
fi
codesign --verify --strict --verbose=2 "${APP}"

echo "==> Building DMG"
mkdir -p "${OUT}/dmg"
cp -R "${APP}" "${OUT}/dmg/"
ln -s /Applications "${OUT}/dmg/Applications"
hdiutil create -volname "${APP_NAME}" -srcfolder "${OUT}/dmg" -ov -format UDZO "${DMG}" >/dev/null
rm -rf "${OUT}/dmg"

if [ "${SIGN_IDENTITY}" != "-" ]; then
  codesign --force --timestamp --sign "${SIGN_IDENTITY}" "${DMG}"
fi

if [ -n "${NOTARY_PROFILE}" ]; then
  echo "==> Notarizing"
  xcrun notarytool submit "${DMG}" --keychain-profile "${NOTARY_PROFILE}" --wait
  xcrun stapler staple "${DMG}"
  spctl -a -t open --context context:primary-signature -vv "${DMG}"
fi

shasum -a 256 "${DMG}"
echo "DONE ${DMG}"
