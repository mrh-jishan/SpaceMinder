#!/bin/zsh
set -euo pipefail

# Required environment variables:
# APPLE_ID, APPLE_TEAM_ID, APPLE_APP_SPECIFIC_PASSWORD
script_dir="${0:A:h}"
project_dir="${script_dir:h}"
app_dir="${project_dir}/dist/SpaceMinder.app"
archive_path="${project_dir}/dist/SpaceMinder-notarization.zip"

: "${APPLE_ID:?Set APPLE_ID}"
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID}"
: "${APPLE_APP_SPECIFIC_PASSWORD:?Set APPLE_APP_SPECIFIC_PASSWORD}"

ditto -c -k --keepParent "$app_dir" "$archive_path"
xcrun notarytool submit "$archive_path" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --wait
xcrun stapler staple "$app_dir"
rm -f "$archive_path"
echo "Notarization ticket stapled to $app_dir"
