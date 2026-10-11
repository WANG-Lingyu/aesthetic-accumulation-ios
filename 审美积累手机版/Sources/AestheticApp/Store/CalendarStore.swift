import Foundation
import UIKit
import Combine

/// 日历里的一张照片（独立于素材：有自己的图片文件和备注）
struct CalendarPhoto: Identifiable, Codable {
    let id: String
    var note: String
    var fileName: String

    init(id: String = UUID().uuidString, note: String = "", fileName: String) {
        self.id = id
        self.note = note
        self.fileName = fileName
    }

    private enum CodingKeys: String, CodingKey { case id, note, fileName }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        fileName = try c.decode(String.self, forKey: .fileName)
    }
}

/// 某一天的记录（照片 + 整体备注）
struct CalendarEntry: Identifiable, Codable {
    let id: String
    var date: Date
    var note: String
    var photos: [CalendarPhoto]

    init(id: String = UUID().uuidString, date: Date, note: String = "", photos: [CalendarPhoto] = []) {
        self.id = id
        self.date = date
        self.note = note
        self.photos = photos
    }

    private enum CodingKeys: String, CodingKey { case id, date, note, photos }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        photos = try c.decodeIfPresent([CalendarPhoto].self, forKey: .photos) ?? []
    }
}

/// 日历数据：按天记录照片与备注（与素材完全独立）
final class CalendarStore: ObservableObject {
    @Published var entries: [CalendarEntry] = []
    /// 当前选中的日期（放 Store 里，加号流程可从外部直接跳转定位）
    @Published var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    static let shared = CalendarStore()

    private let jsonURL: URL
    private let imagesURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let root = docs.appendingPathComponent("审美积累", isDirectory: true)
        jsonURL = root.appendingPathComponent("calendar.json")
        imagesURL = root.appendingPathComponent("calendar_images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        entries = Self.load(from: jsonURL) ?? []
    }

    // MARK: - 持久化

    private static func load(from url: URL) -> [CalendarEntry]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([CalendarEntry].self, from: data)
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entries) {
            try? data.write(to: jsonURL, options: .atomic)
        }
    }

    // MARK: - 查询

    /// 某一天是否有记录（有照片或备注非空，月历打点用）
    func hasEntry(on date: Date) -> Bool {
        entries.contains { Calendar.current.isDate($0.date, inSameDayAs: date) && (!$0.photos.isEmpty || !$0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
    }

    /// 按同一天取记录
    func entry(for date: Date) -> CalendarEntry? {
        entries.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    /// 按 id 取记录（照片查看器用）
    func entry(id: String) -> CalendarEntry? {
        entries.first { $0.id == id }
    }

    func imageURL(for photo: CalendarPhoto) -> URL {
        imagesURL.appendingPathComponent(photo.fileName)
    }

    func uiImage(for photo: CalendarPhoto) -> UIImage? {
        UIImage(contentsOfFile: imageURL(for: photo).path)
    }

    // MARK: - 写入

    /// 把图片数据写入日历存储，返回新照片（备注默认空）
    @discardableResult
    private func importImageData(_ data: Data, ext: String) -> CalendarPhoto? {
        let fileName = "\(UUID().uuidString).\(ext)"
        let dest = imagesURL.appendingPathComponent(fileName)
        do {
            try data.write(to: dest)
            return CalendarPhoto(fileName: fileName)
        } catch {
            print("写入日历图片失败: \(error)")
            return nil
        }
    }

    /// 加号「日历」导入：把拍照 / 相册的图存入某一天
    func addPhotos(_ images: [UIImage], to date: Date) {
        var photos: [CalendarPhoto] = []
        for image in images {
            if let data = image.jpegData(compressionQuality: 0.9),
               let p = importImageData(data, ext: "jpg") {
                photos.append(p)
            }
        }
        guard !photos.isEmpty else { return }
        append(photos, to: date)
    }

    /// 从素材导入：把素材照片复制进某一天（素材原图不动）
    func addPhotos(fromLibrary photoIDs: [String], to date: Date) {
        let library = LibraryStore.shared
        var photos: [CalendarPhoto] = []
        for id in photoIDs {
            guard let photo = library.library.photos.first(where: { $0.id == id }) else { continue }
            let url = library.imageURL(for: photo)
            guard let data = try? Data(contentsOf: url) else { continue }
            let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
            if let p = importImageData(data, ext: ext) {
                photos.append(p)
            }
        }
        guard !photos.isEmpty else { return }
        append(photos, to: date)
    }

    /// 把若干照片追加到某一天（不存在则新建）
    private func append(_ photos: [CalendarPhoto], to date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        if let idx = entries.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: day) }) {
            entries[idx].photos.append(contentsOf: photos)
        } else {
            entries.append(CalendarEntry(date: day, photos: photos))
        }
        persist()
    }

    /// 删除某一天里的一张照片（同步删文件）
    func removePhoto(id: String, from entryID: String) {
        guard let idx = entries.firstIndex(where: { $0.id == entryID }) else { return }
        if let p = entries[idx].photos.first(where: { $0.id == id }) {
            try? FileManager.default.removeItem(at: imageURL(for: p))
        }
        entries[idx].photos.removeAll { $0.id == id }
        cleanupIfNeeded()
        persist()
    }

    /// 整体备注（不存在则新建；写空且无照片则清理该天）
    func setEntryNote(_ note: String, for date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        if let idx = entries.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: day) }) {
            entries[idx].note = note
        } else if !note.isEmpty {
            entries.append(CalendarEntry(date: day, note: note))
        }
        cleanupIfNeeded()
        persist()
    }

    /// 照片备注
    func setPhotoNote(_ note: String, photoID: String, in entryID: String) {
        guard let ei = entries.firstIndex(where: { $0.id == entryID }),
              let pi = entries[ei].photos.firstIndex(where: { $0.id == photoID }) else { return }
        entries[ei].photos[pi].note = note
        persist()
    }

    /// 删除既无照片、备注也为空的记录
    private func cleanupIfNeeded() {
        entries.removeAll { $0.photos.isEmpty && $0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
