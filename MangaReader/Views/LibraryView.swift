import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if model.items.isEmpty {
                    ContentUnavailableView(
                        "MangaReader",
                        systemImage: "books.vertical",
                        description: Text("Put manga folders or archives in the app's Documents folder.")
                    )
                } else {
                    List {
                        ForEach(model.children(of: nil)) { item in
                            NavigationLink(value: item) {
                                LibraryRow(item: item)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("MangaReader")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .navigationDestination(for: LibraryItem.self) { item in
                destination(for: item)
            }
            .refreshable {
                await model.scanLibrary()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { model.errorMessage != nil },
                    set: { if !$0 { model.errorMessage = nil } }
                )
            ) {
                Button("OK") { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private func destination(for item: LibraryItem) -> some View {
        switch item.kind {
        case .collection:
            FolderView(parent: item)
        case .mixed:
            MixedResolutionView(item: item)
        default:
            ReaderView(item: item)
        }
    }
}

struct FolderView: View {
    @EnvironmentObject private var model: AppModel
    let parent: LibraryItem

    var body: some View {
        Group {
            if model.children(of: parent.relativePath).isEmpty {
                ContentUnavailableView(
                    "Empty Folder",
                    systemImage: "folder",
                    description: Text("No books inside this folder.")
                )
            } else {
                List {
                    ForEach(model.children(of: parent.relativePath)) { item in
                        NavigationLink(value: item) {
                            LibraryRow(item: item)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(parent.title)
        .navigationDestination(for: LibraryItem.self) { item in
            switch item.kind {
            case .collection:
                FolderView(parent: item)
            case .mixed:
                MixedResolutionView(item: item)
            default:
                ReaderView(item: item)
            }
        }
        .refreshable {
            await model.scanLibrary()
        }
    }
}

struct LibraryRow: View {
    @EnvironmentObject private var model: AppModel
    let item: LibraryItem

    @State private var showRename = false
    @State private var showMove = false
    @State private var showCopy = false
    @State private var showCoverPicker = false
    @State private var showMixedResolution = false
    @State private var confirmDelete = false

    var body: some View {
        HStack(spacing: 12) {
            BookCoverView(item: item, coverService: model.coverService)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .lineLimit(2)
                Text(kindLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            menuItems
        }
        .sheet(isPresented: $showRename) {
            RenameSheet(item: item)
        }
        .sheet(isPresented: $showMove) {
            DestinationPickerSheet(item: item, operation: .move)
        }
        .sheet(isPresented: $showCopy) {
            DestinationPickerSheet(item: item, operation: .copy)
        }
        .sheet(isPresented: $showCoverPicker) {
            CoverPickerView(item: item)
        }
        .sheet(isPresented: $showMixedResolution) {
            MixedResolutionView(item: item)
        }
        .confirmationDialog("Delete \(item.title)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await model.fileOperations.delete(item)
                        await model.scanLibrary()
                    } catch {
                        model.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var menuItems: some View {
        Button {
            showCoverPicker = true
        } label: {
            Label("Custom Cover", systemImage: "photo.badge.plus")
        }

        if item.kind == .archive {
            Button {
                Task {
                    do {
                        _ = try await model.fileOperations.extractArchive(item)
                        await model.scanLibrary()
                    } catch {
                        model.errorMessage = error.localizedDescription
                    }
                }
            } label: {
                Label("Extract to Folder", systemImage: "folder.badge.gearshape")
            }
        }

        if item.kind == .mixed {
            Button {
                showMixedResolution = true
            } label: {
                Label("Resolve Mixed Folder", systemImage: "questionmark.folder")
            }
        }

        if !item.isVirtual {
            Button {
                showRename = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                showMove = true
            } label: {
                Label("Move", systemImage: "folder")
            }
            Button {
                showCopy = true
            } label: {
                Label("Copy", systemImage: "plus.square.on.square")
            }
        }

        Button(role: .destructive) {
            confirmDelete = true
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private var kindLabel: String {
        switch item.kind {
        case .bookFolder:
            return item.isVirtual ? "Folder images" : "Folder book"
        case .archive:
            return "Archive"
        case .collection:
            return "Folder"
        case .mixed:
            return "Mixed folder"
        case .model, .unknown:
            return "Other"
        }
    }
}
