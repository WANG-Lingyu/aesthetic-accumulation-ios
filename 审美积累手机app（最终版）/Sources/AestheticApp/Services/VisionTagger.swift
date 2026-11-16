import UIKit
import Vision

/// 本地 AI 打标签：用 iPhone 自带 Vision 识别场景 / 人物姿势（离线免费）
enum VisionTagger {
    static func extractTags(from image: UIImage) -> [String] {
        // 模拟器上 Vision 模型不稳定（会卡死/崩溃），跳过 AI 打标签；真机正常
        if Platform.isSimulator { return [] }
        guard let cg = image.cgImage else { return [] }
        var tags: [String] = []

        // 场景分类
        do {
            let req = VNClassifyImageRequest()
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            try handler.perform([req])
            if let results = req.results?.prefix(3) {
                for r in results where r.confidence > 0.35 {
                    tags.append("场景·" + mapScene(r.identifier))
                }
            }
        } catch {}

        // 人体姿势（有完整人像则加「人物」）
        do {
            let req = VNDetectHumanBodyPoseRequest()
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            try handler.perform([req])
            if let results = req.results, !results.isEmpty {
                tags.append("人物")
            }
        } catch {}

        return Array(Set(tags)).sorted()
    }

    private static func mapScene(_ id: String) -> String {
        let map: [String: String] = [
            "outdoor": "户外", "indoor": "室内", "beach": "海滩", "street": "街头",
            "restaurant": "餐厅", "garden": "花园", "city": "城市", "nature": "自然",
            "forest": "森林", "mountain": "山景", "water": "水景", "sky": "天空",
            "room": "房间", "livingRoom": "客厅", "bedroom": "卧室", "kitchen": "厨房"
        ]
        return map[id] ?? id
    }
}
