#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export LC_ALL=C
mkdir -p dist
version=$(sed -n 's/^Version: //p' control)
test -n "$version"

export THEOS="$HOME/theos"
export SYSROOT="$THEOS/sdks/iPhoneOS16.5.sdk"
make clean package THEOS_PACKAGE_SCHEME=rootless FINALPACKAGE=1
rootless="packages/com.wcsy.reply_${version}_iphoneos-arm64.deb"
test -f "$rootless"
cp "$rootless" "dist/wcsy-${version}-rootless.deb"

export THEOS="$HOME/theos-roothide"
export SYSROOT="$THEOS/sdks/iPhoneOS16.5.sdk"
make clean package THEOS_PACKAGE_SCHEME=roothide FINALPACKAGE=1
roothide="packages/com.wcsy.reply_${version}_iphoneos-arm64e.deb"
test -f "$roothide"
cp "$roothide" "dist/wcsy-${version}-roothide.deb"

python3 scripts/verify-packages.py "dist/wcsy-${version}-rootless.deb" "dist/wcsy-${version}-roothide.deb" \
  "dist/WcSy-${version}-app-injection.dylib"
