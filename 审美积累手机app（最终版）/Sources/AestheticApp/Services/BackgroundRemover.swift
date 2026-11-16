import UIKit
import Vision
import CoreImage

enum Platform {
    static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
}

/// 本地抠图：用 Vision 前景实例分割，把主体从背景中抠出（离线免费）
enum BackgroundRemover {
    /// 异步抠图：在后台线程执行 Vision，绝不阻塞主线程；失败返回 nil（自动降级手动抠像）
    static func removeBackground(from image: UIImage) async -> UIImage? {
        // 模拟器上 Vision 前景分割不稳定（会卡死/崩溃），直接返回失败走手动抠像
        if Platform.isSimulator {
            return nil
        }
        // 放到后台线程执行，全程不阻塞主线程
        return await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let cg = image.cgImage else { return nil }
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            do {
                try handler.perform([request])
                guard let observation = request.results?.first,
                      !observation.allInstances.isEmpty else { return nil }
                let maskBuffer = try observation.generateScaledMaskForImage(
                    forInstances: observation.allInstances,
                    from: handler
                )
                return apply(maskBuffer, to: cg)
            } catch {
                print("抠图失败: \(error)")
                return nil
            }
        }.value
    }

    private static func apply(_ maskBuffer: CVPixelBuffer, to cg: CGImage) -> UIImage? {
        let ciImage = CIImage(cgImage: cg)
        let maskImage = CIImage(cvPixelBuffer: maskBuffer)
        let output = ciImage.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: maskImage
        ])
        let context = CIContext()
        guard let outputCG = context.createCGImage(output, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: outputCG)
    }
}
