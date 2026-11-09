#!/bin/bash
# Checks that the committed Xcode project is what project.yml generates (CI runs it; so can you, from anywhere).
#
# XcodeGen puts a random identifier in the reference to Config.xcconfig (TEMP_<uuid>), so the project file is compared with those
# identifiers made equal; everything else (the other generated files and the project itself) has to be the same.
set -euo pipefail
cd "$(dirname "$0")/.."
committed="$(mktemp -d)"
cp -R GeoMapKitDemo.xcodeproj "$committed/"
xcodegen generate >/dev/null
normalize() { sed -E 's/TEMP_[0-9A-Fa-f-]{36}/TEMP_ID/g' "$1"; }
if ! diff <(normalize "$committed/GeoMapKitDemo.xcodeproj/project.pbxproj") <(normalize GeoMapKitDemo.xcodeproj/project.pbxproj); then
    echo "The committed project differs from what project.yml generates: run xcodegen in Apps/ and commit the result." >&2
    exit 1
fi
# Put the committed file back, so that the check changes nothing.
cp "$committed/GeoMapKitDemo.xcodeproj/project.pbxproj" GeoMapKitDemo.xcodeproj/project.pbxproj
git diff --exit-code -- . || { echo "The generated files (Info.plist and so on) differ from the committed ones: run xcodegen in Apps/ and commit." >&2; exit 1; }
echo "The committed project is what project.yml generates."
