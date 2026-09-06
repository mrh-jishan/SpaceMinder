import SwiftUI
import AppKit
import ServiceManagement
import CryptoKit

@main
struct SpaceMinderApp: App {
    @StateObject private var model = StorageViewModel()

    var body: some Scene {
        WindowGroup("SpaceMinder") {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1000, minHeight: 680)
                .task { await model.scan() }
        }
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView().environmentObject(model)
        }
    }
}

enum CleanupKind: String, Codable {
    case contents, directory, file
}

enum CleanupSafety: String, Codable, CaseIterable {
    case safe = "Safe"
    case redownloadable = "Re-downloadable"
    case destructive = "Destructive"

    var tint: Color {
        switch self {
        case .safe: .mint
        case .redownloadable: .orange
        case .destructive: .red
        }
    }
}

struct StorageTarget: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let url: URL
    let kind: CleanupKind
    let safety: CleanupSafety
    let appsToQuit: [String]
    var bytes: Int64 = 0
    var exists: Bool = false

    static let cleanup: [StorageTarget] = [
        .init(id: "user-caches", title: "Application caches", detail: "Temporary data apps can recreate. Quit apps before cleaning.", url: home("Library/Caches"), kind: .contents, safety: .safe, appsToQuit: []),
        .init(id: "npm-cache", title: "npm download cache", detail: "Downloaded package archives, never project source or node_modules.", url: home(".npm/_cacache"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "yarn-cache", title: "Yarn cache", detail: "Yarn Classic download cache. It can be restored from package registries.", url: home("Library/Caches/Yarn"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "yarn-cache-alt", title: "Yarn alternate cache", detail: "Yarn cache used by some installations. Packages download again when needed.", url: home(".cache/yarn"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "bun-cache", title: "Bun package cache", detail: "Downloaded Bun packages. Projects can restore them with Bun.", url: home(".bun/install/cache"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "node-gyp-cache", title: "Node build cache", detail: "Node-gyp headers and compiled build prerequisites. They can be recreated.", url: home(".cache/node-gyp"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "corepack-cache", title: "Corepack package-manager cache", detail: "Downloaded package-manager releases for npm, Yarn, and pnpm.", url: home("Library/Caches/node/corepack"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "pip-cache", title: "pip download cache", detail: "Downloaded Python packages and wheels. pip downloads them again when needed.", url: home("Library/Caches/pip"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "pip-cache-alt", title: "pip alternate cache", detail: "Python package downloads stored by XDG-style pip installations. Packages can be fetched again.", url: home(".cache/pip"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "poetry-cache", title: "Poetry package cache", detail: "Downloaded Python packages cached by Poetry. Project environments are not removed.", url: home("Library/Caches/pypoetry"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "uv-cache", title: "uv package cache", detail: "Downloaded Python packages and wheels cached by uv. They can be restored from registries.", url: home("Library/Caches/uv"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "pyenv-build-cache", title: "pyenv build download cache", detail: "Python source archives cached while pyenv builds interpreters. Installed Python versions are not removed.", url: home(".pyenv/cache"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "rbenv-build-cache", title: "rbenv build download cache", detail: "Ruby source archives cached while rbenv builds interpreters. Installed Ruby versions are not removed.", url: home(".rbenv/cache"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "nodenv-build-cache", title: "nodenv build download cache", detail: "Node.js source archives cached while nodenv builds runtimes. Installed Node versions are not removed.", url: home(".nodenv/cache"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "asdf-download-cache", title: "asdf runtime downloads", detail: "Downloaded archives used by asdf plugins. Installed runtimes and version settings are not removed.", url: home(".asdf/downloads"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "mise-cache", title: "mise cache", detail: "Downloaded runtime archives and temporary data cached by mise. Installed runtimes are not removed.", url: home("Library/Caches/mise"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "mise-download-cache", title: "mise runtime downloads", detail: "Downloaded archives used to install mise-managed runtimes. Installed runtimes are not removed.", url: home(".local/share/mise/downloads"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "nvm-download-cache", title: "nvm download cache", detail: "Downloaded Node.js archives cached by nvm. Installed Node versions are not removed.", url: home(".nvm/.cache"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "rustup-download-cache", title: "rustup downloads", detail: "Downloaded Rust toolchain archives. Installed Rust toolchains are not removed.", url: home(".rustup/downloads"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "sdkman-download-cache", title: "SDKMAN downloads", detail: "Downloaded JVM and SDK archives awaiting or supporting installation. Installed SDKs are not removed.", url: home(".sdkman/tmp"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "rvm-download-cache", title: "RVM download cache", detail: "Downloaded Ruby archives cached by RVM. Installed Ruby versions are not removed.", url: home(".rvm/archives"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "homebrew-cache", title: "Homebrew download cache", detail: "Downloaded Homebrew formula and Cask archives. Installed formulae and apps are not removed.", url: home("Library/Caches/Homebrew"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "homebrew-logs", title: "Homebrew logs", detail: "Homebrew build and diagnostic logs. Installed formulae and apps are not removed.", url: home("Library/Logs/Homebrew"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "maven-cache", title: "Maven local repository", detail: "Java and JVM dependencies, which can include artifacts installed locally. Review before removal; public packages download again when projects build.", url: home(".m2/repository"), kind: .directory, safety: .destructive, appsToQuit: []),
        .init(id: "gradle-cache", title: "Gradle dependency cache", detail: "Downloaded Gradle dependencies and transforms. Project files and Gradle settings stay intact.", url: home(".gradle/caches"), kind: .directory, safety: .redownloadable, appsToQuit: []),
        .init(id: "gradle-wrapper-cache", title: "Gradle wrapper downloads", detail: "Downloaded Gradle distributions. The wrapper downloads them again when needed.", url: home(".gradle/wrapper/dists"), kind: .directory, safety: .redownloadable, appsToQuit: []),
        .init(id: "cocoapods-cache", title: "CocoaPods download cache", detail: "Downloaded Ruby CocoaPods archives. Pods in projects are not removed.", url: home("Library/Caches/CocoaPods"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "rubygems-download-cache", title: "RubyGems download cache", detail: "Downloaded Ruby gem archives shared across Ruby installations. Installed gems are not removed.", url: home(".cache/gem/gems"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "rubygems-spec-cache", title: "RubyGems specification cache", detail: "Cached RubyGem repository metadata. RubyGems fetches it again when needed.", url: home(".gem/specs"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "go-build-cache", title: "Go build cache", detail: "Compiled Go build artifacts. Go recreates them on the next build.", url: home("Library/Caches/go-build"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "go-module-download-cache", title: "Go module download cache", detail: "Downloaded Go module archives. Modules can be fetched again with Go.", url: home("go/pkg/mod/cache/download"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "cargo-registry-cache", title: "Cargo registry cache", detail: "Downloaded Rust crate archives. Cargo can download them again.", url: home(".cargo/registry/cache"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "cargo-git-cache", title: "Cargo Git cache", detail: "Cached Rust Git dependencies. Cargo can fetch them again.", url: home(".cargo/git/db"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "huggingface-cache", title: "Hugging Face models", detail: "Downloaded AI models. They will download again if used.", url: home(".cache/huggingface"), kind: .directory, safety: .redownloadable, appsToQuit: []),
        .init(id: "ollama-models", title: "Ollama models", detail: "Downloaded local AI models. Pull them again with Ollama if needed.", url: home(".ollama/models"), kind: .directory, safety: .redownloadable, appsToQuit: ["Ollama"]),
        .init(id: "lm-studio-cache", title: "LM Studio models", detail: "Downloaded local AI models. Review models before removing them.", url: home(".cache/lm-studio/models"), kind: .directory, safety: .redownloadable, appsToQuit: ["LM Studio"]),
        .init(id: "torch-model-cache", title: "PyTorch model cache", detail: "Downloaded model checkpoints and Hub assets that can be fetched again.", url: home(".cache/torch"), kind: .directory, safety: .redownloadable, appsToQuit: []),
        .init(id: "whisper-model-cache", title: "Whisper model cache", detail: "Downloaded speech-recognition models that can be downloaded again.", url: home(".cache/whisper"), kind: .directory, safety: .redownloadable, appsToQuit: []),
        .init(id: "xcode-device-support", title: "Xcode iOS DeviceSupport", detail: "Device symbols used to debug connected iPhones and iPads.", url: home("Library/Developer/Xcode/iOS DeviceSupport"), kind: .directory, safety: .redownloadable, appsToQuit: ["Xcode"]),
        .init(id: "chrome-ai-model", title: "Chrome on-device AI model", detail: "Downloaded model only; bookmarks, passwords, and history stay intact.", url: home("Library/Application Support/Google/Chrome/OptGuideOnDeviceModel"), kind: .directory, safety: .redownloadable, appsToQuit: ["Google Chrome"]),
        .init(id: "trash", title: "Trash", detail: "Items already marked for deletion. Empty it only after reviewing its contents.", url: home(".Trash"), kind: .contents, safety: .safe, appsToQuit: []),
        .init(id: "docker-disk", title: "Docker virtual disk", detail: "All local Docker images, containers, volumes, and build cache.", url: home("Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"), kind: .file, safety: .destructive, appsToQuit: ["Docker"])
    ]

    static let insights: [StorageTarget] = [
        .init(id: "pyenv-versions", title: "pyenv installed Python versions", detail: "Installed Python runtimes and virtual environments. Review each version and remove it with pyenv uninstall; SpaceMinder never removes this automatically.", url: home(".pyenv/versions"), kind: .directory, safety: .destructive, appsToQuit: []),
        .init(id: "rbenv-versions", title: "rbenv installed Ruby versions", detail: "Installed Ruby runtimes and gems. Review each version and remove it with rbenv uninstall; SpaceMinder never removes this automatically.", url: home(".rbenv/versions"), kind: .directory, safety: .destructive, appsToQuit: []),
        .init(id: "nodenv-versions", title: "nodenv installed Node versions", detail: "Installed Node.js runtimes and global packages. Review each version before removing it with nodenv uninstall.", url: home(".nodenv/versions"), kind: .directory, safety: .destructive, appsToQuit: []),
        .init(id: "asdf-installs", title: "asdf installed runtimes", detail: "Installed language runtimes managed by asdf. Inspect versions and remove them through asdf uninstall.", url: home(".asdf/installs"), kind: .directory, safety: .destructive, appsToQuit: []),
        .init(id: "mise-installs", title: "mise installed runtimes", detail: "Installed language runtimes managed by mise. Inspect versions and remove them through mise uninstall.", url: home(".local/share/mise/installs"), kind: .directory, safety: .destructive, appsToQuit: []),
        .init(id: "nvm-versions", title: "nvm installed Node versions", detail: "Installed Node.js runtimes and global packages. Inspect versions and remove them with nvm uninstall.", url: home(".nvm/versions"), kind: .directory, safety: .destructive, appsToQuit: []),
        .init(id: "volta-tools", title: "Volta installed tools", detail: "Installed Volta-managed Node, npm, pnpm, and Yarn tools. Inspect versions and remove them through Volta.", url: home(".volta/tools"), kind: .directory, safety: .destructive, appsToQuit: []),
        .init(id: "rustup-toolchains", title: "rustup installed toolchains", detail: "Installed Rust toolchains and components. Inspect versions and remove them with rustup toolchain uninstall.", url: home(".rustup/toolchains"), kind: .directory, safety: .destructive, appsToQuit: []),
        .init(id: "sdkman-candidates", title: "SDKMAN installed SDKs", detail: "Installed JVM and other SDKs. Inspect versions and remove them with SDKMAN before reclaiming space.", url: home(".sdkman/candidates"), kind: .directory, safety: .destructive, appsToQuit: []),
        .init(id: "rvm-rubies", title: "RVM installed Rubies", detail: "Installed Ruby runtimes and gems. Inspect versions and remove them with RVM; SpaceMinder never removes this automatically.", url: home(".rvm/rubies"), kind: .directory, safety: .destructive, appsToQuit: []),
        .init(id: "miniconda-packages", title: "Miniconda package cache", detail: "Downloaded and extracted Conda packages. Environments are not removed; use conda clean for cache-aware cleanup.", url: home("miniconda3/pkgs"), kind: .directory, safety: .redownloadable, appsToQuit: []),
        .init(id: "anaconda-packages", title: "Anaconda package cache", detail: "Downloaded and extracted Conda packages. Environments are not removed; use conda clean for cache-aware cleanup.", url: home("anaconda3/pkgs"), kind: .directory, safety: .redownloadable, appsToQuit: []),
        .init(id: "miniforge-packages", title: "Miniforge package cache", detail: "Downloaded and extracted Conda packages. Environments are not removed; use conda clean for cache-aware cleanup.", url: home("miniforge3/pkgs"), kind: .directory, safety: .redownloadable, appsToQuit: []),
        .init(id: "simulators", title: "Xcode simulators", detail: "Remove unused devices in Xcode → Window → Devices and Simulators.", url: home("Library/Developer/CoreSimulator"), kind: .directory, safety: .redownloadable, appsToQuit: ["Xcode"]),
        .init(id: "derived-data", title: "Xcode Derived Data", detail: "Build indexes and intermediates that Xcode can recreate.", url: home("Library/Developer/Xcode/DerivedData"), kind: .directory, safety: .redownloadable, appsToQuit: ["Xcode"]),
        .init(id: "ios-backups", title: "iPhone & iPad backups", detail: "Local device backups. Review the device and date before removal.", url: home("Library/Application Support/MobileSync/Backup"), kind: .directory, safety: .destructive, appsToQuit: []),
        .init(id: "pnpm", title: "pnpm store", detail: "Shared project dependencies. Review it or run pnpm store prune; do not blindly remove it.", url: home("Library/pnpm/store"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "application-support", title: "Application Support", detail: "App data, downloads, and databases. Review individual app folders first.", url: home("Library/Application Support"), kind: .directory, safety: .destructive, appsToQuit: []),
        .init(id: "app-containers", title: "App Containers", detail: "Sandboxed app data. Inspect each app folder before changing anything.", url: home("Library/Containers"), kind: .directory, safety: .destructive, appsToQuit: []),
        .init(id: "group-containers", title: "Group Containers", detail: "Shared data used by app suites. Review carefully before removal.", url: home("Library/Group Containers"), kind: .directory, safety: .destructive, appsToQuit: []),
        .init(id: "chrome-profile", title: "Chrome profile", detail: "Clear browser cache in Chrome; SpaceMinder never deletes profile data.", url: home("Library/Application Support/Google/Chrome"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "icloud-drive", title: "iCloud Drive local copies", detail: "Inspect downloaded copies and remove local downloads while keeping iCloud originals.", url: home("Library/Mobile Documents/com~apple~CloudDocs"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "messages-attachments", title: "Messages attachments", detail: "Photos and files from Messages. Some content may be protected by macOS privacy.", url: home("Library/Messages/Attachments"), kind: .directory, safety: .destructive, appsToQuit: ["Messages"]),
        .init(id: "mail-downloads", title: "Mail downloads", detail: "Downloaded Mail attachments. Review account folders and messages first.", url: home("Library/Containers/com.apple.mail/Data/Library/Mail Downloads"), kind: .directory, safety: .destructive, appsToQuit: ["Mail"]),
        .init(id: "logs", title: "User logs", detail: "Application and diagnostic logs. Inspect recent files before removal.", url: home("Library/Logs"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "downloads", title: "Downloads", detail: "Review installers, archives, and duplicate exports manually.", url: home("Downloads"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "documents", title: "Documents", detail: "Project exports, archives, and older downloads often accumulate here.", url: home("Documents"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "desktop", title: "Desktop projects", detail: "Dormant development projects may contain re-creatable dependencies and build output.", url: home("Desktop"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "movies", title: "Movies", detail: "Large recordings and exports. Review exact files before removal.", url: home("Movies"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "pictures", title: "Pictures", detail: "Photos libraries and media. Review in the owning app before changing files.", url: home("Pictures"), kind: .directory, safety: .destructive, appsToQuit: [])
    ]

    static func home(_ path: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: path)
    }
}

struct VolumeStatus {
    let total: Int64
    let available: Int64
    var used: Int64 { max(0, total - available) }
    var usedFraction: Double { total == 0 ? 0 : Double(used) / Double(total) }
}

struct CleanupEvent: Codable, Identifiable {
    let id: UUID
    let date: Date
    let targets: [String]
    let freedBytes: Int64
}

struct StorageSnapshot: Codable, Identifiable {
    let id: UUID
    let date: Date
    let totalBytes: Int64
    let availableBytes: Int64
    let recommendedBytes: Int64
}

struct DuplicateFile: Identifiable, Hashable {
    let url: URL
    let bytes: Int64
    let modifiedAt: Date?
    var id: String { url.path }
}

struct DuplicateGroup: Identifiable, Hashable {
    let digest: String
    let files: [DuplicateFile]
    let bytesPerFile: Int64
    var id: String { digest }
    var reclaimableBytes: Int64 { Int64(max(0, files.count - 1)) * bytesPerFile }
}

struct DuplicateScanResult: Sendable {
    let groups: [DuplicateGroup]
    let inspectedFiles: Int
    let wasCapped: Bool
}

struct DirectoryEntry: Identifiable, Hashable, Sendable {
    let url: URL
    let bytes: Int64
    let isDirectory: Bool
    let isICloud: Bool
    let isDownloaded: Bool
    let isMeasured: Bool
    var id: String { url.path }
}

struct DirectoryInventory: Sendable {
    let root: URL
    let entries: [DirectoryEntry]
    let inaccessibleItems: Int
    let scannedFiles: Int
    let wasCapped: Bool
}

struct DirectoryMeasurement: Sendable {
    let bytes: Int64
    let scannedFiles: Int
    let wasCapped: Bool
}

struct MountedVolume: Identifiable, Hashable {
    let url: URL
    let name: String
    let totalBytes: Int64
    let availableBytes: Int64
    var id: String { url.path }
}

struct DeveloperArtifact: Identifiable, Hashable, Sendable {
    let url: URL
    let category: String
    let bytes: Int64
    var id: String { url.path }
}

struct DeveloperArtifactResult: Sendable {
    let artifacts: [DeveloperArtifact]
    let wasCapped: Bool
}

@MainActor
final class StorageViewModel: ObservableObject {
    @Published private(set) var volume = VolumeStatus(total: 0, available: 0)
    @Published private(set) var cleanupTargets: [StorageTarget] = []
    @Published private(set) var insightTargets: [StorageTarget] = []
    @Published private(set) var history: [CleanupEvent] = []
    @Published var selected = Set<String>()
    @Published var isScanning = false
    @Published var isCleaning = false
    @Published var notice: String?
    @Published private(set) var duplicateGroups: [DuplicateGroup] = []
    @Published private(set) var duplicateStatus = "Choose folders to inspect. Files stay local and are never deleted automatically."
    @Published var isScanningDuplicates = false
    @Published private(set) var protectedLocationsAvailable = false
    @Published private(set) var inventory: DirectoryInventory?
    @Published var isInspectingDirectory = false
    @Published private(set) var measuringEntries = Set<String>()
    @Published private(set) var currentFolderMeasurement: DirectoryMeasurement?
    @Published var isMeasuringCurrentFolder = false
    @Published var isMeasuringAllDirectories = false
    @Published private(set) var bulkMeasurementCompleted = 0
    @Published private(set) var bulkMeasurementTotal = 0
    @Published private(set) var mountedVolumes: [MountedVolume] = []
    @Published private(set) var snapshots: [StorageSnapshot] = []
    @Published private(set) var developerArtifacts: [DeveloperArtifact] = []
    @Published private(set) var developerArtifactStatus = "Choose a workspace to find re-creatable development artifacts."
    @Published var isScanningDeveloperArtifacts = false
    @AppStorage("launchAtLogin") var launchAtLogin = false
    @AppStorage("customScanPaths") private var customScanPathsData = Data()

    private let scanner = LocalStorageScanner()
    private let cleaner = SafeCleaner()

    init() {
        history = CleanupHistory.load()
        snapshots = SnapshotHistory.load()
        protectedLocationsAvailable = PermissionProbe.canReadProtectedLocations()
    }

    var selectedBytes: Int64 {
        cleanupTargets.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.bytes }
    }

    var customPaths: [URL] {
        get { (try? JSONDecoder().decode([URL].self, from: customScanPathsData)) ?? [] }
        set { customScanPathsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    func scan() async {
        isScanning = true
        let custom = customPaths
        let result = await Task.detached(priority: .userInitiated) { [scanner] in
            scanner.scan(cleanup: StorageTarget.cleanup, insights: StorageTarget.insights, custom: custom)
        }.value
        let nonEmptyCleanup = result.cleanup.filter { $0.exists && $0.bytes > 0 }
        let nonEmptyInsights = result.insights.filter { $0.exists && $0.bytes > 0 }
        volume = result.volume
        cleanupTargets = nonEmptyCleanup
        insightTargets = nonEmptyInsights
        mountedVolumes = VolumeScanner.mounted()
        recordSnapshot(recommendedBytes: nonEmptyCleanup.reduce(0) { $0 + $1.bytes })
        selected = selected.intersection(Set(nonEmptyCleanup.map(\.id)))
        isScanning = false
    }

    func cleanSelected() async {
        let targets = cleanupTargets.filter { selected.contains($0.id) && $0.exists }
        guard !targets.isEmpty else { return }
        isCleaning = true
        let outcome = await Task.detached(priority: .userInitiated) { [cleaner] in
            cleaner.clean(targets)
        }.value
        history.insert(CleanupEvent(id: UUID(), date: .now, targets: outcome.removed, freedBytes: outcome.freed), at: 0)
        CleanupHistory.save(history)
        notice = outcome.message
        selected.removeAll()
        isCleaning = false
        await scan()
    }

    func addCustomPath() {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder to inspect"
        panel.message = "Custom folders are scan-only; SpaceMinder will never delete them automatically."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        if panel.runModal() == .OK {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            customPaths = Array(Set(customPaths + panel.urls.filter { $0.path.hasPrefix(home + "/") }))
            Task { await scan() }
        }
    }

    func updateLoginItem() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if launchAtLogin { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch { notice = "macOS could not update the login item: \(error.localizedDescription)" }
    }

    var duplicateReclaimableBytes: Int64 {
        duplicateGroups.reduce(0) { $0 + $1.reclaimableBytes }
    }

    func scanDuplicates(in folders: [URL]) async {
        guard !folders.isEmpty else { return }
        isScanningDuplicates = true
        duplicateStatus = "Indexing file sizes, then hashing only matching candidates…"
        let result = await Task.detached(priority: .userInitiated) {
            DuplicateFinder.find(in: folders)
        }.value
        duplicateGroups = result.groups
        let capNote = result.wasCapped ? " The scan stopped at 30,000 files; narrow the folders for a complete pass." : ""
        duplicateStatus = "Inspected \(result.inspectedFiles.formatted()) files and found \(result.groups.count) duplicate sets.\(capNote)"
        isScanningDuplicates = false
    }

    func trashDuplicateFiles(_ files: [DuplicateFile]) {
        var moved = 0
        var failures = 0
        let paths = Set(files.map { $0.url.path })
        for file in files {
            do {
                try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
                moved += 1
            } catch {
                failures += 1
            }
        }
        if moved > 0 {
            duplicateGroups = duplicateGroups.compactMap { group in
                let retained = group.files.filter { !paths.contains($0.url.path) }
                guard retained.count > 1 else { return nil }
                return DuplicateGroup(digest: group.digest, files: retained, bytesPerFile: group.bytesPerFile)
            }
        }
        notice = failures == 0
            ? "Moved \(moved) duplicate file(s) to Trash. They can be restored until Trash is emptied."
            : "Moved \(moved) duplicate file(s); \(failures) could not be moved to Trash."
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func openInFinder(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func openFullDiskAccess() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }

    func refreshPermissionStatus() {
        protectedLocationsAvailable = PermissionProbe.canReadProtectedLocations()
    }

    private func recordSnapshot(recommendedBytes: Int64) {
        let current = StorageSnapshot(id: UUID(), date: .now, totalBytes: volume.total, availableBytes: volume.available, recommendedBytes: recommendedBytes)
        if let newest = snapshots.first, newest.date.timeIntervalSinceNow > -1_800 {
            snapshots[0] = current
        } else {
            snapshots.insert(current, at: 0)
        }
        snapshots = Array(snapshots.prefix(60))
        SnapshotHistory.save(snapshots)
    }

    func inspectDirectory(_ url: URL) async {
        isInspectingDirectory = true
        currentFolderMeasurement = nil
        let result = await Task.detached(priority: .userInitiated) { DirectoryInspector.inspect(url) }.value
        inventory = result
        isInspectingDirectory = false
    }

    func measureDirectoryEntry(_ entry: DirectoryEntry) async {
        guard entry.isDirectory, !measuringEntries.contains(entry.id) else { return }
        measuringEntries.insert(entry.id)
        let measurement = await Task.detached(priority: .userInitiated) { DirectoryInspector.measure(entry.url) }.value
        guard let current = inventory else { measuringEntries.remove(entry.id); return }
        let entries = current.entries.map { item in
            item.id == entry.id ? DirectoryEntry(url: item.url, bytes: measurement.bytes, isDirectory: item.isDirectory, isICloud: item.isICloud, isDownloaded: item.isDownloaded, isMeasured: true) : item
        }
        inventory = DirectoryInventory(root: current.root, entries: entries.sorted { $0.bytes > $1.bytes }, inaccessibleItems: current.inaccessibleItems, scannedFiles: measurement.scannedFiles, wasCapped: measurement.wasCapped)
        measuringEntries.remove(entry.id)
        if measurement.wasCapped { notice = "Measurement for \(entry.url.lastPathComponent) stopped after \(measurement.scannedFiles.formatted()) files. Choose a narrower folder for a complete size." }
    }

    func measureCurrentDirectory() async {
        guard let root = inventory?.root, !isMeasuringCurrentFolder else { return }
        isMeasuringCurrentFolder = true
        currentFolderMeasurement = nil
        let measurement = await Task.detached(priority: .userInitiated) { DirectoryInspector.measure(root) }.value
        guard inventory?.root == root else { isMeasuringCurrentFolder = false; return }
        currentFolderMeasurement = measurement
        isMeasuringCurrentFolder = false
        if measurement.wasCapped {
            notice = "Current-folder measurement stopped after \(measurement.scannedFiles.formatted()) files. Choose a narrower folder for a complete total."
        }
    }

    func measureAllDirectories() async {
        guard let current = inventory, !isMeasuringAllDirectories else { return }
        let directories = current.entries.filter { $0.isDirectory && !$0.isMeasured }
        guard !directories.isEmpty else { return }
        isMeasuringAllDirectories = true
        bulkMeasurementCompleted = 0
        bulkMeasurementTotal = directories.count
        for directory in directories {
            await measureDirectoryEntry(directory)
            bulkMeasurementCompleted += 1
        }
        isMeasuringAllDirectories = false
    }

    func scanDeveloperArtifacts(in roots: [URL]) async {
        guard !roots.isEmpty else { return }
        isScanningDeveloperArtifacts = true
        developerArtifactStatus = "Looking for generated development folders…"
        let result = await Task.detached(priority: .userInitiated) { DeveloperArtifactFinder.find(in: roots) }.value
        developerArtifacts = result.artifacts
        developerArtifactStatus = "Found \(result.artifacts.count) re-creatable artifact(s).\(result.wasCapped ? " Scan capped at 100 folders; narrow the workspace for complete results." : "")"
        isScanningDeveloperArtifacts = false
    }

    func trash(_ entries: [DirectoryEntry]) {
        var moved = 0
        var failures = 0
        for entry in entries {
            do { try FileManager.default.trashItem(at: entry.url, resultingItemURL: nil); moved += 1 }
            catch { failures += 1 }
        }
        notice = failures == 0 ? "Moved \(moved) item(s) to Trash. Empty Trash when you are ready to reclaim the storage." : "Moved \(moved) item(s); \(failures) item(s) could not be moved to Trash."
        if let root = inventory?.root { Task { await inspectDirectory(root); await scan() } }
    }

    @discardableResult
    func trashFolder(_ url: URL) -> Bool {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            notice = "Moved \(url.lastPathComponent) to Trash. It can be restored until Trash is emptied."
            Task { await scan() }
            return true
        } catch {
            notice = "Could not move \(url.lastPathComponent) to Trash: \(error.localizedDescription)"
            return false
        }
    }

    func removeLocalICloudCopies(_ entries: [DirectoryEntry]) {
        var offloaded = 0
        var failures = 0
        for entry in entries where entry.isICloud && entry.isDownloaded {
            do { try FileManager.default.evictUbiquitousItem(at: entry.url); offloaded += 1 }
            catch { failures += 1 }
        }
        notice = failures == 0 ? "Removed local copies of \(offloaded) iCloud item(s). Their iCloud originals remain available." : "Offloaded \(offloaded) item(s); \(failures) item(s) could not be offloaded."
        if let root = inventory?.root { Task { await inspectDirectory(root); await scan() } }
    }
}

private struct ScanResult: Sendable {
    let volume: VolumeStatus
    let cleanup: [StorageTarget]
    let insights: [StorageTarget]
}

private final class LocalStorageScanner: @unchecked Sendable {
    private let fileManager = FileManager.default

    func scan(cleanup: [StorageTarget], insights: [StorageTarget], custom: [URL]) -> ScanResult {
        let enrich: (StorageTarget) -> StorageTarget = { target in
            var copy = target
            copy.exists = self.fileManager.fileExists(atPath: target.url.path)
            copy.bytes = copy.exists ? self.allocatedSize(of: target.url) : 0
            return copy
        }
        let customTargets = custom.map { url in
            StorageTarget(id: "custom-\(url.path)", title: url.lastPathComponent, detail: "Custom scan-only location. SpaceMinder will not delete it.", url: url, kind: .directory, safety: .safe, appsToQuit: [])
        }
        return ScanResult(volume: volumeStatus(), cleanup: cleanup.map(enrich), insights: (insights + customTargets).map(enrich))
    }

    private func volumeStatus() -> VolumeStatus {
        let root = URL(fileURLWithPath: "/")
        guard let values = try? root.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]) else {
            return VolumeStatus(total: 0, available: 0)
        }
        let total = Int64(values.volumeTotalCapacity ?? 0)
        let available: Int64
        if let importantCapacity = values.volumeAvailableCapacityForImportantUsage {
            available = importantCapacity
        } else if let normalCapacity = values.volumeAvailableCapacity {
            available = Int64(normalCapacity)
        } else {
            available = 0
        }
        return VolumeStatus(total: total, available: available)
    }

    private func allocatedSize(of url: URL) -> Int64 {
        var total: Int64 = 0
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        if let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants], errorHandler: { _, _ in true }) else { return 0 }
        for case let item as URL in enumerator {
            guard let values = try? item.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }
}

private enum PermissionProbe {
    /// macOS has no supported API that reveals an app's Full Disk Access setting.
    /// This is only a best-effort capability probe. A false result is deliberately
    /// shown as informational because Mail/Messages might simply not exist.
    static func canReadProtectedLocations() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let probes = [home.appendingPathComponent("Library/Mail"), home.appendingPathComponent("Library/Messages")]
        let existingProbes = probes.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existingProbes.isEmpty else { return false }
        return existingProbes.contains {
            (try? FileManager.default.contentsOfDirectory(atPath: $0.path)) != nil
        }
    }
}

private enum DuplicateFinder {
    static func find(in folders: [URL], maxFiles: Int = 30_000, minimumBytes: Int64 = 1_048_576) -> DuplicateScanResult {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey]
        var sameSize: [Int64: [URL]] = [:]
        var inspected = 0
        var capped = false

        outer: for folder in folders {
            guard let enumerator = manager.enumerator(at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants], errorHandler: { _, _ in true }) else { continue }
            for case let file as URL in enumerator {
                guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
                let bytes = Int64(values.fileAllocatedSize ?? values.fileSize ?? 0)
                guard bytes >= minimumBytes else { continue }
                inspected += 1
                if inspected > maxFiles { capped = true; break outer }
                sameSize[bytes, default: []].append(file)
            }
        }

        var byDigest: [String: [DuplicateFile]] = [:]
        for (bytes, files) in sameSize where files.count > 1 {
            for file in files {
                guard let digest = sha256(of: file) else { continue }
                let modifiedAt = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                byDigest[digest, default: []].append(DuplicateFile(url: file, bytes: bytes, modifiedAt: modifiedAt))
            }
        }
        let groups = byDigest.compactMap { digest, files -> DuplicateGroup? in
            guard files.count > 1, let bytes = files.first?.bytes else { return nil }
            return DuplicateGroup(digest: digest, files: files.sorted { $0.url.path < $1.url.path }, bytesPerFile: bytes)
        }
        .sorted { $0.reclaimableBytes > $1.reclaimableBytes }
        return DuplicateScanResult(groups: groups, inspectedFiles: inspected, wasCapped: capped)
    }

    private static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            guard let chunk = try? handle.read(upToCount: 1_048_576), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private enum DirectoryInspector {
    /// Finder-fast inventory: only direct children are read initially. Expensive
    /// recursive allocation totals are requested per folder by the user.
    static func inspect(_ root: URL) -> DirectoryInventory {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        var inaccessible = 0
        let urls = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys), options: [])) ?? []
        let entries = urls.compactMap { url -> DirectoryEntry? in
            guard let values = try? url.resourceValues(forKeys: keys) else { inaccessible += 1; return nil }
            let directory = values.isDirectory == true
            let bytes = directory ? 0 : Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
            return DirectoryEntry(url: url, bytes: bytes, isDirectory: directory, isICloud: values.isUbiquitousItem == true, isDownloaded: values.ubiquitousItemDownloadingStatus == .current, isMeasured: !directory)
        }
        return DirectoryInventory(root: root, entries: entries.sorted { $0.url.lastPathComponent.localizedCaseInsensitiveCompare($1.url.lastPathComponent) == .orderedAscending }, inaccessibleItems: inaccessible, scannedFiles: 0, wasCapped: false)
    }

    static func measure(_ root: URL, maxFiles: Int = 150_000) -> DirectoryMeasurement {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true }) else { return DirectoryMeasurement(bytes: 0, scannedFiles: 0, wasCapped: false) }
        var total: Int64 = 0
        var scannedFiles = 0
        var capped = false
        for case let item as URL in enumerator {
            guard let values = try? item.resourceValues(forKeys: keys) else { continue }
            guard values.isDirectory != true else { continue }
            scannedFiles += 1
            if scannedFiles > maxFiles { capped = true; break }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
        return DirectoryMeasurement(bytes: total, scannedFiles: scannedFiles, wasCapped: capped)
    }
}

private enum VolumeScanner {
    static func mounted() -> [MountedVolume] {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) else { return [] }
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            let available = values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)
            return MountedVolume(url: url, name: values.volumeName ?? url.lastPathComponent, totalBytes: Int64(values.volumeTotalCapacity ?? 0), availableBytes: available)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

private enum DeveloperArtifactFinder {
    private static let categories: [String: String] = [
        "node_modules": "JavaScript dependencies",
        ".yarn": "Yarn project cache and releases (review)",
        ".pnpm-store": "pnpm project-local store (review)",
        ".next": "Next.js build output",
        ".nuxt": "Nuxt build output",
        ".svelte-kit": "SvelteKit build output",
        ".parcel-cache": "Parcel build cache",
        ".vite": "Vite build cache",
        "dist": "Distribution build output",
        "build": "Build output",
        ".turbo": "Turborepo cache",
        ".venv": "Python virtual environment",
        "venv": "Python virtual environment",
        "__pycache__": "Python bytecode cache",
        ".pytest_cache": "pytest cache",
        ".mypy_cache": "mypy type-check cache",
        ".ruff_cache": "Ruff lint cache",
        ".tox": "tox Python test environments",
        ".nox": "nox Python test environments",
        ".hypothesis": "Hypothesis test data cache",
        ".eggs": "Python build dependencies",
        "pip-wheel-metadata": "Python package build metadata",
        "target": "Maven or JVM build output",
        "coverage": "Test coverage output",
        "DerivedData": "Xcode derived data",
        "Pods": "CocoaPods dependencies",
        ".gradle": "Gradle cache"
    ]

    static func find(in roots: [URL], maxArtifacts: Int = 100) -> DeveloperArtifactResult {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        var artifacts: [DeveloperArtifact] = []
        var capped = false
        outer: for root in roots {
            guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants], errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: keys), values.isDirectory == true,
                      let category = category(for: url) else { continue }
                enumerator.skipDescendants()
                artifacts.append(DeveloperArtifact(url: url, category: category, bytes: allocatedSize(of: url, keys: keys)))
                if artifacts.count >= maxArtifacts { capped = true; break outer }
            }
        }
        return DeveloperArtifactResult(artifacts: artifacts.sorted { $0.bytes > $1.bytes }, wasCapped: capped)
    }

    private static func category(for url: URL) -> String? {
        if let category = categories[url.lastPathComponent] { return category }
        let parent = url.deletingLastPathComponent().lastPathComponent
        if url.lastPathComponent == "bundle" && parent == "vendor" { return "Ruby Bundler dependencies" }
        if url.lastPathComponent == "cache" && (parent == "vendor" || parent == "tmp") { return "Ruby project cache" }
        return nil
    }

    private static func allocatedSize(of root: URL, keys: Set<URLResourceKey>) -> Int64 {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: keys), values.isDirectory != true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }
}

private struct CleanupOutcome: Sendable {
    let removed: [String]
    let freed: Int64
    let message: String
}

private final class SafeCleaner: @unchecked Sendable {
    private let fileManager = FileManager.default

    func clean(_ targets: [StorageTarget]) -> CleanupOutcome {
        var freed: Int64 = 0
        var removed: [String] = []
        var blocked: [String] = []
        for target in targets {
            let running = target.appsToQuit.filter(isRunning)
            guard running.isEmpty else { blocked.append("Quit \(running.joined(separator: " and ")) to clean \(target.title)."); continue }
            let before = size(of: target.url)
            do {
                switch target.kind {
                case .contents:
                    for url in try fileManager.contentsOfDirectory(at: target.url, includingPropertiesForKeys: nil, options: []) {
                        try fileManager.removeItem(at: url)
                    }
                case .directory, .file:
                    try fileManager.removeItem(at: target.url)
                }
                freed += before
                removed.append(target.title)
            } catch {
                blocked.append("Could not clean \(target.title): \(error.localizedDescription)")
            }
        }
        let summary = removed.isEmpty ? "Nothing was removed." : "Removed \(removed.count) item(s) and reclaimed about \(ByteCountFormatter.string(fromByteCount: freed, countStyle: .file))."
        return CleanupOutcome(removed: removed, freed: freed, message: ([summary] + blocked).joined(separator: " "))
    }

    private func size(of url: URL) -> Int64 {
        let scanner = LocalStorageScanner()
        return scanner.scan(cleanup: [StorageTarget(id: "temporary", title: "temporary", detail: "", url: url, kind: .file, safety: .safe, appsToQuit: [])], insights: [], custom: []).cleanup[0].bytes
    }

    private func isRunning(_ name: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { app in
            app.localizedName?.localizedCaseInsensitiveContains(name) == true
        }
    }
}

private enum CleanupHistory {
    private static var file: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "SpaceMinder")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "cleanup-history.json")
    }
    static func load() -> [CleanupEvent] { (try? JSONDecoder().decode([CleanupEvent].self, from: Data(contentsOf: file))) ?? [] }
    static func save(_ history: [CleanupEvent]) { try? JSONEncoder().encode(Array(history.prefix(100))).write(to: file, options: .atomic) }
}

private enum SnapshotHistory {
    private static var file: URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "SpaceMinder")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "storage-snapshots.json")
    }
    static func load() -> [StorageSnapshot] { (try? JSONDecoder().decode([StorageSnapshot].self, from: Data(contentsOf: file))) ?? [] }
    static func save(_ snapshots: [StorageSnapshot]) { try? JSONEncoder().encode(Array(snapshots.prefix(60))).write(to: file, options: .atomic) }
}

private extension URL {
    func appending(path: String) -> URL { appendingPathComponent(path, isDirectory: true) }
}
