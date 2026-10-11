import Foundation

/// 图片状态标记：无 / 喜欢 / 备用 / 待复盘
enum PhotoStatus: String, Codable, CaseIterable {
    case none
    case like
    case backup
    case review
}

/// 圈选图形
enum RegionShape: String, Codable, CaseIterable {
    case rect
    case ellipse
}

/// 图片上的局部圈选标注（坐标归一化 0~1）
struct Region: Codable, Identifiable, Equatable {
    var id: String
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var note: String
    var shape: RegionShape
    var colorHex: String
    /// 备注文字位置（归一化，-1 表示自动放在框上方/下方）
    var labelX: Double
    var labelY: Double
    var noteHidden: Bool
    var noteWidth: Double

    init(id: String = UUID().uuidString, x: Double, y: Double, width: Double, height: Double,
         note: String = "", shape: RegionShape = .rect, colorHex: String = "#2A3B4E",
         labelX: Double = -1, labelY: Double = -1,
         noteHidden: Bool = false, noteWidth: Double = 0) {
        self.id = id
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.note = note
        self.shape = shape
        self.colorHex = colorHex
        self.labelX = labelX
        self.labelY = labelY
        self.noteHidden = noteHidden
        self.noteWidth = noteWidth
    }

    enum CodingKeys: String, CodingKey {
        case id, x, y, width, height, note, shape, colorHex, labelX, labelY, noteHidden, noteWidth
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        x = try c.decode(Double.self, forKey: .x)
        y = try c.decode(Double.self, forKey: .y)
        width = try c.decode(Double.self, forKey: .width)
        height = try c.decode(Double.self, forKey: .height)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        shape = try c.decodeIfPresent(RegionShape.self, forKey: .shape) ?? .rect
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#2A3B4E"
        labelX = try c.decodeIfPresent(Double.self, forKey: .labelX) ?? -1
        labelY = try c.decodeIfPresent(Double.self, forKey: .labelY) ?? -1
        noteHidden = try c.decodeIfPresent(Bool.self, forKey: .noteHidden) ?? false
        noteWidth = try c.decodeIfPresent(Double.self, forKey: .noteWidth) ?? 0
    }
}

/// 主色卡里的一格颜色
struct ColorInfo: Codable, Equatable {
    var hex: String
    var share: Double
}

/// 一张素材图片
struct Photo: Codable, Identifiable, Equatable {
    var id: String
    var fileName: String
    var importedAt: Date
    var note: String
    var status: PhotoStatus
    var tags: [String]
    var colors: [ColorInfo]
    var regions: [Region]
    var phash: UInt64

    init(id: String = UUID().uuidString, fileName: String, importedAt: Date = Date(),
         note: String = "", status: PhotoStatus = .none, tags: [String] = [],
         colors: [ColorInfo] = [], regions: [Region] = [], phash: UInt64 = 0) {
        self.id = id
        self.fileName = fileName
        self.importedAt = importedAt
        self.note = note
        self.status = status
        self.tags = tags
        self.colors = colors
        self.regions = regions
        self.phash = phash
    }

    enum CodingKeys: String, CodingKey {
        case id, fileName, importedAt, note, status, tags, colors, regions, phash
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        fileName = try c.decode(String.self, forKey: .fileName)
        importedAt = try c.decodeIfPresent(Date.self, forKey: .importedAt) ?? Date()
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        status = try c.decodeIfPresent(PhotoStatus.self, forKey: .status) ?? .none
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        colors = try c.decodeIfPresent([ColorInfo].self, forKey: .colors) ?? []
        regions = try c.decodeIfPresent([Region].self, forKey: .regions) ?? []
        phash = try c.decodeIfPresent(UInt64.self, forKey: .phash) ?? 0
    }
}

/// 册子（分类文件夹），一张图可进多个册子
struct Album: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var createdAt: Date = Date()
    var coverPhotoId: String? = nil
    var photoIds: [String] = []
}

/// 整个库的数据
struct Library: Codable {
    var version: Int = 1
    var photos: [Photo] = []
    var albums: [Album] = []
}
