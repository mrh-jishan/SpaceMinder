# SpaceMinder

SpaceMinder is a fully native macOS storage intelligence and cleanup app written in Swift and SwiftUI. It does not use Electron, a web view, JavaScript, a server, or external analytics.

## Features

- Native SwiftUI interface and Apple filesystem APIs
- Physical allocated-size scanning, including sparse virtual disks
- Fixed safe-cleanup allow-list; the interface cannot submit arbitrary deletion paths
- Explicit destructive confirmation and app-running checks for Chrome, Xcode, and Docker
- Local cleanup history, custom **scan-only** folders, and optional launch-at-login
- No account, network traffic, analytics, or cloud storage

## Run during development

Requires Xcode 15.3+ / Swift 5.10+. The app runs natively on macOS 13 (Ventura) and later, on both Apple Silicon and Intel Macs.

```zsh
cd spaceminder
swift run SpaceMinder
```

If macOS cannot inspect a protected folder, grant the built app **Full Disk Access** in System Settings → Privacy & Security → Full Disk Access, then scan again. The app is still restricted to its fixed user-library cleanup locations.

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
