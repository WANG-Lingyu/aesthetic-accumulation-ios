import SwiftUI

enum ResizeCorner { case topLeft, topRight, bottomLeft, bottomRight }

/// 素材详情页：大图 + 圈选（点选/拖动/缩放/长按删除）+ 常驻备注 + 取色
struct PhotoDetailView: View {
    let photo: Photo
    @EnvironmentObject var store: LibraryStore
    @State private var draft: Photo
    @State private var selectedRegionID: String?
    @State private var draftRect: Region?
    @State private var newShape: RegionShape = .rect
    @State private var newColorHex: String = AppTheme.defaultRegionColor
    @State private var isDrawing = false
    @State private var dragStart: CGPoint = .zero
    @State private var penActive = false
    @State private var zoomScale: CGFloat = 1.0
    @State private var steadyZoom: CGFloat = 1.0
    @State private var hideAllNotes = false
    @State private var labelDragBase: CGPoint?
    @State private var noteResizeBase: CGFloat?
    @State private var movingRegionID: String?
    @State private var movingRegionStart: Region?
    @State private var resizingCorner: ResizeCorner?
    @State private var resizeStart: Region?
    @State private var showAlbumToggle = false
    @State private var newTag = ""

    init(photo: Photo) {
        self.photo = photo
        _draft = State(initialValue: photo)
    }

    private var uiImage: UIImage? {
        store.uiImage(for: draft)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                imageArea
                hideAllNotesToggle
                styleSection
                regionsSection
                noteSection
                colorSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 80)
        }
        .background(AppTheme.background)
        .navigationTitle("素材详情")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: draft) { _, _ in store.updatePhoto(draft) }
        .onAppear { generateTagsIfNeeded() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAlbumToggle = true } label: {
                    Image(systemName: "folder.badge.plus")
                }
            }
        }
        .sheet(isPresented: $showAlbumToggle) {
            AlbumToggleSheet(photo: draft)
        }
    }

    // MARK: - 大图 + 圈选

    private var imageArea: some View {
        GeometryReader { geo in
            let imageSize = uiImage?.size ?? CGSize(width: 1, height: 1)
            let fitted = fittedRect(imageSize: imageSize, in: geo.size)
            let base = ZStack(alignment: .topLeading) {
                if let uiImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                } else {
                    Rectangle().fill(AppTheme.divider)
                }
                if penActive {
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(drawGesture(in: fitted))
                }
                if !hideAllNotes {
                    ForEach(draft.regions) { region in
                        regionShapeView(region, in: fitted)
                            .onTapGesture { selectedRegionID = region.id }
                            .contextMenu {
                                Button("删除", role: .destructive) {
                                    if let idx = draft.regions.firstIndex(where: { $0.id == region.id }) {
                                        deleteRegion(at: idx)
                                    }
                                }
                            }
                            .gesture(moveGesture(for: region, in: fitted))
                    }
                }
                if let draftRect {
                    regionShapeView(draftRect, in: fitted)
                }
                if !hideAllNotes, let sel = selectedRegion {
                    resizeHandles(for: sel, in: fitted)
                }
                noteViews(in: fitted)
            }
            .frame(width: fitted.width, height: fitted.height)
            .scaleEffect(zoomScale)
            .contentShape(Rectangle())
            .simultaneousGesture(magnifyGesture)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)

            if penActive {
                base
            } else {
                base.simultaneousGesture(tapGesture(in: fitted))
            }
        }
        .frame(height: 380)
        .background(AppTheme.divider.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var selectedRegion: Region? {
        guard let id = selectedRegionID else { return nil }
        return draft.regions.first(where: { $0.id == id })
    }

    private func regionShape(_ region: Region) -> AnyShape {
        switch region.shape {
        case .rect: return AnyShape(Rectangle())
        case .ellipse: return AnyShape(Ellipse())
        }
    }

    private func regionShapeView(_ region: Region, in fitted: CGRect) -> some View {
        let selected = region.id == selectedRegionID
        let color = Color(hexString: region.colorHex)
        let shape = regionShape(region)
        return shape
            .fill(selected ? color.opacity(0.14) : color.opacity(0.06))
            .overlay(shape.stroke(color, lineWidth: selected ? 2.5 : 1.5))
            .frame(width: CGFloat(region.width) * fitted.width,
                   height: CGFloat(region.height) * fitted.height)
            .offset(x: CGFloat(region.x) * fitted.width,
                    y: CGFloat(region.y) * fitted.height)
    }

    // MARK: - 备注（常驻显示）

    @ViewBuilder
    private func noteViews(in fitted: CGRect) -> some View {
        ForEach(draft.regions) { region in
            if !region.noteHidden && !hideAllNotes {
                noteView(for: region, in: fitted)
            }
        }
    }

    @ViewBuilder
    private func noteView(for region: Region, in fitted: CGRect) -> some View {
        let idx = draft.regions.firstIndex(where: { $0.id == region.id }) ?? -1
        let pos = labelPosition(for: region, in: fitted)
        let width = region.noteWidth > 0 ? CGFloat(region.noteWidth) * fitted.width : 140
        let selected = region.id == selectedRegionID

        if idx >= 0 {
            if selected {
                TextField("备注", text: $draft.regions[idx].note)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: width)
                    .offset(x: pos.x, y: pos.y)
                    .overlay(alignment: .bottomTrailing) {
                        noteResizeHandle(for: region, width: width, pos: pos, in: fitted)
                    }
                    .gesture(moveLabelGesture(for: region, in: fitted))
                    .contextMenu {
                        Button("隐藏备注") { toggleNoteHidden(region.id) }
                    }
            } else {
                Text(region.note.isEmpty ? "＋备注" : region.note)
                    .font(.caption)
                    .lineLimit(4)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(AppTheme.cardBackground.opacity(0.95))
                    .cornerRadius(4)
                    .foregroundColor(AppTheme.primaryText)
                    .offset(x: pos.x, y: pos.y)
                    .onTapGesture { selectedRegionID = region.id }
                    .gesture(moveLabelGesture(for: region, in: fitted))
                    .contextMenu {
                        Button("隐藏备注") { toggleNoteHidden(region.id) }
                    }
            }
        }
    }

    private func noteResizeHandle(for region: Region, width: CGFloat, pos: CGPoint, in fitted: CGRect) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(AppTheme.primaryText, lineWidth: 1))
            .frame(width: 14, height: 14)
            .offset(x: width + 2, y: 20)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if noteResizeBase == nil {
                            noteResizeBase = width
                        }
                        guard let base = noteResizeBase else { return }
                        let newW = max(base + value.translation.width, 60)
                        if let i = draft.regions.firstIndex(where: { $0.id == region.id }) {
                            draft.regions[i].noteWidth = Double(newW / fitted.width)
                        }
                    }
                    .onEnded { _ in noteResizeBase = nil }
            )
    }

    private func toggleNoteHidden(_ id: String) {
        if let i = draft.regions.firstIndex(where: { $0.id == id }) {
            draft.regions[i].noteHidden.toggle()
        }
    }

    private func labelPosition(for region: Region, in fitted: CGRect) -> CGPoint {
        if region.labelX >= 0 && region.labelY >= 0 {
            return CGPoint(x: CGFloat(region.labelX) * fitted.width,
                           y: CGFloat(region.labelY) * fitted.height)
        }
        let top = CGFloat(region.y) * fitted.height
        let x = CGFloat(region.x) * fitted.width
        let y: CGFloat = top > 34 ? top - 34 : top + CGFloat(region.height) * fitted.height + 4
        return CGPoint(x: x, y: y)
    }

    private func moveLabelGesture(for region: Region, in fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if labelDragBase == nil {
                    labelDragBase = labelPosition(for: region, in: fitted)
                }
                moveLabel(region, translation: value.translation, in: fitted)
            }
            .onEnded { _ in labelDragBase = nil }
    }

    private func moveLabel(_ region: Region, translation: CGSize, in fitted: CGRect) {
        guard let idx = draft.regions.firstIndex(where: { $0.id == region.id }) else { return }
        let base = labelDragBase ?? labelPosition(for: region, in: fitted)
        let newX = base.x + translation.width
        let newY = base.y + translation.height
        draft.regions[idx].labelX = min(max(Double(newX / fitted.width), 0), 1)
        draft.regions[idx].labelY = min(max(Double(newY / fitted.height), 0), 1)
    }

    // MARK: - 移动圈选

    private func moveGesture(for region: Region, in fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if movingRegionID != region.id {
                    movingRegionID = region.id
                    movingRegionStart = region
                }
                guard let start = movingRegionStart else { return }
                let dx = Double(value.translation.width / fitted.width)
                let dy = Double(value.translation.height / fitted.height)
                if let idx = draft.regions.firstIndex(where: { $0.id == region.id }) {
                    draft.regions[idx].x = min(max(start.x + dx, 0), 1 - start.width)
                    draft.regions[idx].y = min(max(start.y + dy, 0), 1 - start.height)
                }
            }
            .onEnded { _ in
                movingRegionID = nil
                movingRegionStart = nil
            }
    }

    // MARK: - 缩放圈选大小

    private func resizeHandles(for region: Region, in fitted: CGRect) -> some View {
        let x = CGFloat(region.x) * fitted.width
        let y = CGFloat(region.y) * fitted.height
        let w = CGFloat(region.width) * fitted.width
        let h = CGFloat(region.height) * fitted.height
        return ZStack {
            resizeHandle(at: CGPoint(x: x, y: y), corner: .topLeft, region: region, in: fitted)
            resizeHandle(at: CGPoint(x: x + w, y: y), corner: .topRight, region: region, in: fitted)
            resizeHandle(at: CGPoint(x: x, y: y + h), corner: .bottomLeft, region: region, in: fitted)
            resizeHandle(at: CGPoint(x: x + w, y: y + h), corner: .bottomRight, region: region, in: fitted)
        }
    }

    private func resizeHandle(at point: CGPoint, corner: ResizeCorner, region: Region, in fitted: CGRect) -> some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(AppTheme.primaryText, lineWidth: 1.5))
            .frame(width: 18, height: 18)
            .position(point)
            .gesture(resizeGesture(for: region, corner: corner, in: fitted))
    }

    private func resizeGesture(for region: Region, corner: ResizeCorner, in fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if resizingCorner != corner {
                    resizingCorner = corner
                    resizeStart = region
                }
                guard let start = resizeStart else { return }
                resize(region, start: start, corner: corner, translation: value.translation, in: fitted)
            }
            .onEnded { _ in
                resizingCorner = nil
                resizeStart = nil
            }
    }

    private func resize(_ region: Region, start: Region, corner: ResizeCorner, translation: CGSize, in fitted: CGRect) {
        let dx = Double(translation.width / fitted.width)
        let dy = Double(translation.height / fitted.height)
        var x = start.x, y = start.y, w = start.width, h = start.height
        switch corner {
        case .topLeft: x = start.x + dx; y = start.y + dy; w = start.width - dx; h = start.height - dy
        case .topRight: y = start.y + dy; w = start.width + dx; h = start.height - dy
        case .bottomLeft: x = start.x + dx; w = start.width - dx; h = start.height + dy
        case .bottomRight: w = start.width + dx; h = start.height + dy
        }
        let minSize = 0.03
        if w < minSize {
            w = minSize
            if corner == .topLeft || corner == .bottomLeft { x = start.x + start.width - minSize }
        }
        if h < minSize {
            h = minSize
            if corner == .topLeft || corner == .topRight { y = start.y + start.height - minSize }
        }
        if x < 0 { w += x; x = 0 }
        if y < 0 { h += y; y = 0 }
        if x + w > 1 { w = 1 - x }
        if y + h > 1 { h = 1 - y }
        w = max(w, minSize)
        h = max(h, minSize)
        if let idx = draft.regions.firstIndex(where: { $0.id == region.id }) {
            draft.regions[idx].x = x
            draft.regions[idx].y = y
            draft.regions[idx].width = w
            draft.regions[idx].height = h
        }
    }

    // MARK: - 放大 / 选中 / 画框

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoomScale = min(max(steadyZoom * value, 1), 4)
            }
            .onEnded { _ in steadyZoom = zoomScale }
    }

    private func tapGesture(in fitted: CGRect) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                let hit = draft.regions.reversed().first { region($0, contains: value.location, in: fitted) }
                selectedRegionID = hit?.id
            }
    }

    private func drawGesture(in fitted: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isDrawing && (abs(value.translation.width) > 2 || abs(value.translation.height) > 2) {
                    isDrawing = true
                    dragStart = value.startLocation
                }
                if isDrawing {
                    var r = makeRegion(start: dragStart, end: value.location, size: fitted.size)
                    r.shape = newShape
                    r.colorHex = newColorHex
                    draftRect = r
                }
            }
            .onEnded { value in
                if isDrawing {
                    var region = makeRegion(start: dragStart, end: value.location, size: fitted.size)
                    region.shape = newShape
                    region.colorHex = newColorHex
                    if region.width > 0.01, region.height > 0.01 {
                        draft.regions.append(region)
                        selectedRegionID = region.id
                    }
                    draftRect = nil
                    isDrawing = false
                }
            }
    }

    private func region(_ region: Region, contains point: CGPoint, in fitted: CGRect) -> Bool {
        guard fitted.width > 0, fitted.height > 0 else { return false }
        let nx = Double(point.x / fitted.width)
        let ny = Double(point.y / fitted.height)
        switch region.shape {
        case .rect:
            return nx >= region.x && nx <= region.x + region.width &&
                   ny >= region.y && ny <= region.y + region.height
        case .ellipse:
            let cx = region.x + region.width / 2
            let cy = region.y + region.height / 2
            let dx = (nx - cx) / max(region.width / 2, 0.0001)
            let dy = (ny - cy) / max(region.height / 2, 0.0001)
            return dx * dx + dy * dy <= 1
        }
    }

    private func makeRegion(start: CGPoint, end: CGPoint, size: CGSize) -> Region {
        guard size.width > 0, size.height > 0 else {
            return Region(x: 0, y: 0, width: 0, height: 0)
        }
        let x0 = min(start.x, end.x) / size.width
        let y0 = min(start.y, end.y) / size.height
        let x1 = max(start.x, end.x) / size.width
        let y1 = max(start.y, end.y) / size.height
        func clamp(_ v: CGFloat) -> Double { Double(min(max(v, 0), 1)) }
        return Region(
            x: clamp(x0), y: clamp(y0),
            width: max(0, clamp(x1) - clamp(x0)),
            height: max(0, clamp(y1) - clamp(y0))
        )
    }

    private func fittedRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, container.width > 0, container.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }

    // MARK: - 面板

    private var hideAllNotesToggle: some View {
        Toggle(isOn: $hideAllNotes) {
            Text("隐藏所有备注").font(.subheadline)
        }
    }

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("圈选工具").font(.headline)
                Spacer()
                Button {
                    penActive.toggle()
                    zoomScale = 1
                    steadyZoom = 1
                } label: {
                    Image(systemName: "pencil.tip.crop.circle")
                        .font(.title2)
                        .foregroundColor(penActive ? AppTheme.primaryText : AppTheme.secondaryText)
                        .padding(6)
                        .background(penActive ? AppTheme.primaryText.opacity(0.12) : AppTheme.cardBackground)
                        .clipShape(Circle())
                }
            }
            Text(penActive ? "画笔开启：拖拽画框；点圈选选中；长按删除；拖动框移动" : "画笔关闭：双指放大；点圈选看备注")
                .font(.caption)
                .foregroundColor(AppTheme.secondaryText)
            Picker("", selection: $newShape) {
                Text("矩形").tag(RegionShape.rect)
                Text("椭圆").tag(RegionShape.ellipse)
            }
            .pickerStyle(.segmented)
            HStack(spacing: 6) {
                ForEach(AppTheme.regionPalette, id: \.self) { hex in
                    Circle()
                        .fill(Color(hexString: hex))
                        .frame(width: 26, height: 26)
                        .overlay(Circle().stroke(newColorHex == hex ? AppTheme.primaryText : Color.clear, lineWidth: 2))
                        .contentShape(Circle())
                        .onTapGesture { newColorHex = hex }
                }
            }
        }
    }

    private var regionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("圈选笔记").font(.headline)
            if draft.regions.isEmpty {
                Text("还没有圈选：点画笔后拖拽画框")
                    .font(.caption)
                    .foregroundColor(AppTheme.secondaryText)
            } else if let idx = selectedRegionIndex {
                RegionEditor(region: $draft.regions[idx], onDelete: { deleteRegion(at: idx) })
            }

            ForEach(draft.regions) { region in
                HStack(spacing: 6) {
                    Circle().fill(Color(hexString: region.colorHex)).frame(width: 8, height: 8)
                    Text(region.note.isEmpty ? "未命名圈选" : region.note)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    if region.noteHidden {
                        Button {
                            toggleNoteHidden(region.id)
                        } label: {
                            Image(systemName: "eye.slash")
                                .font(.caption2)
                                .foregroundColor(AppTheme.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(region.id == selectedRegionID ? AppTheme.cardBackground : Color.clear)
                .cornerRadius(6)
                .contentShape(Rectangle())
                .onTapGesture { selectedRegionID = region.id }
            }
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("整体备注").font(.headline)
            TextEditor(text: $draft.note)
                .frame(minHeight: 80)
                .padding(4)
                .overlay(alignment: .topLeading) {
                    if draft.note.isEmpty {
                        Text(draft.tags.isEmpty ? "备注…" : "备注…（建议标签：\(draft.tags.joined(separator: "、"))）")
                            .font(.callout)
                            .foregroundColor(AppTheme.secondaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                }
                .background(AppTheme.cardBackground)
                .cornerRadius(8)
            VoiceNoteButton(note: $draft.note)
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("标签").font(.headline)
            HStack {
                TextField("添加标签", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                Button("添加") {
                    let t = newTag.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty && !draft.tags.contains(t) {
                        draft.tags.append(t)
                        newTag = ""
                    }
                }
                .buttonStyle(.bordered)
            }
            if draft.tags.isEmpty {
                Text("暂无标签，可手动添加").font(.caption).foregroundColor(AppTheme.secondaryText)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(draft.tags, id: \.self) { tag in
                        HStack(spacing: 3) {
                            Text(tag).font(.caption).lineLimit(1)
                            Button {
                                draft.tags.removeAll { $0 == tag }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption2)
                                    .foregroundColor(AppTheme.secondaryText)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(AppTheme.cardBackground)
                        .cornerRadius(6)
                    }
                }
            }
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("主色调").font(.headline)
            if draft.colors.isEmpty {
                Text("无").font(.caption).foregroundColor(AppTheme.secondaryText)
            } else {
                HStack(spacing: 6) {
                    ForEach(Array(draft.colors.enumerated()), id: \.offset) { _, c in
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(hexString: c.hex))
                                .frame(height: 26)
                            Text(ColorExtractor.colorName(hex: c.hex))
                                .font(.system(size: 10))
                                .foregroundColor(AppTheme.primaryText)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private var selectedRegionIndex: Int? {
        guard let id = selectedRegionID else { return nil }
        return draft.regions.firstIndex(where: { $0.id == id })
    }

    private func deleteRegion(at index: Int) {
        draft.regions.remove(at: index)
        selectedRegionID = nil
    }

    private func generateTagsIfNeeded() {
        guard draft.tags.isEmpty, let image = uiImage else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let tags = VisionTagger.extractTags(from: image)
            DispatchQueue.main.async {
                self.draft.tags = tags
            }
        }
    }
}

/// 单个圈选区域的编辑面板
struct RegionEditor: View {
    @Binding var region: Region
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("备注（如：上衣·低饱和灰调）", text: $region.note)
                .textFieldStyle(.roundedBorder)

            Picker("", selection: $region.shape) {
                Text("矩形").tag(RegionShape.rect)
                Text("椭圆").tag(RegionShape.ellipse)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 6) {
                ForEach(AppTheme.regionPalette, id: \.self) { hex in
                    Circle()
                        .fill(Color(hexString: hex))
                        .frame(width: 24, height: 24)
                        .overlay(Circle().stroke(region.colorHex == hex ? AppTheme.primaryText : Color.clear, lineWidth: 2))
                        .contentShape(Circle())
                        .onTapGesture { region.colorHex = hex }
                }
            }

            VoiceNoteButton(note: $region.note)

            Button("删除这个圈选", role: .destructive) { onDelete() }
                .font(.caption)
        }
        .padding(10)
        .background(AppTheme.cardBackground)
        .cornerRadius(8)
    }
}
