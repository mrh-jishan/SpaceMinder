#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
app_dir="${project_dir}/dist/SpaceMinder.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/Resources/Info.plist")
dmg_path="${project_dir}/dist/SpaceMinder-${version}.dmg"

if [[ ! -d "$app_dir" ]]; then
  echo "Missing $app_dir. Run build-universal-app.sh first." >&2
  exit 1
fi

rm -f "$dmg_path"
hdiutil create -volname "SpaceMinder" -srcfolder "$app_dir" -ov -format UDZO "$dmg_path"
shasum -a 256 "$dmg_path" > "$dmg_path.sha256"
echo "Created $dmg_path"
