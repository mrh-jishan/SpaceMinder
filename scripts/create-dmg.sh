#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
app_dir="${project_dir}/dist/SpaceMinder.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/Resources/Info.plist")
dmg_path="${project_dir}/dist/SpaceMinder-${version}.dmg"
staging_dir=$(mktemp -d)
trap 'rm -rf "$staging_dir"' EXIT

if [[ ! -d "$app_dir" ]]; then
  echo "Missing $app_dir. Run build-universal-app.sh first." >&2
  exit 1
fi

rm -f "$dmg_path"
cp -R "$app_dir" "$staging_dir/SpaceMinder.app"
cp "$project_dir/Resources/INSTALLATION.txt" "$staging_dir/Read Me — Install.txt"
hdiutil create -volname "SpaceMinder" -srcfolder "$staging_dir" -ov -format UDZO "$dmg_path"
shasum -a 256 "$dmg_path" > "$dmg_path.sha256"
echo "Created $dmg_path"
