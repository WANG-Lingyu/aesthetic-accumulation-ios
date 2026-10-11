import Foundation
import UIKit
import Combine

/// 负责库数据的读写与图片文件管理（iOS 用 Documents 目录）
final class LibraryStore: ObservableObject {
    @Published var library: Library

    private let rootURL: URL
    private let libraryURL: URL
    private let imagesURL: URL

    static let shared = LibraryStore()

    private init() {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        rootURL = docs.appendingPathComponent("审美积累", isDirectory: true)
        libraryURL = rootURL.appendingPathComponent("library.json")
        imagesURL = rootURL.appendingPathComponent("images", isDirectory: true)
        try? fm.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        library = Self.load(from: libraryURL) ?? Library()
    }

    // MARK: - 持久化

    private static func load(from url: URL) -> Library? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Library.self, from: data)
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(library)
            try data.write(to: libraryURL, options: .atomic)
        } catch {
            print("保存失败: \(error)")
        }
    }

    // MARK: - 图片文件

    /// 导入图片数据，写入库并返回 Photo（同时计算感知哈希用于查重）
    @discardableResult
    func importImage(_ data: Data, ext: String = "jpg") -> Photo? {
        let fileName = "\(UUID().uuidString).\(ext)"
        let dest = imagesURL.appendingPathComponent(fileName)
        do {
            try data.write(to: dest)
            var photo = Photo(fileName: fileName)
            if let image = UIImage(data: data) {
                photo.phash = ImageHasher.averageHash(image)
                photo.colors = ColorExtractor.extract(from: image)
            }
            library.photos.append(photo)
            save()
            return photo
        } catch {
            print("写入图片失败: \(error)")
            return nil
        }
    }

    /// 找出与给定照片近似重复的已有照片（汉明距离 < 阈值）
    func findDuplicates(for photoIDs: [String], threshold: Int = 10) -> [(new: Photo, existing: Photo)] {
        var result: [(Photo, Photo)] = []
        let newPhotos = library.photos.filter { photoIDs.contains($0.id) && $0.phash != 0 }
        let others = library.photos.filter { !photoIDs.contains($0.id) && $0.phash != 0 }
        for newPhoto in newPhotos {
            if let dup = others.first(where: { ImageHasher.distance(newPhoto.phash, $0.phash) < threshold }) {
                result.append((new: newPhoto, existing: dup))
            }
        }
        return result
    }

    func imageURL(for photo: Photo) -> URL {
        imagesURL.appendingPathComponent(photo.fileName)
    }

    func uiImage(for photo: Photo) -> UIImage? {
        UIImage(contentsOfFile: imageURL(for: photo).path)
    }

    /// 用本地 Vision 给照片自动打标签（异步）
    func generateTags(for photoID: String) {
        guard let photo = library.photos.first(where: { $0.id == photoID }),
              let image = uiImage(for: photo) else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let tags = VisionTagger.extractTags(from: image)
            DispatchQueue.main.async {
                guard let self else { return }
                if let idx = self.library.photos.firstIndex(where: { $0.id == photoID }) {
                    self.library.photos[idx].tags = tags
                    self.save()
                }
            }
        }
    }

    // MARK: - 图片操作

    func deletePhoto(id: String) {
        if let photo = library.photos.first(where: { $0.id == id }) {
            try? FileManager.default.removeItem(at: imageURL(for: photo))
        }
        library.photos.removeAll { $0.id == id }
        for i in library.albums.indices {
            library.albums[i].photoIds.removeAll { $0 == id }
            if library.albums[i].coverPhotoId == id { library.albums[i].coverPhotoId = nil }
        }
        save()
    }

    func updatePhoto(_ photo: Photo) {
        if let idx = library.photos.firstIndex(where: { $0.id == photo.id }) {
            library.photos[idx] = photo
            save()
        }
    }

    // MARK: - 册子操作

    @discardableResult
    func addAlbum(name: String) -> Album {
        let album = Album(name: name)
        library.albums.append(album)
        save()
        return album
    }

    /// 保证存在默认「搭配」册子
    @discardableResult
    func ensureOutfitAlbum() -> Album {
        if let existing = library.albums.first(where: { $0.name == "搭配" }) {
            return existing
        }
        return addAlbum(name: "搭配")
    }

    /// 把搭配导出图直接存进默认「搭配」册子
    @discardableResult
    func exportToOutfitAlbum(_ data: Data) -> Photo? {
        guard let photo = importImage(data, ext: "png") else { return nil }
        let album = ensureOutfitAlbum()
        if let idx = library.albums.firstIndex(where: { $0.id == album.id }) {
            library.albums[idx].photoIds.append(photo.id)
            save()
        }
        return photo
    }

    func renameAlbum(id: String, to newName: String) {
        if let idx = library.albums.firstIndex(where: { $0.id == id }) {
            library.albums[idx].name = newName
            save()
        }
    }

    func deleteAlbum(id: String) {
        library.albums.removeAll { $0.id == id }
        save()
    }

    func togglePhoto(_ photoId: String, in albumId: String) {
        if let idx = library.albums.firstIndex(where: { $0.id == albumId }) {
            if let p = library.albums[idx].photoIds.firstIndex(of: photoId) {
                library.albums[idx].photoIds.remove(at: p)
            } else {
                library.albums[idx].photoIds.append(photoId)
            }
            save()
        }
    }

    func mergeAlbum(source: String, into target: String) {
        guard let si = library.albums.firstIndex(where: { $0.id == source }),
              let ti = library.albums.firstIndex(where: { $0.id == target }) else { return }
        for pid in library.albums[si].photoIds where !library.albums[ti].photoIds.contains(pid) {
            library.albums[ti].photoIds.append(pid)
        }
        library.albums.remove(at: si)
        save()
    }

    func setPhotos(_ photoIDs: [String], in albumID: String, to isIn: Bool) {
        guard let idx = library.albums.firstIndex(where: { $0.id == albumID }) else { return }
        for pid in photoIDs {
            if isIn {
                if !library.albums[idx].photoIds.contains(pid) {
                    library.albums[idx].photoIds.append(pid)
                }
            } else {
                library.albums[idx].photoIds.removeAll { $0 == pid }
            }
        }
        save()
    }

    func movePhoto(_ photoID: String, before targetID: String, in albumID: String) {
        guard let idx = library.albums.firstIndex(where: { $0.id == albumID }) else { return }
        var ids = library.albums[idx].photoIds
        guard let from = ids.firstIndex(of: photoID), photoID != targetID else { return }
        ids.remove(at: from)
        let target = ids.firstIndex(of: targetID) ?? ids.count
        ids.insert(photoID, at: target)
        library.albums[idx].photoIds = ids
        save()
    }

    func setCover(photoID: String, for albumID: String) {
        guard let idx = library.albums.firstIndex(where: { $0.id == albumID }) else { return }
        library.albums[idx].coverPhotoId = photoID
        save()
    }

    func deletePhotos(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        for id in ids {
            if let photo = library.photos.first(where: { $0.id == id }) {
                try? FileManager.default.removeItem(at: imageURL(for: photo))
            }
        }
        library.photos.removeAll { ids.contains($0.id) }
        for i in library.albums.indices {
            library.albums[i].photoIds.removeAll { ids.contains($0) }
            if let cover = library.albums[i].coverPhotoId, ids.contains(cover) {
                library.albums[i].coverPhotoId = nil
            }
        }
        save()
    }
}
