# Changelog

## Unreleased — 0.1.0

- Native SwiftUI storage dashboard and fixed safe-cleanup targets
- Folder Explorer with physical-size inventory, Finder navigation, and reversible Trash actions
- Finder-style lazy Explorer rendering, list/grid views, on-demand folder sizing, and attached-volume navigation
- Compact, responsive workspace spacing with restrained native motion between pages, folders, and selections
- Duplicate Radar with size prefiltering and streaming SHA-256 verification
- Persistent sidebar-based Preferences and Privacy workspaces, plus richer compact duplicate-set details
- iCloud local-copy offloading that preserves cloud originals
- Generated-code final confirmation for every removal path, including cleanup, iCloud local-copy eviction, and Trash moves
- Review-first cleanup: each recommendation and review-only location opens in Explorer for item-level measurement and selection
- Expanded review locations and JavaScript package coverage: npm, Yarn, Bun, node-gyp, Corepack, pnpm, project-local stores, and build caches
- Finder-style Explorer search, iCloud/file-type filters, name/size/kind sorting, and visible click selection feedback
- Explorer quick locations (Home, Desktop, Downloads, Documents), current-folder Finder opening, and select-all/clear controls
- Visible Explorer quick-location buttons, split list-and-preview view, Finder-style modifier selection, drag-out support, and file-type icons
- Duplicate Radar and Developer Reclaim Planner now run from independent Discovery pages to avoid competing scans and interleaved results
- Removed the redundant Discovery Overview; Duplicate Radar and Reclaim Planner are direct left-sidebar destinations
- Explorer keeps a 50-step back history and can move the current home-folder subdirectory to Trash with generated-code confirmation, then return to its parent
- Added nonempty-only local AI model cleanup targets for Ollama, LM Studio, PyTorch, and Whisper
- Full Disk Access unavailable probes are now informational rather than misleading warnings
- Full Disk Access concierge, universal Intel + Apple Silicon builds, direct-download DMG, and native icon

## Release archive

Every published version, its notes, DMG, and SHA-256 checksum are available on the [GitHub Releases page](https://github.com/mrh-jishan/SpaceMinder/releases). When publishing a tag, move the matching Unreleased section above into a versioned heading and add a new Unreleased section.
