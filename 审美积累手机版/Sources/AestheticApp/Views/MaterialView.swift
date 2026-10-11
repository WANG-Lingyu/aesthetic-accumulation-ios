import SwiftUI

struct DateGroup: Identifiable {
    let date: Date
    let label: String
    var photos: [Photo]
    var id: Date { date }
}

/// 素材页：册子 + 照片网格 + 搜索 + 多选 + 拖拽排序（全部素材按日期分组）
struct MaterialView: View {
    @EnvironmentObject var store: LibraryStore
    @State private var selectedAlbumID: String?
    @State private var showAlbums = false
    @State private var searchText = ""
    @State private var isSelecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var showBatchAlbum = false
    @State private var dragPhotoID: String?
    @State private var dragTranslation: CGSize = .zero
    @State private var dragStartIndex: Int?
    @State private var currentDate: Date?

    private let columns = [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)]

    private var photos: [Photo] {
        var result: [Photo]
        if let selectedAlbumID, let album = store.library.albums.first(where: { $0.id == selectedAlbumID }) {
            let set = Set(album.photoIds)
            result = store.library.photos.filter { set.contains($0.id) }
            let order = album.photoIds
            result.sort { (order.firstIndex(of: $0.id) ?? Int.max) < (order.firstIndex(of: $1.id) ?? Int.max) }
        } else {
            result = store.library.photos.sorted { $0.importedAt < $1.importedAt }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { matches($0, query: query) }
        }
        return result
    }

    private var dateGroups: [DateGroup] {
        let cal = Calendar.current
        var groups: [DateGroup] = []
        for photo in photos {
            let day = cal.startOfDay(for: photo.importedAt)
            if let idx = groups.firstIndex(where: { $0.date == day }) {
                groups[idx].photos.append(photo)
            } else {
                groups.append(DateGroup(date: day, label: dayLabel(day), photos: [photo]))
            }
        }
        return groups
    }

    private var title: String {
        if isSelecting {
            return "已选 \(selectedIDs.count) 张"
        }
        if let selectedAlbumID, let album = store.library.albums.first(where: { $0.id == selectedAlbumID }) {
            return album.name
        }
        return "素材"
    }

    var body: some View {
        NavigationStack {
            if selectedAlbumID == nil {
                allPhotosView
            } else {
                albumGridView
            }
        }
    }

    // MARK: - 全部素材（按日期分组 + 时间条）

    private var allPhotosView: some View {
        ScrollView {
            if photos.isEmpty {
                emptyState
            } else {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(dateGroups) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.label)
                                .font(.headline)
                                .padding(.horizontal, 4)
                            LazyVGrid(columns: columns, spacing: 4) {
                                ForEach(group.photos) { photo in
                                    card(photo)
                                }
                            }
                        }
                        .id(group.date)
                    }
                }
                .scrollTargetLayout()
                .padding(4)
            }
        }
        .background(AppTheme.background)
        .overlay(alignment: .topTrailing) {
            if let currentDate {
                Text(dayLabel(currentDate))
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.85))
                    .foregroundColor(.white)
                    .cornerRadius(6)
                    .padding(.trailing, 6)
                    .padding(.top, 2)
            }
        }
        .scrollPosition(id: $currentDate)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { materialToolbar }
        .searchable(text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "搜索备注 / 颜色 / 册子名")
        .sheet(isPresented: $showAlbums) {
            AlbumSheet(selectedAlbumID: $selectedAlbumID)
        }
        .sheet(isPresented: $showBatchAlbum) {
            BatchAlbumPickerSheet(photoIDs: Array(selectedIDs), onDone: { exitSelectMode() })
        }
    }

    // MARK: - 册子视图（简单网格 + 拖拽排序）

    private var albumGridView: some View {
        ScrollView {
            if photos.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(photos) { photo in
                        card(photo)
                    }
                }
                .padding(4)
            }
        }
        .background(AppTheme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { materialToolbar }
        .searchable(text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "搜索备注 / 颜色 / 册子名")
        .sheet(isPresented: $showAlbums) {
            AlbumSheet(selectedAlbumID: $selectedAlbumID)
        }
        .sheet(isPresented: $showBatchAlbum) {
            BatchAlbumPickerSheet(photoIDs: Array(selectedIDs), onDone: { exitSelectMode() })
        }
    }

    @ToolbarContentBuilder
    private var materialToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if isSelecting {
                Button("完成") { exitSelectMode() }
            } else {
                Button { showAlbums = true } label: { Image(systemName: "folder") }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if isSelecting {
                HStack(spacing: 14) {
                    Button("加入册子") { showBatchAlbum = true }
                        .disabled(selectedIDs.isEmpty)
                    Button("删除", role: .destructive) {
                        store.deletePhotos(selectedIDs)
                        exitSelectMode()
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            } else {
                Button("选择") {
                    isSelecting = true
                    selectedIDs.removeAll()
                }
            }
        }
    }

    // MARK: - 卡片

    @ViewBuilder
    private func card(_ photo: Photo) -> some View {
        if isSelecting {
            photoThumb(photo)
                .onTapGesture { toggleSelect(photo.id) }
        } else if let albumID = selectedAlbumID {
            let cellSize = (UIScreen.main.bounds.width - 16) / 3
            NavigationLink {
                PhotoDetailView(photo: photo)
            } label: {
                photoThumb(photo)
            }
            .buttonStyle(.plain)
            .offset(dragPhotoID == photo.id ? dragTranslation : .zero)
            .zIndex(dragPhotoID == photo.id ? 1 : 0)
            .scaleEffect(dragPhotoID == photo.id ? 1.08 : 1)
            .shadow(color: dragPhotoID == photo.id ? .black.opacity(0.25) : .clear, radius: dragPhotoID == photo.id ? 6 : 0)
            .contextMenu {
                Button {
                    store.setCover(photoID: photo.id, for: albumID)
                } label: {
                    Label("设为封面", systemImage: "photo")
                }
            }
            .gesture(reorderGesture(for: photo, albumID: albumID, cellSize: cellSize))
        } else {
            NavigationLink {
                PhotoDetailView(photo: photo)
            } label: {
                photoThumb(photo)
            }
            .buttonStyle(.plain)
        }
    }

    private func reorderGesture(for photo: Photo, albumID: String, cellSize: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if dragPhotoID == nil {
                    dragPhotoID = photo.id
                    dragStartIndex = store.library.albums.first(where: { $0.id == albumID })?.photoIds.firstIndex(of: photo.id)
                }
                dragTranslation = value.translation
                reorderInAlbum(photoID: photo.id, albumID: albumID, translation: value.translation, cellSize: cellSize)
            }
            .onEnded { _ in
                dragPhotoID = nil
                dragTranslation = .zero
                dragStartIndex = nil
                store.save()
            }
    }

    private func reorderInAlbum(photoID: String, albumID: String, translation: CGSize, cellSize: CGFloat) {
        guard let albumIdx = store.library.albums.firstIndex(where: { $0.id == albumID }) else { return }
        let ids = store.library.albums[albumIdx].photoIds
        guard let start = dragStartIndex, let current = ids.firstIndex(of: photoID) else { return }
        let col = Int((translation.width / (cellSize + 4)).rounded())
        let row = Int((translation.height / (cellSize + 4)).rounded())
        let target = min(max(start + row * 3 + col, 0), ids.count - 1)
        guard target != current else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            var newIds = store.library.albums[albumIdx].photoIds
            let moved = newIds.remove(at: current)
            newIds.insert(moved, at: target)
            store.library.albums[albumIdx].photoIds = newIds
        }
    }

    private func photoThumb(_ photo: Photo) -> some View {
        PhotoCard(photo: photo)
            .overlay(alignment: .topLeading) {
                if isSelecting {
                    Image(systemName: selectedIDs.contains(photo.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundColor(AppTheme.primaryText)
                        .padding(4)
                        .background(AppTheme.cardBackground.opacity(0.9))
                        .clipShape(Circle())
                        .padding(4)
                }
            }
    }

    private func toggleSelect(_ id: String) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    private func exitSelectMode() {
        isSelecting = false
        selectedIDs.removeAll()
    }

    private func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今天" }
        if cal.isDateInYesterday(date) { return "昨天" }
        return date.formatted(.dateTime.year().month().day())
    }

    private func matches(_ photo: Photo, query: String) -> Bool {
        let q = query.lowercased()
        var haystacks = [photo.note]
        haystacks += photo.regions.map { $0.note }
        haystacks += photo.tags
        haystacks += photo.colors.map { ColorExtractor.colorName(hex: $0.hex) }
        haystacks += photo.colors.map { $0.hex }
        haystacks += store.library.albums
            .filter { $0.photoIds.contains(photo.id) }
            .map { $0.name }
        return haystacks.contains { $0.lowercased().contains(q) }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: searchText.isEmpty ? "photo.on.rectangle.angled" : "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(AppTheme.secondaryText)
            Text(searchText.isEmpty ? "还没有素材" : "没有找到匹配的素材")
                .font(.title3).fontWeight(.semibold)
            if searchText.isEmpty {
                Text("点底部「＋」拍照或从相册选择")
                    .font(.callout)
                    .foregroundColor(AppTheme.secondaryText)
            }
        }
        .foregroundColor(AppTheme.primaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 120)
    }
}
