# Releasing SpaceMinder

The GitHub workflow builds on every pull request and push to `main`. It uploads a universal DMG and checksum as an Actions artifact, so native build regressions are caught before a release. A matching version tag always creates a direct-download GitHub Release.

Without an Apple Developer subscription, the release is ad-hoc signed. Users can install the DMG by Control-clicking the app in Finder and choosing **Open** once. This is the only legitimate way to distribute a macOS app directly without Apple’s Developer ID notarization; Gatekeeper cannot be removed or bypassed programmatically.

## One-time GitHub configuration

For warning-free, Apple-notarized releases, add these repository secrets in GitHub repository → **Settings → Secrets and variables → Actions**:

| Secret | Value |
| --- | --- |
| `APPLE_CERTIFICATE_P12_BASE64` | Base64 of the exported **Developer ID Application** `.p12` certificate |
| `APPLE_CERTIFICATE_PASSWORD` | Password used while exporting that `.p12` |
| `APPLE_ID` | Apple ID email used for notarization |
| `APPLE_TEAM_ID` | Ten-character Apple Developer Team ID |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific Apple ID password for notarization |

The certificate must be a **Developer ID Application** certificate, not an Apple Development or Mac App Store certificate. Do not place any credential in the repository or a workflow file.

## Publish a release

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`.
2. Commit and push the version update to `main`.
3. Create and push the matching tag. For example, version `0.2.0` requires tag `v0.2.0`.

```zsh
git tag v0.2.0
git push origin v0.2.0
```

The workflow refuses a tag only if it does not match the app version or if the output is not a universal Intel + Apple Silicon app. Without Apple credentials it publishes an ad-hoc-signed direct-download DMG with first-launch instructions and a `.sha256` checksum. With all five secrets present, it instead publishes an Apple-notarized DMG.
