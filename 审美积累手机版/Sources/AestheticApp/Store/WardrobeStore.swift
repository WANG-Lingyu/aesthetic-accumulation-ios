import Foundation
import UIKit
import Combine

/// 衣橱单品（抠图后的透明底图片 + 品牌 / 尺码 / 价格，均可选填）
struct WardrobeItem: Codable, Identifiable {
    var id: String
    var category: String
    var imageFileName: String
    var createdAt: Date
    var brand: String
    var size: String
    var price: String

    init(id: String = UUID().uuidString, category: String, imageFileName: String,
         createdAt: Date = Date(), brand: String = "", size: String = "", price: String = "") {
        self.id = id
        self.category = category
        self.imageFileName = imageFileName
        self.createdAt = createdAt
        self.brand = brand
        self.size = size
        self.price = price
    }

    private enum CodingKeys: String, CodingKey {
        case id, category, imageFileName, createdAt, brand, size, price
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        category = try c.decode(String.self, forKey: .category)
        imageFileName = try c.decode(String.self, forKey: .imageFileName)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        brand = try c.decodeIfPresent(String.self, forKey: .brand) ?? ""
        size = try c.decodeIfPresent(String.self, forKey: .size) ?? ""
        price = try c.decodeIfPresent(String.self, forKey: .price) ?? ""
    }
}

/// 衣橱数据存储
final class WardrobeStore: ObservableObject {
    @Published var items: [WardrobeItem] = []

    private let rootURL: URL
    private let jsonURL: URL
    private let imagesURL: URL

    static let shared = WardrobeStore()

    static let defaultCategories = ["上装", "下装", "连衣裙", "鞋子", "包包", "首饰", "配饰"]

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        rootURL = docs.appendingPathComponent("审美积累", isDirectory: true)
        jsonURL = rootURL.appendingPathComponent("wardrobe.json")
        imagesURL = rootURL.appendingPathComponent("wardrobe_images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        items = Self.load(from: jsonURL) ?? []
    }

    // MARK: - 持久化

    private static func load(from url: URL) -> [WardrobeItem]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([WardrobeItem].self, from: data)
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(items)
            try data.write(to: jsonURL, options: .atomic)
        } catch {
            print("衣橱保存失败: \(error)")
        }
    }

    // MARK: - 图片

    func addItem(category: String, image: UIImage, brand: String = "", size: String = "", price: String = "") {
        // 裁掉抠图四周的透明边，让缩略图 / 画板里的单品贴合内容、居中
        let finalImage = image.trimmingTransparentEdges() ?? image
        guard let data = finalImage.pngData() else { return }
        let fileName = "\(UUID().uuidString).png"
        let dest = imagesURL.appendingPathComponent(fileName)
        do {
            try data.write(to: dest)
            items.append(WardrobeItem(category: category, imageFileName: fileName,
                                      brand: brand, size: size, price: price))
            save()
        } catch {
            print("写入衣橱图片失败: \(error)")
        }
    }

    func image(for item: WardrobeItem) -> UIImage? {
        UIImage(contentsOfFile: imagesURL.appendingPathComponent(item.imageFileName).path)
    }

    func deleteItem(id: String) {
        if let item = items.first(where: { $0.id == id }) {
            try? FileManager.default.removeItem(at: imagesURL.appendingPathComponent(item.imageFileName))
        }
        items.removeAll { $0.id == id }
        save()
    }
}
