import SwiftUI

/// 穿搭页：衣橱 / 搭配（画板）
struct OutfitView: View {
    @EnvironmentObject var outfit: OutfitStore
    @State private var section: OutfitSection = .wardrobe
    @State private var wardrobeSelecting = false
    @State private var showDraftBox = false

    enum OutfitSection: String, CaseIterable {
        case wardrobe = "衣橱"
        case outfit = "搭配"
    }

    var body: some View {
        NavigationStack {
            content
                .background(AppTheme.background)
                .navigationTitle("穿搭")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(AppTheme.cardBackground, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showDraftBox = true } label: {
                            Image(systemName: "archivebox")
                        }
                    }
                    ToolbarItem(placement: .principal) {
                        Picker("", selection: $section) {
                            ForEach(OutfitSection.allCases, id: \.self) { s in
                                Text(s.rawValue).tag(s)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 150)
                    }
                }
                .sheet(isPresented: $showDraftBox) {
                    DraftBoxView {
                        section = .outfit
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if section == .wardrobe {
            WardrobeView(selecting: $wardrobeSelecting) {
                section = .outfit
            }
        } else {
            OutfitCanvasView(items: $outfit.currentItems) {
                wardrobeSelecting = true
                section = .wardrobe
            }
        }
    }
}

/// 衣橱：左侧分类栏 + 右侧单品网格（支持多选 添加/删除）
struct WardrobeView: View {
    @EnvironmentObject var wardrobe: WardrobeStore
    @EnvironmentObject var outfit: OutfitStore
    @Binding var selecting: Bool
    var onAddToCanvas: () -> Void
    @State private var selectedCategory: String?
    @State private var selectedIDs: Set<String> = []
    /// 点开查看的单品详情
    @State private var detailItem: WardrobeItem?

    private let columns = [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)]

    private var categories: [String] {
        let defaults = WardrobeStore.defaultCategories.filter { cat in
            wardrobe.items.contains { $0.category == cat }
        }
        let custom = Set(wardrobe.items.map { $0.category })
            .filter { !WardrobeStore.defaultCategories.contains($0) }
            .sorted()
        return defaults + custom
    }

    private var filteredItems: [WardrobeItem] {
        if let selectedCategory {
            return wardrobe.items.filter { $0.category == selectedCategory }
        }
        return wardrobe.items
    }

    var body: some View {
        HStack(spacing: 0) {
            categorySidebar
                .frame(width: 92)
            Rectangle().fill(AppTheme.divider).frame(width: 1)
            itemGrid
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .toolbar { wardrobeToolbar }
        .sheet(item: $detailItem) { item in
            NavigationStack {
                WardrobeItemDetailView(item: item)
            }
        }
    }

    private var categorySidebar: some View {
        ScrollView {
            VStack(spacing: 4) {
                categoryButton("全部", category: nil)
                ForEach(categories, id: \.self) { cat in
                    categoryButton(cat, category: cat)
                }
            }
            .padding(.vertical, 8)
        }
        .background(AppTheme.cardBackground)
    }

    private func categoryButton(_ name: String, category: String?) -> some View {
        Button {
            selectedCategory = category
        } label: {
            Text(name)
                .font(.caption)
                .lineLimit(2)
                .padding(.vertical, 10)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity)
                .background(selectedCategory == category ? AppTheme.primaryText.opacity(0.10) : Color.clear)
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .foregroundColor(selectedCategory == category ? AppTheme.primaryText : AppTheme.secondaryText)
    }

    private var itemGrid: some View {
        ScrollView {
            if filteredItems.isEmpty {
                VStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "tshirt").font(.system(size: 36))
                        Text("这里还没有单品").font(.callout)
                    }
                    .foregroundColor(AppTheme.secondaryText)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .containerRelativeFrame(.vertical)
            } else {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(filteredItems) { item in
                        if selecting {
                            itemCell(item)
                                .overlay(alignment: .topLeading) {
                                    Image(systemName: selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 20))
                                        .foregroundColor(selectedIDs.contains(item.id) ? AppTheme.primaryText : AppTheme.secondaryText)
                                        .padding(6)
                                }
                                .onTapGesture { toggleSelect(item.id) }
                        } else {
                            Button {
                                detailItem = item
                            } label: {
                                itemCell(item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(0)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func itemCell(_ item: WardrobeItem) -> some View {
        Rectangle()
            .fill(Color.white)
            .aspectRatio(0.75, contentMode: .fill)
            .overlay {
                if let img = wardrobe.image(for: item) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.divider, lineWidth: 1))
    }

    private func toggleSelect(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func addSelectedToCanvas() {
        for id in selectedIDs {
            guard let item = wardrobe.items.first(where: { $0.id == id }) else { continue }
            outfit.currentItems.append(CanvasItem(
                wardrobeItemId: item.id,
                x: UIScreen.main.bounds.width / 2 + CGFloat.random(in: -60...60),
                y: 420 + CGFloat.random(in: -80...80),
                scale: 1,
                rotation: 0
            ))
        }
        selectedIDs.removeAll()
        selecting = false
        onAddToCanvas()
    }

    private func deleteSelected() {
        for id in selectedIDs {
            wardrobe.deleteItem(id: id)
        }
        selectedIDs.removeAll()
        selecting = false
    }

    @ToolbarContentBuilder
    private var wardrobeToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if selecting {
                HStack(spacing: 14) {
                    Button("取消") {
                        selecting = false
                        selectedIDs.removeAll()
                    }
                    Button("添加") { addSelectedToCanvas() }
                        .disabled(selectedIDs.isEmpty)
                    Button("删除", role: .destructive) { deleteSelected() }
                        .disabled(selectedIDs.isEmpty)
                }
            } else {
                Button("选择") {
                    selecting = true
                    selectedIDs.removeAll()
                }
            }
        }
    }
}

/// 单品详情
struct WardrobeItemDetailView: View {
    let item: WardrobeItem
    @EnvironmentObject var wardrobe: WardrobeStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let img = wardrobe.image(for: item) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .padding(16)
                        .background(Color.white)
                }
                Text("分类：\(item.category)").font(.subheadline)
                if !item.brand.isEmpty { Text("品牌：\(item.brand)").font(.subheadline) }
                if !item.size.isEmpty { Text("尺码：\(item.size)").font(.subheadline) }
                if !item.price.isEmpty { Text("价格：\(item.price)").font(.subheadline) }
                Button("删除这个单品", role: .destructive) {
                    wardrobe.deleteItem(id: item.id)
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding(16)
        }
        .background(AppTheme.background)
        .navigationTitle("单品详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 搭配画板：从衣橱导入单品，拖动 / 缩放 / 旋转 / 图层 / 导出到素材
struct OutfitCanvasView: View {
    @EnvironmentObject var wardrobe: WardrobeStore
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var outfit: OutfitStore
    @Binding var items: [CanvasItem]
    var onAddItems: () -> Void
    @State private var selectedID: UUID?
    @State private var canvasSize: CGSize = .zero
    @State private var showSavedAlert = false
    @State private var showDraftSavedAlert = false
    @State private var showExportOptions = false
    @State private var draggingID: UUID?
    @State private var dragTranslation: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .zIndex(1)
            Rectangle().fill(AppTheme.divider).frame(width: 1)
            canvas
                .zIndex(0)
        }
        .navigationTitle("搭配画板")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !items.isEmpty {
                    Button("清空") {
                        items.removeAll()
                        selectedID = nil
                        outfit.currentDraftID = nil
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 14) {
                    Button {
                        showExportOptions = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .disabled(items.isEmpty)

                    Button { onAddItems() } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .confirmationDialog("保存到", isPresented: $showExportOptions, titleVisibility: .visible) {
            Button("下载到素材") { exportToMaterial() }
            if outfit.currentDraftID != nil {
                Button("保存到原草稿") { saveToCurrentDraft() }
            }
            Button("放入草稿箱") { saveToDraft() }
            Button("取消", role: .cancel) {}
        }
        .alert("已保存到素材", isPresented: $showSavedAlert) {
            Button("好", role: .cancel) {}
        }
        .alert("已放入草稿箱", isPresented: $showDraftSavedAlert) {
            Button("好", role: .cancel) {}
        }
    }

    // MARK: - 左侧：已添加单品栏 + 图层控件

    private var sidebar: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(Array(items.reversed())) { item in
                    sidebarCell(item)
                        .offset(y: draggingID == item.id ? dragTranslation : 0)
                        .zIndex(draggingID == item.id ? 1 : 0)
                        .simultaneousGesture(reorderGesture(item))
                }
            }
            .padding(8)
        }
        .frame(width: 88)
        .background(AppTheme.cardBackground)
    }

    private func sidebarCell(_ item: CanvasItem) -> some View {
        ZStack(alignment: .topLeading) {
            Button {
                selectedID = item.id
            } label: {
                Rectangle()
                    .fill(Color.white)
                    .aspectRatio(0.75, contentMode: .fill)
                    .overlay {
                        if let wardrobeItem = wardrobe.items.first(where: { $0.id == item.wardrobeItemId }),
                           let img = wardrobe.image(for: wardrobeItem) {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .padding(4)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(selectedID == item.id ? AppTheme.primaryText : Color.clear, lineWidth: 2)
                    )
            }
            .buttonStyle(.plain)

            if selectedID == item.id {
                Button {
                    deleteItem(item)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.red)
                        .background(Circle().fill(Color.white))
                }
                .buttonStyle(.plain)
                .offset(x: -5, y: -5)
            }
        }
    }

    private func deleteItem(_ item: CanvasItem) {
        items.removeAll { $0.id == item.id }
        selectedID = nil
    }

    /// 长按拖拽侧栏小图，调整层级（画板遮挡关系）
    private func reorderGesture(_ item: CanvasItem) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture())
            .onChanged { value in
                if case .second(true, let drag?) = value {
                    if draggingID == nil { draggingID = item.id }
                    dragTranslation = drag.translation.height
                }
            }
            .onEnded { value in
                if case .second(true, let drag?) = value, draggingID == item.id {
                    moveItem(id: item.id, by: drag.translation.height)
                }
                draggingID = nil
                dragTranslation = 0
            }
    }

    private func moveItem(id: UUID, by offset: CGFloat) {
        let cellStride: CGFloat = 104
        let delta = Int((offset / cellStride).rounded())
        guard delta != 0 else { return }
        var topFirst = Array(items.reversed())
        guard let idx = topFirst.firstIndex(where: { $0.id == id }) else { return }
        let newIdx = min(max(idx + delta, 0), topFirst.count - 1)
        guard newIdx != idx else { return }
        let moved = topFirst.remove(at: idx)
        topFirst.insert(moved, at: newIdx)
        items = Array(topFirst.reversed())
    }

    // MARK: - 画布

    private var canvas: some View {
        ZStack {
            AppTheme.canvasBackground
                .contentShape(Rectangle())
                .onTapGesture { selectedID = nil }

            ForEach($items) { $item in
                if let wardrobeItem = wardrobe.items.first(where: { $0.id == item.wardrobeItemId }),
                   let img = wardrobe.image(for: wardrobeItem) {
                    CanvasItemView(image: img, item: $item, isSelected: selectedID == item.id)
                        .onTapGesture { selectedID = item.id }
                }
            }

            if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "plus.square.dashed").font(.system(size: 44))
                    Text("点右上角 ＋ 从衣橱添加单品").font(.callout)
                }
                .foregroundColor(AppTheme.secondaryText)
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear.onAppear { canvasSize = geo.size }
            }
        )
    }

    /// 把画板渲染成一张图，存进「素材」的默认「搭配」册子
    private func exportToMaterial() {
        guard canvasSize.width > 0, canvasSize.height > 0, !items.isEmpty else { return }
        guard let image = OutfitStore.renderCanvas(items: items, canvasSize: canvasSize, wardrobe: wardrobe, outputSize: canvasSize),
              let data = image.pngData(),
              let photo = store.exportToOutfitAlbum(data) else { return }
        store.generateTags(for: photo.id)
        showSavedAlert = true
    }

    /// 把当前画板放入草稿箱
    private func saveToDraft() {
        guard !items.isEmpty else { return }
        outfit.saveDraft(name: outfit.nextDraftName(), items: items, canvasSize: canvasSize)
        showDraftSavedAlert = true
    }

    /// 把当前画板的新操作保存回原草稿
    private func saveToCurrentDraft() {
        guard let id = outfit.currentDraftID, !items.isEmpty else { return }
        outfit.updateDraft(id: id, items: items, canvasSize: canvasSize)
        showDraftSavedAlert = true
    }
}

/// 画板上的单个单品（拖动/缩放/旋转）
struct CanvasItemView: View {
    let image: UIImage
    @Binding var item: CanvasItem
    var isSelected: Bool

    @State private var dragStart: CGPoint?
    @State private var scaleStart: CGFloat?
    @State private var rotationStart: Double?

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(width: 130 * item.scale)
            .rotationEffect(.radians(item.rotation))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? AppTheme.primaryText : Color.clear, lineWidth: 2)
            )
            .position(x: item.x, y: item.y)
            .gesture(dragGesture)
            .simultaneousGesture(magnifyGesture)
            .simultaneousGesture(rotationGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStart == nil {
                    dragStart = CGPoint(x: item.x, y: item.y)
                }
                item.x = dragStart!.x + value.translation.width
                item.y = dragStart!.y + value.translation.height
            }
            .onEnded { _ in dragStart = nil }
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                if scaleStart == nil { scaleStart = item.scale }
                item.scale = max(0.2, min(4, scaleStart! * value))
            }
            .onEnded { _ in scaleStart = nil }
    }

    private var rotationGesture: some Gesture {
        RotationGesture()
            .onChanged { value in
                if rotationStart == nil { rotationStart = item.rotation }
                item.rotation = rotationStart! + value.radians
            }
            .onEnded { _ in rotationStart = nil }
    }
}

/// 草稿箱：画板缩略图网格 + 长按删除/重命名
struct DraftBoxView: View {
    @EnvironmentObject var outfit: OutfitStore
    @EnvironmentObject var wardrobe: WardrobeStore
    var onOpen: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var renamingDraft: OutfitDraft?
    @State private var renameText = ""
    @State private var showRenameAlert = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            if outfit.drafts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "archivebox").font(.system(size: 36))
                    Text("还没有草稿").font(.callout)
                }
                .foregroundColor(AppTheme.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("草稿箱")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("关闭") { dismiss() }
                    }
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(outfit.drafts) { draft in
                            draftCell(draft)
                        }
                    }
                    .padding(12)
                }
                .navigationTitle("草稿箱")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("关闭") { dismiss() }
                    }
                }
            }
        }
        .alert("重命名", isPresented: $showRenameAlert) {
            TextField("名称", text: $renameText)
            Button("确定") {
                if let d = renamingDraft {
                    outfit.renameDraft(id: d.id, newName: renameText)
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func draftCell(_ draft: OutfitDraft) -> some View {
        Button {
            outfit.currentItems = draft.items
            outfit.currentDraftID = draft.id
            onOpen()
            dismiss()
        } label: {
            VStack(spacing: 6) {
                if let thumb = OutfitStore.renderCanvas(
                    items: draft.items,
                    canvasSize: CGSize(width: draft.canvasWidth, height: draft.canvasHeight),
                    wardrobe: wardrobe,
                    outputSize: CGSize(width: 180, height: 220)
                ) {
                    Image(uiImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 190)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Rectangle()
                        .fill(AppTheme.canvasBackground)
                        .frame(height: 190)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Text(draft.name)
                    .font(.caption)
                    .foregroundColor(AppTheme.primaryText)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                renamingDraft = draft
                renameText = draft.name
                showRenameAlert = true
            } label: {
                Label("重命名", systemImage: "pencil")
            }
            Button(role: .destructive) {
                outfit.deleteDraft(id: draft.id)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}

/// 抠图后选择分类（支持批量）
struct CategoryPickerSheet: View {
    let images: [UIImage]
    var onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var customCategory = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if let first = images.first {
                    Image(uiImage: first)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 160)
                        .padding(.top, 16)
                }
                List {
                    ForEach(WardrobeStore.defaultCategories, id: \.self) { category in
                        Button {
                            onPick(category)
                            dismiss()
                        } label: {
                            Text(category)
                        }
                        .foregroundColor(AppTheme.primaryText)
                    }
                    HStack {
                        TextField("自定义分类", text: $customCategory)
                        Button("添加") {
                            let c = customCategory.trimmingCharacters(in: .whitespaces)
                            if !c.isEmpty {
                                onPick(c)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle("选择分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

/// 衣橱添加：填写品牌 / 尺码 / 价格（都可留空）
struct ItemInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onConfirm: (String, String, String) -> Void
    @State private var brand = ""
    @State private var size = ""
    @State private var price = ""

    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("补充信息（可留空）")
                    .font(.headline)
                    .foregroundColor(AppTheme.primaryText)
                VStack(spacing: 10) {
                    field("品牌", text: $brand)
                    field("尺码", text: $size)
                    field("价格", text: $price)
                }
                HStack(spacing: 16) {
                    Button("取消") { dismiss() }
                        .foregroundColor(AppTheme.secondaryText)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                    Button("确定") {
                        dismiss()
                        onConfirm(
                            brand.trimmingCharacters(in: .whitespacesAndNewlines),
                            size.trimmingCharacters(in: .whitespacesAndNewlines),
                            price.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
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
            .padding(.horizontal, 40)
        }
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .padding(10)
            .background(AppTheme.background)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.divider, lineWidth: 1))
    }
}
