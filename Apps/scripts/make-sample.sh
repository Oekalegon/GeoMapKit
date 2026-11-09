#!/bin/bash
# Makes a small sample map for the apps: the area around Vaduz (Liechtenstein) as a .gmk store file of about 4 MB.
#
# It downloads liechtenstein-latest.osm.pbf (3.5 MB) from Geofabrik, so run it only when you want that. It needs the Tools package of
# GeoMapKit, which has to sit in a folder named "GeoMapKit" (the package name of the parent): see ../Tools/Package.swift.
#
#   scripts/make-sample.sh [output-folder]
#
# Then put the file into the app: in the Simulator
#   xcrun simctl get_app_container booted org.oekalegon.GeoMapKitDemo data      # prints the folder of the app
#   cp Liechtenstein.gmk "<that folder>/Documents/Maps/"
# or in the app: Library > Add a map… and pick the file in the Files app (on a device: AirDrop it, or use Finder file sharing).
set -euo pipefail
out="${1:-.}"
mkdir -p "$out"
here="$(cd "$(dirname "$0")" && pwd)"
pbf="$out/liechtenstein-latest.osm.pbf"
[ -f "$pbf" ] || curl -L --fail -o "$pbf" https://download.geofabrik.de/europe/liechtenstein-latest.osm.pbf
swift run --package-path "$here/../../Tools" -c release geomapkit build "$pbf" --center 47.14,9.52 --radius-km 10 --output "$out/Liechtenstein.gmk"
echo "Wrote $out/Liechtenstein.gmk"
