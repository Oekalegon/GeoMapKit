#!/bin/bash
# Checks that the committed Xcode project is what project.yml generates (CI runs it; so can you, from anywhere).
#
# XcodeGen is not fully deterministic, so the project file is compared after two things are made equal:
#  - the random identifier in the reference to Config.xcconfig (TEMP_<uuid>);
#  - the reference to the package folder, which is named after the folder the repository was cloned into (and has an identifier made from
#    that name), so it is "GeoMapKit" for most people and something else in a git worktree.
# The lines are sorted before they are compared, since the file is ordered by identifier. Everything else, and the other generated files,
# has to be the same.
set -euo pipefail
cd "$(dirname "$0")/.."

normalize() {
    local file="$1" id
    id=$(grep -E 'lastKnownFileType = folder; name = .*; path = \.\.; sourceTree = SOURCE_ROOT' "$file" | head -1 | grep -oE '[0-9A-F]{24}' | head -1 || true)
    local text
    text=$(sed -E 's/TEMP_[0-9A-Fa-f-]{36}/TEMP_ID/g' "$file")
    if [ -n "$id" ]; then text=$(printf '%s\n' "$text" | sed -E "s/$id/PKG_ID/g"); fi
    printf '%s\n' "$text" \
        | sed -E 's#(PKG_ID) /\* [^*]+ \*/#\1 /* PKG */#g; s#(lastKnownFileType = folder; name = )("[^"]*"|[^;]*);( path = \.\.;)#\1PKG;\3#' \
        | sort
}

committed="$(mktemp -d)"
cp -R GeoMapKitDemo.xcodeproj "$committed/"
xcodegen generate >/dev/null
if ! diff <(normalize "$committed/GeoMapKitDemo.xcodeproj/project.pbxproj") <(normalize GeoMapKitDemo.xcodeproj/project.pbxproj); then
    echo "The committed project differs from what project.yml generates: run xcodegen in Apps/ and commit the result." >&2
    exit 1
fi
# Put the committed file back, so that the check changes nothing.
cp "$committed/GeoMapKitDemo.xcodeproj/project.pbxproj" GeoMapKitDemo.xcodeproj/project.pbxproj
git diff --exit-code -- . || { echo "The generated files (Info.plist and so on) differ from the committed ones: run xcodegen in Apps/ and commit." >&2; exit 1; }
echo "The committed project is what project.yml generates."
