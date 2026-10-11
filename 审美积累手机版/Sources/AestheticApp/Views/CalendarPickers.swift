import SwiftUI

/// 日历页用到的弹窗（用单个 fullScreenCover 承载，避免多 sheet 冲突）
enum CalendarSheet: Identifiable {
    case libraryPicker                        // 从素材导入
    case viewer(entryID: String, startIndex: Int) // 照片查看器

    var id: String {
        switch self {
        case .libraryPicker: return "libraryPicker"
        case .viewer(let id, let index): return "viewer-\(id)-\(index)"
        }
    }
}

/// 从素材导入：多选素材照片（支持按册子 / 关键词 / 标签 / 颜色筛选），复制进日历某一天
struct LibraryPhotoPickerSheet: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let onConfirm: ([String]) -> Void
    @State private var selectedIDs: Set<String> = []
    /// 来源册子（nil = 全部素材）
    @State private var sourceAlbumID: String?
    @State private var searchText = ""
    @State private var selectedTag: String?
    @State private var selectedColor: String?

    /// 颜色筛选用到的固定色板（与 ColorExtractor.colorName 的中文名对应）
    private static let colorPalette: [(name: String, hex: String)] = [
        ("红色", "#D32F2F"), ("橙色", "#F57C00"), ("黄色", "#FBC02D"),
        ("绿色", "#388E3C"), ("青色", "#00ACC1"), ("蓝色", "#1976D2"),
        ("紫色", "#7B1FA2"), ("粉色", "#EC407A"), ("棕色", "#795548"),
        ("米色", "#D7CCC8"), ("黑色", "#212121"), ("白色", "#F5F5F5"),
        ("灰色", "#9E9E9E")
    ]

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.library.photos.isEmpty {
                Spacer()
                Text("素材里还没有照片")
                    .foregroundColor(AppTheme.secondaryText)
                Spacer()
            } else {
                filterBar
                Divider()
                if filteredPhotos.isEmpty {
                    Spacer()
                    Text("没有找到匹配的素材")
                        .foregroundColor(AppTheme.secondaryText)
                    Spacer()
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(filteredPhotos) { photo in
                                cell(photo)
                            }
                        }
                        .padding(8)
                    }
                }
            }
            Divider()
            footer
        }
        .background(AppTheme.background)
    }

    // MARK: - 筛选后的照片

    private var filteredPhotos: [Photo] {
        var result: [Photo]
        if let sourceAlbumID, let album = store.library.albums.first(where: { $0.id == sourceAlbumID }) {
            let set = Set(album.photoIds)
            result = store.library.photos.filter { set.contains($0.id) }
        } else {
            result = store.library.photos.sorted { $0.importedAt < $1.importedAt }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { matches($0, query: query) }
        }
        if let tag = selectedTag {
            result = result.filter { $0.tags.contains(tag) }
        }
        if let color = selectedColor {
            result = result.filter { $0.colors.contains { ColorExtractor.colorName(hex: $0.hex) == color } }
        }
        return result
    }

    /// 全部素材里出现过的标签（去重排序，作为筛选 chips）
    private var allTags: [String] {
        Array(Set(store.library.photos.flatMap { $0.tags })).sorted()
    }

    /// 关键词匹配：整体备注 / 局部标注 / 标签 / 颜色名与色值 / 所在册子名
    private func matches(_ photo: Photo, query: String) -> Bool {
        let q = query.lowercased()
        var haystacks = [photo.note]
        haystacks += photo.regions.map { $0.note }
        haystacks += photo.tags
        haystacks += photo.colors.map { ColorExtractor.colorName(hex: $0.hex) }
        haystacks += photo.colors.map { $0.hex }
        haystacks += store.library.albums.filter { $0.photoIds.contains(photo.id) }.map { $0.name }
        return haystacks.contains { $0.lowercased().contains(q) }
    }

    // MARK: - 顶部筛选栏

    private var filterBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(AppTheme.secondaryText)
                TextField("搜索备注 / 标签 / 颜色", text: $searchText)
                    .autocorrectionDisabled()
            }
            .padding(8)
            .background(AppTheme.cardBackground)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.divider, lineWidth: 1))

            albumChips
            if !allTags.isEmpty { tagChips }
            colorChips
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var albumChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip("全部", selected: sourceAlbumID == nil) { sourceAlbumID = nil }
                ForEach(store.library.albums) { album in
                    filterChip(album.name, selected: sourceAlbumID == album.id) { sourceAlbumID = album.id }
                }
            }
        }
    }

    private var tagChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(allTags, id: \.self) { tag in
                    filterChip(tag, selected: selectedTag == tag) {
                        selectedTag = (selectedTag == tag ? nil : tag)
                    }
                }
            }
        }
    }

    private var colorChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Self.colorPalette, id: \.name) { item in
                    VStack(spacing: 3) {
                        Circle()
                            .fill(Color(hexString: item.hex))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle().stroke(
                                    selectedColor == item.name ? AppTheme.primaryText : AppTheme.divider,
                                    lineWidth: selectedColor == item.name ? 2 : 1
                                )
                            )
                        Text(item.name)
                            .font(.system(size: 9))
                            .foregroundColor(selectedColor == item.name ? AppTheme.primaryText : AppTheme.secondaryText)
                    }
                    .onTapGesture {
                        selectedColor = (selectedColor == item.name ? nil : item.name)
                    }
                }
            }
        }
    }

    private func filterChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(selected ? .semibold : .regular))
                .foregroundColor(selected ? .white : AppTheme.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? AppTheme.primaryText : AppTheme.cardBackground)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(selected ? Color.clear : AppTheme.divider, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 头部 / 底部

    private var header: some View {
        HStack {
            Button("取消") { dismiss() }
                .foregroundColor(AppTheme.secondaryText)
            Spacer()
            Text("从素材选择")
                .font(.headline)
                .foregroundColor(AppTheme.primaryText)
            Spacer()
            Color.clear.frame(width: 44, height: 32) // 平衡左侧「取消」，让标题居中
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("添加(\(selectedIDs.count))") {
                let ids = store.library.photos.map(\.id).filter { selectedIDs.contains($0) }
                dismiss()
                onConfirm(ids)
            }
            .disabled(selectedIDs.isEmpty)
            .font(.subheadline.weight(.medium))
            .foregroundColor(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 20)
            .background(AppTheme.primaryText.opacity(selectedIDs.isEmpty ? 0.35 : 1))
            .cornerRadius(8)
        }
        .padding(12)
    }

    private func cell(_ photo: Photo) -> some View {
        let selected = selectedIDs.contains(photo.id)
        return PhotoCard(photo: photo)
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 6).stroke(AppTheme.primaryText, lineWidth: 2)
                }
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(selected ? AppTheme.primaryText : .white)
                    .padding(4)
                    .shadow(color: .black.opacity(0.3), radius: 2)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if selected {
                    selectedIDs.remove(photo.id)
                } else {
                    selectedIDs.insert(photo.id)
                }
            }
    }
}

/// 加号「日历」导入时选择归入的日期
struct CalendarDatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onConfirm: (Date) -> Void
    @State private var selectedDate: Date = Date()

    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("归入哪一天")
                    .font(.headline)
                    .foregroundColor(AppTheme.primaryText)
                DatePicker("日期", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                HStack(spacing: 16) {
                    Button("取消") { dismiss() }
                        .foregroundColor(AppTheme.secondaryText)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                    Button("确定") {
                        dismiss()
                        onConfirm(selectedDate)
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 24)
                    .background(AppTheme.primaryText)
                    .cornerRadius(8)
                }
                .padding(.top, 4)
            }
            .padding(20)
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
            .padding(.horizontal, 32)
        }
    }
}
