#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
configuration="${1:-debug}"
app_dir="$project_dir/output/Nudge.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"

cd "$project_dir"
swift build -c "$configuration" --product Nudge

binary_path="$(swift build -c "$configuration" --show-bin-path)/Nudge"

mkdir -p "$macos_dir"
cp "$project_dir/App/Info.plist" "$contents_dir/Info.plist"
cp "$binary_path" "$macos_dir/Nudge"
codesign --force --deep --sign - "$app_dir"

echo "$app_dir"
