import SwiftUI

enum AlbumEdit: Identifiable {
    case create
    case rename(Album)
    var id: String {
        switch self {
        case .create: return "create"
        case .rename(let a): return "rename-\(a.id)"
        }
    }
}

/// 册子管理：封面/名称/数量/创建时间、选择、新建、重命名、删除
struct AlbumSheet: View {
    @Binding var selectedAlbumID: String?
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var edit: AlbumEdit?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        selectedAlbumID = nil
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "photo.on.rectangle")
                            Text("全部素材")
                            Spacer()
                            Text("\(store.library.photos.count)")
                                .foregroundColor(AppTheme.secondaryText)
                        }
                    }
                    .foregroundColor(AppTheme.primaryText)
                }
                Section("册子") {
                    ForEach(store.library.albums) { album in
                        Button {
                            selectedAlbumID = album.id
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                coverImage(for: album)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(album.name)
                                    Text("\(album.photoIds.count) 张 · \(album.createdAt.formatted(.dateTime.year().month().day()))")
                                        .font(.caption2)
                                        .foregroundColor(AppTheme.secondaryText)
                                }
                                Spacer()
                            }
                        }
                        .foregroundColor(AppTheme.primaryText)
                        .swipeActions {
                            Button("重命名") { edit = .rename(album) }
                            Button("删除", role: .destructive) {
                                store.deleteAlbum(id: album.id)
                                if selectedAlbumID == album.id { selectedAlbumID = nil }
                            }
                        }
                    }
                }
            }
            .navigationTitle("册子")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { edit = .create } label: { Image(systemName: "plus") }
                }
            }
            .sheet(item: $edit) { e in
                AlbumNameSheet(edit: e)
            }
        }
    }

    private func coverImage(for album: Album) -> some View {
        Group {
            if let img = coverUIImage(for: album) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(AppTheme.divider)
                    Image(systemName: "folder").foregroundColor(AppTheme.secondaryText)
                }
            }
        }
        .frame(width: 44, height: 44)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func coverUIImage(for album: Album) -> UIImage? {
        let id = album.coverPhotoId ?? album.photoIds.first
        guard let id, let photo = store.library.photos.first(where: { $0.id == id }) else { return nil }
        return store.uiImage(for: photo)
    }
}

/// 新建 / 重命名册子
struct AlbumNameSheet: View {
    let edit: AlbumEdit
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(edit: AlbumEdit) {
        self.edit = edit
        switch edit {
        case .create: _name = State(initialValue: "")
        case .rename(let album): _name = State(initialValue: album.name)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField("册子名称", text: $name)
                    .textFieldStyle(.roundedBorder)
                Button {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    switch edit {
                    case .create: store.addAlbum(name: trimmed)
                    case .rename(let album): store.renameAlbum(id: album.id, to: trimmed)
                    }
                    dismiss()
                } label: {
                    Text("确定")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.primaryText)
                Spacer()
            }
            .padding(16)
            .navigationTitle(edit.id == "create" ? "新建册子" : "重命名")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}
