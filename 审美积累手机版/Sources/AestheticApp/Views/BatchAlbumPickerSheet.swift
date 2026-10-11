import SwiftUI

/// 批量把多张照片加入 / 移出册子，并支持新建册子
struct BatchAlbumPickerSheet: View {
    let photoIDs: [String]
    var onDone: () -> Void = {}
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var showNewAlbum = false
    @State private var newAlbumName = ""

    var body: some View {
        NavigationStack {
            Group {
                if store.library.albums.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 40))
                            .foregroundColor(AppTheme.secondaryText)
                        Text("还没有册子，点右上角「＋」新建")
                            .font(.callout)
                            .foregroundColor(AppTheme.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                } else {
                    List {
                        ForEach(store.library.albums) { album in
                            let allIn = photoIDs.allSatisfy { album.photoIds.contains($0) }
                            Button {
                                store.setPhotos(photoIDs, in: album.id, to: !allIn)
                            } label: {
                                HStack {
                                    Image(systemName: allIn ? "checkmark.square.fill" : "square")
                                    Text(album.name)
                                    Spacer()
                                }
                            }
                            .foregroundColor(AppTheme.primaryText)
                        }
                    }
                }
            }
            .navigationTitle("加入册子（\(photoIDs.count) 张）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showNewAlbum = true } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                        onDone()
                    }
                }
            }
            .alert("新建册子", isPresented: $showNewAlbum) {
                TextField("册子名称", text: $newAlbumName)
                Button("创建") {
                    let name = newAlbumName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        let album = store.addAlbum(name: name)
                        store.setPhotos(photoIDs, in: album.id, to: true)
                        newAlbumName = ""
                    }
                }
                Button("取消", role: .cancel) { newAlbumName = "" }
            }
        }
    }
}
