# Releasing SpaceMinder

The GitHub workflow builds on every pull request and push to `main`. It uploads a universal DMG and checksum as an Actions artifact, so native build regressions are caught before a release.

## One-time GitHub configuration

GitHub repository → **Settings → Secrets and variables → Actions** → add these repository secrets:

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

The workflow refuses to publish a tag release if signing/notarization credentials are absent, if the tag does not match the app version, or if the output is not a universal Intel + Apple Silicon app. On success, GitHub Releases receives the notarized DMG and `.sha256` checksum automatically.
