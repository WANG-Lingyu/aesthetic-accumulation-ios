import UIKit

/// 本地取色算法：图像降采样 + 颜色量化，输出前 n 个主色（无需 AI）
enum ColorExtractor {
    static func extract(from image: UIImage, count: Int = 5) -> [ColorInfo] {
        guard let cg = image.cgImage else { return [] }

        let targetWidth = 64
        let scale = CGFloat(cg.width) / CGFloat(targetWidth)
        let targetHeight = max(1, Int(CGFloat(cg.height) / scale))

        guard let ctx = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: targetWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }

        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        guard let data = ctx.data else { return [] }

        let pixelCount = targetWidth * targetHeight
        let buffer = data.bindMemory(to: UInt8.self, capacity: pixelCount * 4)

        var buckets: [Int: (r: Int, g: Int, b: Int, count: Int)] = [:]
        for i in 0..<pixelCount {
            let o = i * 4
            if Int(buffer[o + 3]) < 128 { continue }
            let r = Int(buffer[o])
            let g = Int(buffer[o + 1])
            let b = Int(buffer[o + 2])
            let key = quantize(r: r, g: g, b: b)
            var bucket = buckets[key] ?? (r: 0, g: 0, b: 0, count: 0)
            bucket.r += r
            bucket.g += g
            bucket.b += b
            bucket.count += 1
            buckets[key] = bucket
        }

        let total = max(1, buckets.values.reduce(0) { $0 + $1.count })
        let top = buckets.values.sorted { $0.count > $1.count }.prefix(count)

        return top.map { b in
            let r = b.r / b.count
            let g = b.g / b.count
            let bl = b.b / b.count
            let hex = String(format: "#%02X%02X%02X", r, g, bl)
            return ColorInfo(hex: hex, share: Double(b.count) / Double(total))
        }
    }

    private static func quantize(r: Int, g: Int, b: Int) -> Int {
        (r / 64 << 4) | (g / 64 << 2) | (b / 64)
    }

    // MARK: - 颜色中文名（供展示与搜索）

    static func colorName(hex: String) -> String {
        let (r, g, b) = rgb(fromHex: hex)
        return colorName(r: r, g: g, b: b)
    }

    private static func rgb(fromHex hex: String) -> (Int, Int, Int) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        return (Int((value >> 16) & 0xFF), Int((value >> 8) & 0xFF), Int(value & 0xFF))
    }

    private static func colorName(r: Int, g: Int, b: Int) -> String {
        let rf = Double(r) / 255.0
        let gf = Double(g) / 255.0
        let bf = Double(b) / 255.0
        let maxC = max(rf, max(gf, bf))
        let minC = min(rf, min(gf, bf))
        let v = maxC
        let d = maxC - minC

        var h: Double = 0
        if d > 0.0001 {
            if maxC == rf {
                h = (gf - bf) / d
                if h < 0 { h += 6 }
            } else if maxC == gf {
                h = (bf - rf) / d + 2
            } else {
                h = (rf - gf) / d + 4
            }
            h *= 60
        }
        let s = v > 0 ? d / v : 0

        if s < 0.12 {
            if v < 0.15 { return "黑色" }
            if v > 0.90 { return "白色" }
            return "灰色"
        }
        if v > 0.85 && s < 0.30 && h >= 15 && h < 70 { return "米色" }
        if h >= 15 && h < 50 && (s < 0.5 || v < 0.65) { return "棕色" }
        if h < 15 { return "红色" }
        if h < 45 { return "橙色" }
        if h < 70 { return "黄色" }
        if h < 160 { return "绿色" }
        if h < 200 { return "青色" }
        if h < 260 { return "蓝色" }
        if h < 320 { return "紫色" }
        return "粉色"
    }
}
