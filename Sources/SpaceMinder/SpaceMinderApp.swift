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
        .init(id: "huggingface-cache", title: "Hugging Face models", detail: "Downloaded AI models. They will download again if used.", url: home(".cache/huggingface"), kind: .directory, safety: .redownloadable, appsToQuit: []),
        .init(id: "xcode-device-support", title: "Xcode iOS DeviceSupport", detail: "Device symbols used to debug connected iPhones and iPads.", url: home("Library/Developer/Xcode/iOS DeviceSupport"), kind: .directory, safety: .redownloadable, appsToQuit: ["Xcode"]),
        .init(id: "chrome-ai-model", title: "Chrome on-device AI model", detail: "Downloaded model only; bookmarks, passwords, and history stay intact.", url: home("Library/Application Support/Google/Chrome/OptGuideOnDeviceModel"), kind: .directory, safety: .redownloadable, appsToQuit: ["Google Chrome"]),
        .init(id: "trash", title: "Trash", detail: "Items already marked for deletion. Empty it only after reviewing its contents.", url: home(".Trash"), kind: .contents, safety: .safe, appsToQuit: []),
        .init(id: "docker-disk", title: "Docker virtual disk", detail: "All local Docker images, containers, volumes, and build cache.", url: home("Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"), kind: .file, safety: .destructive, appsToQuit: ["Docker"])
    ]

    static let insights: [StorageTarget] = [
        .init(id: "simulators", title: "Xcode simulators", detail: "Remove unused devices in Xcode → Window → Devices and Simulators.", url: home("Library/Developer/CoreSimulator"), kind: .directory, safety: .redownloadable, appsToQuit: ["Xcode"]),
        .init(id: "pnpm", title: "pnpm store", detail: "Run `pnpm store prune` to remove unreferenced package versions.", url: home("Library/pnpm"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "chrome-profile", title: "Chrome profile", detail: "Clear browser cache in Chrome; SpaceMinder never deletes profile data.", url: home("Library/Application Support/Google/Chrome"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "icloud-drive", title: "iCloud Drive local copies", detail: "Inspect downloaded copies and remove local downloads while keeping iCloud originals.", url: home("Library/Mobile Documents/com~apple~CloudDocs"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "downloads", title: "Downloads", detail: "Review installers, archives, and duplicate exports manually.", url: home("Downloads"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "desktop", title: "Desktop projects", detail: "Dormant development projects may contain re-creatable dependencies and build output.", url: home("Desktop"), kind: .directory, safety: .safe, appsToQuit: [])
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

struct DuplicateFile: Identifiable, Hashable {
    let url: URL
    let bytes: Int64
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
    var id: String { url.path }
}

struct DirectoryInventory: Sendable {
    let root: URL
    let entries: [DirectoryEntry]
    let inaccessibleItems: Int
}

@MainActor
final class StorageViewModel: ObservableObject {
    @Published private(set) var volume = VolumeStatus(total: 0, available: 0)
    @Published private(set) var cleanupTargets = StorageTarget.cleanup
    @Published private(set) var insightTargets = StorageTarget.insights
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
    @AppStorage("launchAtLogin") var launchAtLogin = false
    @AppStorage("customScanPaths") private var customScanPathsData = Data()

    private let scanner = LocalStorageScanner()
    private let cleaner = SafeCleaner()

    init() {
        history = CleanupHistory.load()
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
        volume = result.volume
        cleanupTargets = result.cleanup
        insightTargets = result.insights
        selected = selected.intersection(Set(result.cleanup.filter(\.exists).map(\.id)))
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

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openFullDiskAccess() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }

    func refreshPermissionStatus() {
        protectedLocationsAvailable = PermissionProbe.canReadProtectedLocations()
    }

    func inspectDirectory(_ url: URL) async {
        isInspectingDirectory = true
        let result = await Task.detached(priority: .userInitiated) { DirectoryInspector.inspect(url) }.value
        inventory = result
        isInspectingDirectory = false
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
    /// This touches metadata only. macOS returns false without Full Disk Access
    /// for protected user data such as Messages/Mail on a typical installation.
    static func canReadProtectedLocations() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let probes = [home.appendingPathComponent("Library/Mail"), home.appendingPathComponent("Library/Messages")]
        return probes.contains { FileManager.default.isReadableFile(atPath: $0.path) }
    }
}

private enum DuplicateFinder {
    static func find(in folders: [URL], maxFiles: Int = 30_000, minimumBytes: Int64 = 1_048_576) -> DuplicateScanResult {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .fileAllocatedSizeKey]
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
                byDigest[digest, default: []].append(DuplicateFile(url: file, bytes: bytes))
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
    static func inspect(_ root: URL) -> DirectoryInventory {
        let manager = FileManager.default
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .fileSizeKey]
        var inaccessible = 0
        let urls = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys), options: [])) ?? []
        let entries = urls.compactMap { url -> DirectoryEntry? in
            guard let values = try? url.resourceValues(forKeys: keys) else { inaccessible += 1; return nil }
            let directory = values.isDirectory == true
            let bytes = directory ? recursiveAllocatedSize(url, keys: keys, inaccessible: &inaccessible) : Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
            return DirectoryEntry(url: url, bytes: bytes, isDirectory: directory, isICloud: values.isUbiquitousItem == true, isDownloaded: values.ubiquitousItemDownloadingStatus == .current)
        }
        return DirectoryInventory(root: root, entries: entries.sorted { $0.bytes > $1.bytes }, inaccessibleItems: inaccessible)
    }

    private static func recursiveAllocatedSize(_ root: URL, keys: Set<URLResourceKey>, inaccessible: inout Int) -> Int64 {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let item as URL in enumerator {
            guard let values = try? item.resourceValues(forKeys: keys) else { inaccessible += 1; continue }
            guard values.isDirectory != true else { continue }
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

private extension URL {
    func appending(path: String) -> URL { appendingPathComponent(path, isDirectory: true) }
}
