import SwiftUI

struct Stroke: Identifiable {
    let id = UUID()
    var points: [CGPoint]
    var isEraser: Bool
    var brushSize: CGFloat   // 每笔独立记录粗细，滑块只影响新笔迹，不影响已涂区域
}

/// 手动抠像（全屏页面）：默认整图保留，擦除笔涂成透明，保留笔恢复；实时红色蒙版预览
struct ManualCutoutView: View {
    let image: UIImage
    var onDone: (UIImage) -> Void
    var onUseOriginal: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var strokes: [Stroke] = []
    @State private var currentStroke: Stroke?
    @State private var isEraser = false
    @State private var brushSize: CGFloat = 30
    @State private var fittedSize: CGSize = .zero
    @State private var isPreviewing = false
    @State private var basePreview: UIImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { geo in
                    let fitted = fittedRect(imageSize: image.size, in: geo.size)
                    ZStack {
                        AppTheme.background

                        if isPreviewing {
                            // 最终预览：棋盘格透明底 + 抠图结果
                            checkerboard
                                .frame(width: fitted.width, height: fitted.height)
                                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            if let result = generateCutout() {
                                Image(uiImage: result)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: fitted.width, height: fitted.height)
                                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                            }
                        } else {
                            // 编辑态：实时蒙版预览（保留=红色，擦除=灰色）
                            ZStack {
                                if let preview = previewImage() {
                                    Image(uiImage: preview)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: fitted.width, height: fitted.height)
                                }
                                Color.clear
                                    .contentShape(Rectangle())
                                    .gesture(dragGesture)
                            }
                            .frame(width: fitted.width, height: fitted.height)
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        }
                    }
                    .onAppear {
                        fittedSize = fitted.size
                        basePreview = downscale(image, to: fitted.size)
                    }
                    .onChange(of: geo.size) { _, newSize in
                        let f = fittedRect(imageSize: image.size, in: newSize).size
                        fittedSize = f
                        basePreview = downscale(image, to: f)
                    }
                }

                toolbar
            }
            .navigationTitle(isPreviewing ? "预览" : "手动抠像")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isPreviewing ? "返回编辑" : "预览") { isPreviewing.toggle() }
                }
            }
        }
    }

    // MARK: - 手势（涂抹轨迹跟随手指）

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if currentStroke == nil {
                    currentStroke = Stroke(points: [], isEraser: isEraser, brushSize: brushSize)
                }
                currentStroke?.points.append(value.location)
            }
            .onEnded { _ in
                if let s = currentStroke {
                    strokes.append(s)
                    currentStroke = nil
                }
            }
    }

    private var allStrokes: [Stroke] {
        if let currentStroke {
            return strokes + [currentStroke]
        }
        return strokes
    }

    // MARK: - 渲染灰度蒙版（白=保留，黑=擦除，默认全白=全部保留）

    private func renderMask() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: fittedSize)
        return renderer.image { ctx in
            UIColor.black.setFill()
            ctx.fill(CGRect(origin: .zero, size: fittedSize))
            for stroke in allStrokes {
                guard let first = stroke.points.first else { continue }
                let path = UIBezierPath()
                path.move(to: first)
                for p in stroke.points.dropFirst() { path.addLine(to: p) }
                path.lineWidth = stroke.brushSize
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                (stroke.isEraser ? UIColor.black : UIColor.white).setStroke()
                path.stroke()
            }
        }
    }

    private func downscale(_ img: UIImage, to size: CGSize) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            img.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    // MARK: - 实时预览（保留=原图，擦除=红色蒙版）

    private func previewImage() -> UIImage? {
        guard fittedSize.width > 0, fittedSize.height > 0,
              let base = basePreview, let baseCG = base.cgImage else { return nil }
        let mask = renderMask()
        guard let maskCG = mask.cgImage else { return nil }
        let maskAlpha = CIImage(cgImage: maskCG).applyingFilter("CIMaskToAlpha")

        // 保留笔涂红的地方：50% 透明度红色，透出底下图片；其余=清晰原图
        let red = CIImage(color: CIColor(red: 1, green: 0.25, blue: 0.25, alpha: 0.5))
        let redMasked = red.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: maskAlpha
        ])
        let baseImage = CIImage(cgImage: baseCG)
        let out = redMasked.applyingFilter("CISourceOverCompositing", parameters: [
            kCIInputBackgroundImageKey: baseImage
        ])
        let context = CIContext()
        guard let outCG = context.createCGImage(out, from: baseImage.extent) else { return nil }
        return UIImage(cgImage: outCG)
    }

    // MARK: - 工具栏

    private var toolbar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                modeButton("保留笔", icon: "paintbrush.pointed.fill", active: !isEraser, tint: Color.green) {
                    isEraser = false
                }
                modeButton("擦除笔", icon: "eraser.fill", active: isEraser, tint: Color.red) {
                    isEraser = true
                }
            }

            HStack(spacing: 10) {
                Text("粗细").font(.caption).foregroundColor(AppTheme.secondaryText)
                Slider(value: $brushSize, in: 8...60)
                Text("\(Int(brushSize))")
                    .font(.caption).monospacedDigit()
                    .foregroundColor(AppTheme.secondaryText)
                    .frame(width: 26)
            }

            HStack(spacing: 14) {
                Button { undo() } label: { Label("撤销", systemImage: "arrow.uturn.backward") }
                Button { strokes = [] } label: { Label("清空", systemImage: "trash") }
                Spacer()
                Button("用原图") {
                    dismiss()
                    onUseOriginal()
                }
                .font(.subheadline)
                Button("完成") {
                    if let cutout = generateCutout() {
                        dismiss()
                        onDone(cutout)
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(AppTheme.primaryText)
                .cornerRadius(8)
            }
            .font(.subheadline)
            .foregroundColor(AppTheme.primaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppTheme.cardBackground)
        .overlay(alignment: .top) { Rectangle().fill(AppTheme.divider).frame(height: 1) }
    }

    private func modeButton(_ title: String, icon: String, active: Bool, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.subheadline)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .foregroundColor(active ? .white : AppTheme.secondaryText)
            .background(active ? tint : AppTheme.background)
            .cornerRadius(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(active ? Color.clear : AppTheme.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func undo() {
        if !strokes.isEmpty {
            strokes.removeLast()
        }
    }

    // MARK: - 透明底棋盘格（预览用）

    private var checkerboard: some View {
        Canvas { context, size in
            let square: CGFloat = 12
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    let even = (Int(x / square) + Int(y / square)) % 2 == 0
                    context.fill(
                        Path(CGRect(x: x, y: y, width: square, height: square)),
                        with: .color(even ? Color.white : Color.gray.opacity(0.18))
                    )
                    x += square
                }
                y += square
            }
        }
    }

    // MARK: - 完成：生成带透明通道的抠图结果

    private func generateCutout() -> UIImage? {
        guard let cgImage = image.cgImage, fittedSize.width > 0, fittedSize.height > 0 else { return nil }
        let mask = renderMask()
        guard let maskCG = mask.cgImage else { return nil }
        let maskAlpha = CIImage(cgImage: maskCG).applyingFilter("CIMaskToAlpha")

        let ci = CIImage(cgImage: cgImage)
        // 把蒙版缩放到原图的真实像素尺寸，避免设备缩放导致与预览错位
        let scaledMask = maskAlpha.transformed(by: CGAffineTransform(
            scaleX: ci.extent.width / maskAlpha.extent.width,
            y: ci.extent.height / maskAlpha.extent.height
        ))

        let out = ci.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: scaledMask
        ])
        let context = CIContext()
        guard let outCG = context.createCGImage(out, from: ci.extent) else { return nil }
        return UIImage(cgImage: outCG)
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
}
