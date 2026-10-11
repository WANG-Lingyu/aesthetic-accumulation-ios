import Foundation
import UIKit
import Combine

/// 画板上的单品：位置 / 缩放 / 旋转
struct CanvasItem: Identifiable, Codable {
    let id: UUID
    var wardrobeItemId: String
    var x: CGFloat
    var y: CGFloat
    var scale: CGFloat
    var rotation: Double

    init(id: UUID = UUID(), wardrobeItemId: String, x: CGFloat, y: CGFloat, scale: CGFloat, rotation: Double) {
        self.id = id
        self.wardrobeItemId = wardrobeItemId
        self.x = x
        self.y = y
        self.scale = scale
        self.rotation = rotation
    }
}

/// 草稿箱里的搭配方案
struct OutfitDraft: Identifiable, Codable {
    let id: UUID
    var name: String
    var createdAt: Date
    var items: [CanvasItem]
    var canvasWidth: CGFloat
    var canvasHeight: CGFloat

    init(id: UUID = UUID(), name: String, createdAt: Date = Date(), items: [CanvasItem], canvasWidth: CGFloat, canvasHeight: CGFloat) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.items = items
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt, items, canvasWidth, canvasHeight
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        items = try c.decode([CanvasItem].self, forKey: .items)
        canvasWidth = try c.decodeIfPresent(CGFloat.self, forKey: .canvasWidth) ?? 300
        canvasHeight = try c.decodeIfPresent(CGFloat.self, forKey: .canvasHeight) ?? 700
    }
}

/// 搭配数据：当前画板 + 草稿箱
final class OutfitStore: ObservableObject {
    @Published var currentItems: [CanvasItem] = []
    @Published var drafts: [OutfitDraft] = []
    /// 当前画板是从哪个草稿打开的（nil 表示是新建画板）
    @Published var currentDraftID: UUID?

    static let shared = OutfitStore()

    private let draftsURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let root = docs.appendingPathComponent("审美积累", isDirectory: true)
        draftsURL = root.appendingPathComponent("outfit_drafts.json")
        drafts = Self.load(from: draftsURL) ?? []
    }

    private static func load(from url: URL) -> [OutfitDraft]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([OutfitDraft].self, from: data)
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(drafts) {
            try? data.write(to: draftsURL, options: .atomic)
        }
    }

    func saveDraft(name: String, items: [CanvasItem], canvasSize: CGSize) {
        drafts.append(OutfitDraft(
            id: UUID(),
            name: name,
            createdAt: Date(),
            items: items,
            canvasWidth: canvasSize.width,
            canvasHeight: canvasSize.height
        ))
        persist()
    }

    func deleteDraft(id: UUID) {
        drafts.removeAll { $0.id == id }
        persist()
    }

    /// 把新操作保存回原草稿
    func updateDraft(id: UUID, items: [CanvasItem], canvasSize: CGSize) {
        if let idx = drafts.firstIndex(where: { $0.id == id }) {
            drafts[idx].items = items
            drafts[idx].canvasWidth = canvasSize.width
            drafts[idx].canvasHeight = canvasSize.height
            persist()
        }
    }

    func renameDraft(id: UUID, newName: String) {
        if let idx = drafts.firstIndex(where: { $0.id == id }) {
            let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                drafts[idx].name = trimmed
                persist()
            }
        }
    }

    /// 生成一个默认草稿名
    func nextDraftName() -> String {
        "草稿 \(drafts.count + 1)"
    }

    /// 把一组画板单品渲染成图片（画板导出 / 草稿缩略图共用）
    static func renderCanvas(items: [CanvasItem], canvasSize: CGSize, wardrobe: WardrobeStore, outputSize: CGSize) -> UIImage? {
        guard canvasSize.width > 0, canvasSize.height > 0, outputSize.width > 0, outputSize.height > 0 else { return nil }
        let s = min(outputSize.width / canvasSize.width, outputSize.height / canvasSize.height)
        let offsetX = (outputSize.width - canvasSize.width * s) / 2
        let offsetY = (outputSize.height - canvasSize.height * s) / 2
        let renderer = UIGraphicsImageRenderer(size: outputSize)
        return renderer.image { ctx in
            UIColor(red: 247/255, green: 242/255, blue: 236/255, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: outputSize))
            for item in items {
                guard let wi = wardrobe.items.first(where: { $0.id == item.wardrobeItemId }),
                      let img = wardrobe.image(for: wi) else { continue }
                let w = 130 * item.scale * s
                let h = w * img.size.height / img.size.width
                ctx.cgContext.saveGState()
                ctx.cgContext.translateBy(x: offsetX + item.x * s, y: offsetY + item.y * s)
                ctx.cgContext.rotate(by: item.rotation)
                img.draw(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
                ctx.cgContext.restoreGState()
            }
        }
    }
}
