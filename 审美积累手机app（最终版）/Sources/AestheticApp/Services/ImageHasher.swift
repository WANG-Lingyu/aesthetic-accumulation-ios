import UIKit

/// 感知哈希：用于查重（相似图片判断，本地计算无需 AI）
enum ImageHasher {
    /// 平均哈希（8x8 灰度 → 64 位）
    static func averageHash(_ image: UIImage) -> UInt64 {
        let side = 8
        guard let gray = grayscale(image, width: side, height: side),
              let data = gray.dataProvider?.data else { return 0 }
        let bytes = CFDataGetBytePtr(data)!
        let count = side * side
        let avg = (0..<count).reduce(0) { $0 + Int(bytes[$1]) } / count
        var hash: UInt64 = 0
        for i in 0..<count {
            if Int(bytes[i]) >= avg {
                hash |= (UInt64(1) << (63 - i))
            }
        }
        return hash
    }

    private static func grayscale(_ image: UIImage, width: Int, height: Int) -> CGImage? {
        guard let cg = image.cgImage else { return nil }
        let space = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width,
                                  space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()
    }

    /// 汉明距离（越小越相似，< 10 视为重复）
    static func distance(_ a: UInt64, _ b: UInt64) -> Int {
        var x = a ^ b
        var count = 0
        while x != 0 {
            x &= x - 1
            count += 1
        }
        return count
    }
}
