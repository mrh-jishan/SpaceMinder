import SwiftUI
import AppKit

private enum Workspace: String, CaseIterable, Identifiable {
    case dashboard, duplicates, reclaim, explorer, pro, preferences, privacy
    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject private var model: StorageViewModel
    @State private var destructiveRequest: DestructiveActionRequest?
    @State private var workspace: Workspace? = .dashboard

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $workspace, inspectFolder: inspectFolder)
        } detail: {
            Group {
                switch workspace ?? .dashboard {
                case .dashboard: dashboard
                case .duplicates: DiscoveryView(onOpenExplorer: { workspace = .explorer }, tool: .duplicates)
                case .reclaim: DiscoveryView(onOpenExplorer: { workspace = .explorer }, tool: .reclaim)
                case .explorer: FolderExplorerView()
                case .pro: ProWorkspaceView()
                case .preferences: PreferencesWorkspaceView()
                case .privacy: PrivacyWorkspaceView()
                }
            }
            .id(workspace?.id)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .animation(.spring(response: 0.32, dampingFraction: 0.88), value: workspace)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await model.scan() } } label: {
                    Label(model.isScanning ? "Scanning…" : "Scan now", systemImage: "arrow.clockwise")
                }
                .disabled(model.isScanning || model.isCleaning)
            }
        }
        .sheet(item: $destructiveRequest) { request in
            SafetyConfirmationSheet(request: request) { request.perform(); destructiveRequest = nil }
        }
        .alert("SpaceMinder", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK") { model.notice = nil }
        } message: {
            Text(model.notice ?? "")
        }
    }

    private var dashboard: some View {
        WorkspaceScrollPage {
            VStack(alignment: .leading, spacing: 24) {
                header
                StorageHero(volume: model.volume)
                PermissionCard()
                cleanupSection
                insightSection
                if !model.history.isEmpty { historySection }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func inspectFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a folder to inspect"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK, let url = panel.url else { return }
        workspace = .explorer
        Task { await model.inspectDirectory(url) }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Storage, understood.")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Private, local-first cleanup for your Mac. Nothing is uploaded.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("Duplicate Radar") { workspace = .duplicates }
                Button("Reclaim Planner") { workspace = .reclaim }
            } label: {
                Label("Discovery", systemImage: "sparkles")
            }
            .buttonStyle(.bordered)
            if model.isCleaning { ProgressView().controlSize(.small) }
        }
    }

    private var cleanupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Recommended cleanup").font(.title3.weight(.semibold))
                    Text("Select only data you are comfortable recreating.").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clean selected") {
                    let targets = model.cleanupTargets.filter { model.selected.contains($0.id) && $0.exists }
                    destructiveRequest = DestructiveActionRequest(
                        title: "Permanently remove selected storage?",
                        detail: "This permanently removes the exact selected cache, model, symbol, Trash, or Docker data. It cannot be recovered after the operation finishes.",
                        items: targets.map { "\($0.title) — \(ByteCountFormatter.string(fromByteCount: $0.bytes, countStyle: .file))" },
                        perform: { Task { await model.cleanSelected() } }
                    )
                }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.selected.isEmpty || model.isCleaning)
            }
            .padding(.bottom, 3)

            VStack(spacing: 8) {
                ForEach(model.cleanupTargets) { target in
                    CleanupRow(
                        target: target,
                        isSelected: model.selected.contains(target.id),
                        review: { inspectCleanupTarget(target) },
                        reveal: { model.reveal(target.url) }
                    ) {
                        if model.selected.contains(target.id) { model.selected.remove(target.id) }
                        else if target.exists { model.selected.insert(target.id) }
                    }
                }
            }
        }
    }

    private func inspectCleanupTarget(_ target: StorageTarget) {
        guard target.exists else { return }
        workspace = .explorer
        Task { await model.inspectDirectory(target.url) }
    }

    private var insightSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Space to review").font(.title3.weight(.semibold))
            Text("These locations may be large, but SpaceMinder deliberately leaves their data under your control. Some locations overlap, so do not add their totals together.")
                .font(.subheadline).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                ForEach(model.insightTargets) { target in
                    InsightCard(target: target, review: { inspectCleanupTarget(target) })
                }
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Recent cleanup").font(.title3.weight(.semibold))
            ForEach(model.history.prefix(3)) { item in
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(item.targets.joined(separator: ", "))
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: item.freedBytes, countStyle: .file)).monospacedDigit()
                    Text(item.date, style: .date).foregroundStyle(.secondary)
                }
                .font(.subheadline)
            }
        }
        .padding(.top, 8)
    }
}

struct DestructiveActionRequest: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let items: [String]
    let code: String
    let perform: () -> Void

    init(title: String, detail: String, items: [String], perform: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.items = items
        self.code = String(format: "%06d", Int.random(in: 0...999_999))
        self.perform = perform
    }
}

struct SafetyConfirmationSheet: View {
    let request: DestructiveActionRequest
    let confirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var typedCode = ""
    @FocusState private var codeFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Final safety check", systemImage: "exclamationmark.triangle.fill")
                .font(.headline).foregroundStyle(.orange)
            Text(request.title).font(.title2.weight(.bold))
            Text(request.detail).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text("Affected items").font(.subheadline.weight(.semibold))
                ForEach(request.items.prefix(8), id: \.self) { Text("• \($0)").font(.caption).foregroundStyle(.secondary) }
                if request.items.count > 8 { Text("• and \(request.items.count - 8) more item(s)").font(.caption).foregroundStyle(.secondary) }
            }
            .padding(12).background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 7) {
                Text("Type this generated code to authorize the operation:").font(.subheadline)
                Text(request.code).font(.system(.title3, design: .monospaced).weight(.bold)).textSelection(.enabled)
                TextField("Enter authorization code", text: $typedCode)
                    .textFieldStyle(.roundedBorder).focused($codeFocused)
            }
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Permanently continue", role: .destructive) { confirm() }
                    .buttonStyle(.borderedProminent)
                    .disabled(typedCode.trimmingCharacters(in: .whitespacesAndNewlines) != request.code)
            }
        }
        .padding(28)
        .frame(width: 560)
        .onAppear { codeFocused = true }
    }
}

struct WorkspaceScrollPage<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            let horizontal = min(max(CGFloat(20), proxy.size.width * 0.045), CGFloat(56))
            let vertical = min(max(CGFloat(20), proxy.size.height * 0.035), CGFloat(36))
            ScrollView {
                content()
                    .frame(maxWidth: 1220, alignment: .leading)
                    .padding(.horizontal, horizontal)
                    .padding(.vertical, vertical)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

private struct ProWorkspaceView: View {
    @EnvironmentObject private var model: StorageViewModel
    @AppStorage("spaceBudgetGigabytes") private var spaceBudgetGigabytes = 40.0

    private var budgetBytes: Int64 { Int64(spaceBudgetGigabytes * 1_073_741_824) }

    var body: some View {
        WorkspaceScrollPage {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 7) {
                    Label("Pro toolkit", systemImage: "crown.fill").font(.headline).foregroundStyle(.orange)
                    Text("Space Pulse").font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Persistent local storage history, a personal free-space budget, and attached-volume visibility. These tools are fully local and included while SpaceMinder is in preview.")
                        .foregroundStyle(.secondary)
                }
                budgetCard
                snapshotCard
                volumesCard
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var budgetCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Free-space budget").font(.title3.weight(.semibold))
                    Text("Set the amount of free storage you want to keep available.").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: budgetBytes, countStyle: .file)).font(.title3.weight(.bold)).monospacedDigit()
            }
            Slider(value: $spaceBudgetGigabytes, in: 10...150, step: 5)
            HStack {
                Label(model.volume.available >= budgetBytes ? "You are above your target" : "Below your target—review recommended cleanup", systemImage: model.volume.available >= budgetBytes ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(model.volume.available >= budgetBytes ? .green : .orange)
                Spacer()
                Text("Current free: \(ByteCountFormatter.string(fromByteCount: model.volume.available, countStyle: .file))").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var snapshotCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Space Pulse history").font(.title3.weight(.semibold))
            Text("A snapshot is recorded locally whenever SpaceMinder scans, making unexpected storage growth visible over time.").font(.subheadline).foregroundStyle(.secondary)
            if model.snapshots.isEmpty {
                Text("Your first scan will create a baseline.").foregroundStyle(.secondary).padding(.vertical, 8)
            } else {
                ForEach(model.snapshots.prefix(8)) { snapshot in
                    HStack {
                        Text(snapshot.date, style: .date)
                        Text(snapshot.date, style: .time).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(ByteCountFormatter.string(fromByteCount: snapshot.availableBytes, countStyle: .file)) free").monospacedDigit()
                        Text("\(ByteCountFormatter.string(fromByteCount: snapshot.recommendedBytes, countStyle: .file)) reclaimable").font(.caption).foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var volumesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Attached volumes").font(.title3.weight(.semibold))
            Text("External drives and mounted network locations can be selected in Folder Explorer for the same local analysis.").font(.subheadline).foregroundStyle(.secondary)
            ForEach(model.mountedVolumes) { volume in
                HStack {
                    Image(systemName: "externaldrive.fill").foregroundStyle(.indigo)
                    Text(volume.name).fontWeight(.medium)
                    Spacer()
                    Text("\(ByteCountFormatter.string(fromByteCount: volume.availableBytes, countStyle: .file)) free of \(ByteCountFormatter.string(fromByteCount: volume.totalBytes, countStyle: .file))").font(.caption).foregroundStyle(.secondary)
                    Button("Reveal") { model.reveal(volume.url) }.buttonStyle(.link)
                }
            }
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct Sidebar: View {
    @EnvironmentObject private var model: StorageViewModel
    @Binding var selection: Workspace?
    let inspectFolder: () -> Void
    var body: some View {
        List(selection: $selection) {
            Section {
                Label("Dashboard", systemImage: "internaldrive").tag(Workspace.dashboard)
            }
            Section("Workspaces") {
                Label("Duplicate Radar", systemImage: "doc.on.doc").tag(Workspace.duplicates)
                Label("Reclaim Planner", systemImage: "hammer").tag(Workspace.reclaim)
                Label("Folder Explorer", systemImage: "folder.badge.gearshape").tag(Workspace.explorer)
                Label("Pro toolkit", systemImage: "crown").tag(Workspace.pro)
            }
            Section("Tools") {
                Button(action: inspectFolder) { Label("Inspect folder", systemImage: "folder.badge.plus") }
                    .buttonStyle(.plain)
                Label("Preferences", systemImage: "gearshape").tag(Workspace.preferences)
            }
            Section("Privacy") {
                Label("Privacy & Permissions", systemImage: "lock.fill").tag(Workspace.privacy)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("SpaceMinder")
    }
}

private struct PreferencesWorkspaceView: View {
    @EnvironmentObject private var model: StorageViewModel
    var body: some View {
        WorkspaceScrollPage {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Preferences").font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Configure local behavior. SpaceMinder never cleans automatically.").foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 13) {
                    Text("Automation").font(.title3.weight(.semibold))
                    Toggle("Open SpaceMinder when I log in", isOn: $model.launchAtLogin)
                        .onChange(of: model.launchAtLogin) { _ in model.updateLoginItem() }
                    Text("Launch at login only opens the app; it never performs a cleanup without your confirmation.").font(.caption).foregroundStyle(.secondary)
                }
                .padding(20).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                VStack(alignment: .leading, spacing: 13) {
                    HStack { Text("Custom scan folders").font(.title3.weight(.semibold)); Spacer(); Button("Add folder…") { model.addCustomPath() } }
                    Text("Custom locations are analysis-only. Use Folder Explorer when you intentionally want to manage their contents.").font(.subheadline).foregroundStyle(.secondary)
                    ForEach(model.customPaths, id: \.self) { url in
                        HStack { Image(systemName: "folder.fill").foregroundStyle(.indigo); Text(url.path).lineLimit(1); Spacer(); Button("Remove") { model.customPaths.removeAll { $0 == url }; Task { await model.scan() } }.buttonStyle(.link) }
                    }
                }
                .padding(20).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct PrivacyWorkspaceView: View {
    @EnvironmentObject private var model: StorageViewModel
    var body: some View {
        WorkspaceScrollPage {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Privacy & Permissions").font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("Your file names, sizes, duplicate hashes, and cleanup history stay on this Mac.").foregroundStyle(.secondary)
                }
                PermissionCard()
                VStack(alignment: .leading, spacing: 11) {
                    Label("No network service", systemImage: "network.slash").font(.headline)
                    Text("SpaceMinder has no account, analytics, server, or upload path. Duplicate hashes are calculated locally and are never transmitted.").foregroundStyle(.secondary)
                    Label("Your approval is required", systemImage: "hand.raised.fill").font(.headline).padding(.top, 5)
                    Text("The app uses a fixed cleanup allow-list. Folder Explorer moves selected local files to Trash; it never deletes arbitrary files automatically. iCloud offloading keeps cloud originals.").foregroundStyle(.secondary)
                    Label("Why Full Disk Access is optional", systemImage: "lock.shield.fill").font(.headline).padding(.top, 5)
                    Text("Apple requires each person to enable Full Disk Access themselves after installation. It cannot be granted by a DMG or installer, which protects Mail, Messages, and other sensitive data.").foregroundStyle(.secondary)
                }
                .padding(20).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct StorageHero: View {
    let volume: VolumeStatus
    var body: some View {
        HStack(spacing: 28) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 14)
                Circle().trim(from: 0, to: volume.usedFraction).stroke(volume.usedFraction > 0.85 ? .red : .indigo, style: .init(lineWidth: 14, lineCap: .round)).rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text("\(Int(volume.usedFraction * 100))%") .font(.title2.weight(.bold)).monospacedDigit()
                    Text("used").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 118, height: 118)
            VStack(alignment: .leading, spacing: 7) {
                Text("\(ByteCountFormatter.string(fromByteCount: volume.available, countStyle: .file)) free")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                Text("of \(ByteCountFormatter.string(fromByteCount: volume.total, countStyle: .file)) total storage")
                    .foregroundStyle(.secondary)
                ProgressView(value: volume.usedFraction).tint(volume.usedFraction > 0.85 ? .red : .indigo).frame(width: 350)
            }
            Spacer()
            Label("On this Mac", systemImage: "macbook")
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .background(.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct CleanupRow: View {
    let target: StorageTarget
    let isSelected: Bool
    let review: () -> Void
    let reveal: () -> Void
    let toggle: () -> Void
    var body: some View {
        HStack(spacing: 14) {
            Button(action: toggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(isSelected ? Color.indigo : Color.secondary.opacity(0.55))
            }
            .padding(15)
            .buttonStyle(.plain)
            .disabled(!target.exists)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(target.title).fontWeight(.semibold)
                    Text(target.safety.rawValue.uppercased()).font(.caption2.weight(.bold)).padding(.horizontal, 6).padding(.vertical, 3).background(target.safety.tint.opacity(0.16), in: Capsule()).foregroundStyle(target.safety.tint)
                }
                Text(target.detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                if !target.appsToQuit.isEmpty { Text("Quit \(target.appsToQuit.joined(separator: " and ")) first").font(.caption).foregroundStyle(.orange) }
            }
            Spacer()
            Text(target.exists ? ByteCountFormatter.string(fromByteCount: target.bytes, countStyle: .file) : "Not found")
                .font(.system(.body, design: .monospaced).weight(.semibold)).foregroundStyle(target.exists ? .primary : .tertiary)
            Button("Review", action: review).buttonStyle(.link).disabled(!target.exists)
            Button(action: reveal) { Image(systemName: "arrow.up.forward.app") }
                .buttonStyle(.plain)
                .help("Reveal in Finder")
                .disabled(!target.exists)
        }
        .padding(.horizontal, 15).padding(.vertical, 9)
        .background(isSelected ? .indigo.opacity(0.09) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(isSelected ? Color.indigo.opacity(0.35) : Color.gray.opacity(0.22), lineWidth: 1))
    }
}

private struct InsightCard: View {
    @EnvironmentObject private var model: StorageViewModel
    let target: StorageTarget
    let review: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { Image(systemName: "folder").foregroundStyle(.indigo); Spacer(); Text(ByteCountFormatter.string(fromByteCount: target.bytes, countStyle: .file)).font(.caption.weight(.semibold)).monospacedDigit() }
            Text(target.title).fontWeight(.semibold)
            Text(target.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Review", action: review).buttonStyle(.link).font(.caption)
                Spacer()
                Button(action: { model.reveal(target.url) }) { Image(systemName: "arrow.up.forward.app") }
                    .buttonStyle(.plain)
                    .help("Reveal in Finder")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
