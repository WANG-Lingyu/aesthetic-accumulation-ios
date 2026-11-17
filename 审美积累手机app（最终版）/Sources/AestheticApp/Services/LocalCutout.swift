import UIKit
import Foundation

/// 本地 AI 抠图：调用 withoutBG Mac 应用的 Local API
///
/// 前提：在 Mac 上安装 withoutBG，并点菜单栏图标 → 「Start Local API」（默认 http://127.0.0.1:8000）。
/// 免费、离线、私有，图片不出本机。模拟器与 Mac 共享 loopback，可直接访问 127.0.0.1。
///
/// 接口：POST /v1/remove-background，body 为原始图片字节（image/jpeg），返回透明 PNG。
enum LocalCutout {

    private static let endpoint = URL(string: "http://127.0.0.1:8000/v1/remove-background")!

    /// 异步抠图：成功返回 (透明图, nil)；失败返回 (nil, 错误描述)
    static func removeBackground(from image: UIImage) async -> (image: UIImage?, error: String?) {
        // 全程后台线程执行，不阻塞主线程
        return await Task.detached(priority: .userInitiated) { () -> (UIImage?, String?) in
            guard let jpeg = image.jpegData(compressionQuality: 0.95) else {
                return (nil, "图片处理失败")
            }

            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.timeoutInterval = 120   // 本地模型首次推理可能较慢
            request.httpBody = jpeg
            request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    return (nil, "响应异常")
                }
                guard http.statusCode == 200 else {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    return (nil, "HTTP \(http.statusCode) \(body.prefix(200))")
                }
                guard let img = UIImage(data: data) else {
                    return (nil, "返回的不是有效图片")
                }
                print("本地抠图：成功")
                return (img, nil)
            } catch {
                let ns = error as NSError
                let msg = "无法连接本地抠图服务（\(ns.localizedDescription)）"
                print("本地抠图：domain=\(ns.domain) code=\(ns.code) \(ns.localizedDescription)")
                return (nil, msg + "\n请确认已安装 withoutBG 并点菜单栏「Start Local API」")
            }
        }.value
    }
}
