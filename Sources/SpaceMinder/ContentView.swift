import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var model: StorageViewModel
    @State private var showConfirmation = false

    var body: some View {
        NavigationSplitView {
            Sidebar()
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    StorageHero(volume: model.volume)
                    cleanupSection
                    insightSection
                    if !model.history.isEmpty { historySection }
                }
                .padding(32)
                .frame(maxWidth: 1120, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await model.scan() } } label: {
                    Label(model.isScanning ? "Scanning…" : "Scan now", systemImage: "arrow.clockwise")
                }
                .disabled(model.isScanning || model.isCleaning)
            }
        }
        .confirmationDialog("Permanently remove selected items?", isPresented: $showConfirmation, titleVisibility: .visible) {
            Button("Clean \(ByteCountFormatter.string(fromByteCount: model.selectedBytes, countStyle: .file))", role: .destructive) {
                Task { await model.cleanSelected() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("SpaceMinder only removes the exact folders and files selected below. This cannot be undone.")
        }
        .alert("SpaceMinder", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK") { model.notice = nil }
        } message: {
            Text(model.notice ?? "")
        }
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
                Button("Clean selected") { showConfirmation = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.selected.isEmpty || model.isCleaning)
            }
            .padding(.bottom, 3)

            VStack(spacing: 8) {
                ForEach(model.cleanupTargets) { target in
                    CleanupRow(target: target, isSelected: model.selected.contains(target.id)) {
                        if model.selected.contains(target.id) { model.selected.remove(target.id) }
                        else if target.exists { model.selected.insert(target.id) }
                    }
                }
            }
        }
    }

    private var insightSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Space to review").font(.title3.weight(.semibold))
            Text("These locations may be large, but SpaceMinder deliberately leaves their data under your control.")
                .font(.subheadline).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                ForEach(model.insightTargets) { target in InsightCard(target: target) }
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

private struct Sidebar: View {
    @EnvironmentObject private var model: StorageViewModel
    var body: some View {
        List {
            Section {
                Label("Dashboard", systemImage: "internaldrive")
                    .fontWeight(.semibold)
            }
            Section("Tools") {
                Button { model.addCustomPath() } label: { Label("Inspect folder", systemImage: "folder.badge.plus") }
                    .buttonStyle(.plain)
                Button { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) } label: { Label("Preferences", systemImage: "gearshape") }
                    .buttonStyle(.plain)
            }
            Section("Privacy") {
                Label("Local analysis only", systemImage: "lock.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("SpaceMinder")
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
    let toggle: () -> Void
    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(isSelected ? Color.indigo : Color.secondary.opacity(0.55))
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
            }
            .padding(15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!target.exists)
        .background(isSelected ? .indigo.opacity(0.09) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(isSelected ? Color.indigo.opacity(0.35) : Color.gray.opacity(0.22), lineWidth: 1))
    }
}

private struct InsightCard: View {
    let target: StorageTarget
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack { Image(systemName: "folder").foregroundStyle(.indigo); Spacer(); Text(ByteCountFormatter.string(fromByteCount: target.bytes, countStyle: .file)).font(.caption.weight(.semibold)).monospacedDigit() }
            Text(target.title).fontWeight(.semibold)
            Text(target.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
