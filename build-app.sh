#!/bin/zsh
set -euo pipefail

project_root="$(cd "$(dirname "$0")" && pwd)"
app_path="$project_root/NodeBar.app"

swift build --package-path "$project_root" --configuration release --product NodeBar -Xswiftc -warnings-as-errors

rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$project_root/.build/release/NodeBar" "$app_path/Contents/MacOS/NodeBar"
cp "$project_root/Resources/Info.plist" "$app_path/Contents/Info.plist"

# Ad-hoc signing makes the generated bundle launchable on a development Mac.
codesign --force --deep --sign - "$app_path" >/dev/null

printf 'Built %s\n' "$app_path"
