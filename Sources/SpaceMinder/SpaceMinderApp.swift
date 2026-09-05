import SwiftUI
import AppKit
import ServiceManagement

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
        .init(id: "docker-disk", title: "Docker virtual disk", detail: "All local Docker images, containers, volumes, and build cache.", url: home("Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"), kind: .file, safety: .destructive, appsToQuit: ["Docker"])
    ]

    static let insights: [StorageTarget] = [
        .init(id: "simulators", title: "Xcode simulators", detail: "Remove unused devices in Xcode → Window → Devices and Simulators.", url: home("Library/Developer/CoreSimulator"), kind: .directory, safety: .redownloadable, appsToQuit: ["Xcode"]),
        .init(id: "pnpm", title: "pnpm store", detail: "Run `pnpm store prune` to remove unreferenced package versions.", url: home("Library/pnpm"), kind: .directory, safety: .safe, appsToQuit: []),
        .init(id: "chrome-profile", title: "Chrome profile", detail: "Clear browser cache in Chrome; SpaceMinder never deletes profile data.", url: home("Library/Application Support/Google/Chrome"), kind: .directory, safety: .safe, appsToQuit: []),
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
    @AppStorage("launchAtLogin") var launchAtLogin = false
    @AppStorage("customScanPaths") private var customScanPathsData = Data()

    private let scanner = LocalStorageScanner()
    private let cleaner = SafeCleaner()

    init() {
        history = CleanupHistory.load()
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
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [.skipsPackageDescendants, .skipsHiddenFiles], errorHandler: { _, _ in true }) else { return 0 }
        for case let item as URL in enumerator {
            guard let values = try? item.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
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
