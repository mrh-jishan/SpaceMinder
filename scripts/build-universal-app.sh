#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
output_dir="${project_dir}/dist"
build_dir="${project_dir}/.build"
app_dir="${output_dir}/SpaceMinder.app"

cd "$project_dir"
rm -rf "$output_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"

swift build -c release --arch arm64 --arch x86_64

# Recent SwiftPM releases combine the two slices into one universal executable.
# Older releases may retain the per-architecture output layout, so retain that
# fallback and join the slices ourselves.
universal_binary=$(find "$build_dir" -path '*/Products/Release/SpaceMinder' -type f -print -quit)
if [[ -n "$universal_binary" ]]; then
  cp "$universal_binary" "$app_dir/Contents/MacOS/SpaceMinder"
else
  arm_binary=$(find "$build_dir" -path '*arm64*' -path '*/release/SpaceMinder' -type f -print -quit)
  intel_binary=$(find "$build_dir" -path '*x86_64*' -path '*/release/SpaceMinder' -type f -print -quit)
  if [[ -z "$arm_binary" || -z "$intel_binary" ]]; then
    echo "Could not locate a universal or both architecture-specific builds." >&2
    exit 1
  fi
  xcrun lipo -create "$arm_binary" "$intel_binary" -output "$app_dir/Contents/MacOS/SpaceMinder"
fi

if ! xcrun lipo -info "$app_dir/Contents/MacOS/SpaceMinder" | grep -q 'arm64.*x86_64\|x86_64.*arm64'; then
  echo "The output is not universal; refusing to package it." >&2
  exit 1
fi
cp "$project_dir/Resources/Info.plist" "$app_dir/Contents/Info.plist"
codesign --force --deep --sign - "$app_dir"
echo "Created $app_dir"
