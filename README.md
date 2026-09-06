# SpaceMinder

SpaceMinder is a fully native macOS storage intelligence and cleanup app written in Swift and SwiftUI. It does not use Electron, a web view, JavaScript, a server, or external analytics.

## Download

- [Latest release and installation notes](https://github.com/mrh-jishan/SpaceMinder/releases/latest)
- [All released versions](https://github.com/mrh-jishan/SpaceMinder/releases)
- [Latest universal DMG](https://github.com/mrh-jishan/SpaceMinder/releases/latest/download/SpaceMinder-latest.dmg) — available after the first version tag is published

Each release includes its versioned DMG, a permanent `SpaceMinder-latest.dmg` link, and SHA-256 checksums. See [CHANGELOG.md](CHANGELOG.md) for release history.

## Features

- Native SwiftUI interface and Apple filesystem APIs
- Physical allocated-size scanning, including sparse virtual disks
- Fixed safe-cleanup allow-list; the interface cannot submit arbitrary deletion paths
- Exact six-digit final confirmation for every destructive action, plus app-running checks for Chrome, Xcode, and Docker
- Local cleanup history, custom **scan-only** folders, and optional launch-at-login
- Finder-style Folder Explorer: visible Home/Desktop/Downloads/Documents shortcuts, 50-step back navigation, current-folder Finder opening and full-folder measurement, direct Inspect Folder routing, instant shallow metadata listings, lazy 100-item rendering, search, file/iCloud filters, name/size/kind sorting, list/grid/split-preview views, type-aware icons, Command/Control and Shift multi-selection, drag-out support, select-all/clear controls, double-click navigation, per-folder on-demand size measurement, and reversible Trash actions—including six-digit-confirmed removal of the current home-folder subdirectory with automatic return to its parent
- Duplicate Radar: efficient two-pass SHA-256 matching that hashes only equal-size files; it is local-only and can move only an individually reviewed copy to Trash after six-digit confirmation
- Developer Reclaim Planner: identifies re-creatable `node_modules`, Yarn/pnpm project stores, JavaScript build output, virtual environments, Xcode artifacts, and project caches before you remove anything
- iCloud Drive local-copy offloading, which preserves iCloud originals while freeing downloaded local copies
- Trash as a measured, first-class cleanup target; nonempty-only local AI model stores for Hugging Face, Ollama, LM Studio, PyTorch, and Whisper; re-downloadable npm, Yarn, Bun, node-gyp, and Corepack caches; and review-first pnpm stores
- Space Pulse: persistent local scan history, a configurable free-space budget, and attached-volume visibility
- Compact responsive native workspaces with restrained motion for Dashboard, Duplicate Radar, Reclaim Planner, Folder Explorer, Pro toolkit, Preferences, and Privacy—no blocking modal navigation
- No account, network traffic, analytics, or cloud storage

## Run during development

Requires Xcode 15.3+ / Swift 5.10+. The app runs natively on macOS 13 (Ventura) and later, on both Apple Silicon and Intel Macs.

```zsh
cd spaceminder
swift run SpaceMinder
```

If macOS cannot inspect a protected folder, SpaceMinder shows an **Open Privacy Settings** action. Grant the built app **Full Disk Access** in System Settings → Privacy & Security → Full Disk Access, then scan again. The app remains useful without it for ordinary user folders. Apple does not allow an installer or app to grant Full Disk Access silently: the user must enable it after installation.

## Build a universal native `.app`

```zsh
cd spaceminder
chmod +x scripts/build-universal-app.sh
scripts/build-universal-app.sh
open dist
```

The resulting `dist/SpaceMinder.app` contains an Apple Silicon and Intel universal binary. The script applies an ad-hoc signature suitable for local use. Create a local installer with `zsh scripts/create-dmg.sh`.

## Distribute to other Macs

You can distribute a universal, direct-download DMG from GitHub Releases without an Apple Developer subscription. Recipients should download the DMG, drag the app to Applications, then Control-click the app in Finder and choose **Open** on first launch. macOS requires this warning for any app that is not Developer ID signed and notarized.

To remove that warning, sign the app with a **Developer ID Application** certificate and notarize it using your Apple Developer account. GitHub Actions performs this automatically for version tags once the repository secrets in [RELEASING.md](RELEASING.md) are configured.

```zsh
codesign --force --deep --options runtime --timestamp --sign "Developer ID Application: Your Company (TEAMID)" dist/SpaceMinder.app
ditto -c -k --keepParent dist/SpaceMinder.app SpaceMinder.zip
xcrun notarytool submit SpaceMinder.zip --keychain-profile "notary-profile" --wait
xcrun stapler staple dist/SpaceMinder.app
```
