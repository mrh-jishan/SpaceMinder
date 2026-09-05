import SwiftUI
import AppKit

struct PermissionCard: View {
    @EnvironmentObject private var model: StorageViewModel

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: model.protectedLocationsAvailable ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                .font(.title2)
                .foregroundStyle(model.protectedLocationsAvailable ? .green : .orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.protectedLocationsAvailable ? "Full scan access is available" : "Optional: enable Full Disk Access")
                    .fontWeight(.semibold)
                Text(model.protectedLocationsAvailable ? "SpaceMinder can include protected app data in its storage measurements." : "macOS is limiting protected app-data measurements. Enable this only if you want a more complete system-wide scan.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !model.protectedLocationsAvailable {
                Button("Open Privacy Settings") { model.openFullDiskAccess() }
                    .buttonStyle(.bordered)
            } else {
                Button("Refresh") { model.refreshPermissionStatus() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(15)
        .background(.orange.opacity(model.protectedLocationsAvailable ? 0.04 : 0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct DiscoveryView: View {
    @EnvironmentObject private var model: StorageViewModel
    let onOpenExplorer: () -> Void
    @State private var folders = DiscoveryView.defaultFolders

    private static var defaultFolders: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ["Desktop", "Downloads", "Documents"].map { home.appendingPathComponent($0) }
    }

    var body: some View {
        WorkspaceScrollPage {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Discovery Lab").font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Find exact duplicates using a two-pass, local-only scan.").foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onOpenExplorer) { Label("Folder Explorer", systemImage: "folder.badge.gearshape") }
                    .buttonStyle(.bordered)
                }
                scanControl
                developerPlanner
                results
                privacyNote
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var scanControl: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Duplicate radar").font(.title3.weight(.semibold))
                    Text("First groups files by size; only equal-size files are SHA-256 hashed. This avoids needless reads and keeps memory use low.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button { chooseFolders() } label: { Label("Add folder", systemImage: "folder.badge.plus") }
                Button { Task { await model.scanDuplicates(in: folders) } } label: {
                    Label(model.isScanningDuplicates ? "Scanning…" : "Scan for duplicates", systemImage: "waveform.path.ecg")
                }
                .buttonStyle(.borderedProminent)
                .disabled(folders.isEmpty || model.isScanningDuplicates)
            }
            FlowLayout(spacing: 8) {
                ForEach(folders, id: \.path) { folder in
                    HStack(spacing: 5) {
                        Image(systemName: "folder.fill").foregroundStyle(.indigo)
                        Text(folder.lastPathComponent)
                        Button { folders.removeAll { $0 == folder } } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(.quaternary, in: Capsule())
                }
            }
            Text(model.duplicateStatus).font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.indigo.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder private var results: some View {
        if model.duplicateGroups.isEmpty && !model.isScanningDuplicates {
            VStack(spacing: 10) {
                Image(systemName: "doc.on.doc").font(.system(size: 35)).foregroundStyle(.secondary)
                Text("No duplicate results yet").font(.headline)
                Text("Choose folders and scan. Files smaller than 1 MB are skipped to keep the scan focused.").font(.subheadline).foregroundStyle(.secondary)
            }
                .frame(maxWidth: .infinity, minHeight: 230)
        } else {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Exact duplicate sets").font(.title3.weight(.semibold))
                    Text("Potential reclaimable space assumes you keep one copy in each set.").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: model.duplicateReclaimableBytes, countStyle: .file))
                    .font(.title2.weight(.bold)).monospacedDigit()
            }
            ForEach(model.duplicateGroups.prefix(30)) { group in
                DuplicateGroupCard(group: group)
            }
        }
    }

    private var privacyNote: some View {
        Label("Duplicate radar runs entirely on your Mac. It never uploads file names, paths, contents, or hashes, and it cannot delete anything.", systemImage: "lock.fill")
            .font(.caption).foregroundStyle(.secondary)
            .padding(.top, 5)
    }

    private var developerPlanner: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Developer Reclaim Planner", systemImage: "hammer.fill").font(.title3.weight(.semibold))
                    Text("Find generated dependencies and build output that can be recreated from a project’s source files. Nothing is removed automatically.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button { Task { await model.scanDeveloperArtifacts(in: folders) } } label: {
                    Label(model.isScanningDeveloperArtifacts ? "Scanning…" : "Find project artifacts", systemImage: "magnifyingglass")
                }
                .buttonStyle(.bordered)
                .disabled(folders.isEmpty || model.isScanningDeveloperArtifacts)
            }
            Text(model.developerArtifactStatus).font(.caption).foregroundStyle(.secondary)
            if !model.developerArtifacts.isEmpty {
                let total = model.developerArtifacts.reduce(Int64(0)) { $0 + $1.bytes }
                HStack { Text("Potentially re-creatable").font(.caption.weight(.semibold)); Spacer(); Text(ByteCountFormatter.string(fromByteCount: total, countStyle: .file)).font(.caption.weight(.bold)).monospacedDigit() }
                ForEach(model.developerArtifacts.prefix(12)) { artifact in
                    HStack(spacing: 9) {
                        Image(systemName: "cube.transparent.fill").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(artifact.url.lastPathComponent).fontWeight(.medium)
                            Text("\(artifact.category) · \(artifact.url.deletingLastPathComponent().path)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: artifact.bytes, countStyle: .file)).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        Button("Inspect") { Task { await model.inspectDirectory(artifact.url); onOpenExplorer() } }.buttonStyle(.link)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(20)
        .background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func chooseFolders() {
        let panel = NSOpenPanel()
        panel.title = "Choose folders to inspect for duplicates"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        if panel.runModal() == .OK {
            folders = Array(Set(folders + panel.urls)).sorted { $0.path < $1.path }
        }
    }
}

struct FolderExplorerView: View {
    @EnvironmentObject private var model: StorageViewModel
    @State private var selected = Set<String>()
    @State private var confirmTrash = false

    private var inventory: DirectoryInventory? { model.inventory }
    private var selectedEntries: [DirectoryEntry] { inventory?.entries.filter { selected.contains($0.id) } ?? [] }
    private var localEntries: [DirectoryEntry] { selectedEntries.filter { !$0.isICloud } }
    private var iCloudEntries: [DirectoryEntry] { selectedEntries.filter { $0.isICloud && $0.isDownloaded } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Folder Explorer").font(.system(size: 27, weight: .bold, design: .rounded))
                    Text("Measure and act on exactly what is inside a folder—no guesswork.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Choose folder…") { chooseRoot() }
            }
            .padding(.horizontal, 32).padding(.vertical, 26)
            Divider()
            if !model.mountedVolumes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Text("Volumes").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(model.mountedVolumes) { volume in
                            Button {
                                selected.removeAll()
                                Task { await model.inspectDirectory(volume.url) }
                            } label: {
                                Label(volume.name, systemImage: "externaldrive.fill")
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 9).padding(.vertical, 6)
                                    .background(.quaternary, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 28).padding(.vertical, 10)
                }
                Divider()
            }
            if let inventory {
                explorer(inventory)
            } else {
                ProgressView("Loading folder inventory…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .task { await model.inspectDirectory(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")) }
            }
        }
        .frame(minWidth: 920, minHeight: 640)
        .confirmationDialog("Move selected local items to Trash?", isPresented: $confirmTrash, titleVisibility: .visible) {
            Button("Move \(localEntries.count) item(s) to Trash", role: .destructive) { model.trash(localEntries); selected.removeAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This is reversible until Trash is emptied. iCloud items are excluded, so cloud originals are never deleted by this action.")
        }
    }

    @ViewBuilder private func explorer(_ inventory: DirectoryInventory) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button { openParent(of: inventory.root) } label: { Image(systemName: "chevron.left") }
                    .disabled(inventory.root.path == FileManager.default.homeDirectoryForCurrentUser.path)
                Image(systemName: "folder.fill").foregroundStyle(.indigo)
                Text(inventory.root.path).font(.subheadline.monospaced()).lineLimit(1)
                Spacer()
                if model.isInspectingDirectory { ProgressView().controlSize(.small) }
                Button { Task { await model.inspectDirectory(inventory.root) } } label: { Image(systemName: "arrow.clockwise") }
            }
            .padding(.horizontal, 28).padding(.vertical, 14)
            .background(.quaternary.opacity(0.5))

            HStack(spacing: 10) {
                Text("\(inventory.entries.count) direct items · \(inventory.scannedFiles.formatted()) files measured in one pass").font(.caption).foregroundStyle(.secondary)
                if inventory.inaccessibleItems > 0 { Text("\(inventory.inaccessibleItems) protected item(s) skipped").font(.caption).foregroundStyle(.orange) }
                if inventory.wasCapped { Text("Scan capped at 150,000 files—choose a narrower folder for complete results.").font(.caption).foregroundStyle(.orange) }
                Spacer()
                if !iCloudEntries.isEmpty {
                    Button("Remove local iCloud copies") { model.removeLocalICloudCopies(iCloudEntries); selected.removeAll() }
                        .buttonStyle(.bordered)
                }
                Button("Move local items to Trash") { confirmTrash = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(localEntries.isEmpty)
            }
            .padding(.horizontal, 28).padding(.vertical, 13)

            List(inventory.entries, selection: $selected) { entry in
                HStack(spacing: 10) {
                    Image(systemName: entry.isDirectory ? "folder.fill" : (entry.isICloud ? "icloud.fill" : "doc.fill"))
                        .foregroundStyle(entry.isICloud ? .blue : .indigo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.url.lastPathComponent).lineLimit(1)
                        if entry.isICloud { Text(entry.isDownloaded ? "iCloud: stored locally" : "iCloud: online only").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: entry.bytes, countStyle: .file)).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                    if entry.isDirectory { Button("Open") { selected.removeAll(); Task { await model.inspectDirectory(entry.url) } }.buttonStyle(.link) }
                    Button("Reveal") { model.reveal(entry.url) }.buttonStyle(.link)
                }
                .tag(entry.id)
            }
            .listStyle(.inset)
        }
    }

    private func chooseRoot() {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder to inspect"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        if panel.runModal() == .OK, let url = panel.url { selected.removeAll(); Task { await model.inspectDirectory(url) } }
    }

    private func openParent(of root: URL) {
        selected.removeAll()
        Task { await model.inspectDirectory(root.deletingLastPathComponent()) }
    }
}

private struct DuplicateGroupCard: View {
    @EnvironmentObject private var model: StorageViewModel
    let group: DuplicateGroup

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(group.files) { file in
                    HStack(spacing: 9) {
                        Image(systemName: "doc.fill").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(file.url.lastPathComponent).lineLimit(1)
                            Text(file.url.deletingLastPathComponent().path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button("Reveal") { model.reveal(file.url) }.buttonStyle(.link)
                    }
                    .font(.subheadline)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Image(systemName: "doc.on.doc.fill").foregroundStyle(.indigo)
                Text("\(group.files.count) identical copies").fontWeight(.semibold)
                Spacer()
                Text("\(ByteCountFormatter.string(fromByteCount: group.bytesPerFile, countStyle: .file)) each").foregroundStyle(.secondary)
                Text("reclaim \(ByteCountFormatter.string(fromByteCount: group.reclaimableBytes, countStyle: .file))").font(.caption.weight(.semibold)).foregroundStyle(.green)
            }
        }
        .padding(15)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .greatestFiniteMagnitude
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? 0, height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var point = bounds.origin
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if point.x + size.width > bounds.maxX, point.x > bounds.minX {
                point.x = bounds.minX
                point.y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: point, proposal: ProposedViewSize(size))
            point.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
