import Foundation
import CoreLocation

/// 某一天的天气（最低 / 最高温度 + 天气现象）
struct Weather: Equatable {
    let date: Date
    let minTemp: Double
    let maxTemp: Double
    let code: Int

    var symbolName: String {
        switch code {
        case 0, 1: return "sun.max"
        case 2: return "cloud.sun"
        case 3: return "cloud"
        case 45, 48: return "cloud.fog"
        case 51, 53, 55, 56, 57: return "cloud.drizzle"
        case 61, 63, 65, 66, 67, 80, 81, 82: return "cloud.rain"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow"
        case 95, 96, 99: return "cloud.bolt.rain"
        default: return "cloud.sun"
        }
    }

    var conditionText: String {
        switch code {
        case 0: return "晴"
        case 1: return "晴朗"
        case 2: return "多云"
        case 3: return "阴"
        case 45, 48: return "雾"
        case 51, 53, 55: return "毛毛雨"
        case 56, 57, 66, 67: return "冻雨"
        case 61, 63, 65: return "雨"
        case 71, 73, 75, 77: return "雪"
        case 80, 81, 82: return "阵雨"
        case 85, 86: return "阵雪"
        case 95: return "雷阵雨"
        case 96, 99: return "雷暴冰雹"
        default: return "多云"
        }
    }
}

/// 定位并按需拉取任意一天的天气（历史用 archive，今天/未来用 forecast；Open-Meteo 免费接口）
final class WeatherStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    /// 按日期缓存天气，key 为 "yyyy-MM-dd"
    @Published private(set) var weatherByDay: [String: Weather] = [:]
    /// 定位到的地点名（如城市 / 区）
    @Published private(set) var placeName: String?

    static let shared = WeatherStore()

    private let manager = CLLocationManager()
    /// 反地理编码器需保持引用，否则局部变量被释放后回调不会触发
    private let geocoder = CLGeocoder()
    private var location: CLLocation?
    private var started = false
    /// 定位成功前先记下要拉取的日期，等拿到定位再补拉
    private var pendingKeys: Set<String> = []

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// 请求定位（幂等），视图按需调用 loadWeather(for:) 拉取具体某天
    func load() {
        guard !started else { return }
        started = true
        manager.requestWhenInUseAuthorization()
    }

    func weather(for date: Date) -> Weather? {
        weatherByDay[Self.key(for: date)]
    }

    /// 拉取某一天的天气（已有缓存则跳过）
    func loadWeather(for date: Date) {
        let key = Self.key(for: date)
        guard weatherByDay[key] == nil else { return }
        pendingKeys.insert(key)
        fetchPendingIfPossible()
    }

    private static func key(for date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private func fetchPendingIfPossible() {
        guard let location else { return }
        let keys = pendingKeys
        pendingKeys.removeAll()
        for key in keys {
            Task { await fetchDaily(key: key, lat: location.coordinate.latitude, lon: location.coordinate.longitude) }
        }
    }

    private func fetchDaily(key: String, lat: Double, lon: Double) async {
        guard let date = Self.dayFormatter.date(from: key) else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let target = cal.startOfDay(for: date)

        // 历史日期用 archive API，今天/未来用 forecast API
        let api = target < today
            ? "https://archive-api.open-meteo.com/v1/archive"
            : "https://api.open-meteo.com/v1/forecast"
        let urlString = "\(api)?latitude=\(lat)&longitude=\(lon)&daily=temperature_2m_max,temperature_2m_min,weathercode&timezone=auto&start_date=\(key)&end_date=\(key)"

        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let daily = obj["daily"] as? [String: Any],
              let maxs = daily["temperature_2m_max"] as? [Double], let max = maxs.first,
              let mins = daily["temperature_2m_min"] as? [Double], let min = mins.first,
              let codes = daily["weathercode"] as? [Int] else { return }
        let code = codes.first ?? 0

        let weather = Weather(date: target, minTemp: min, maxTemp: max, code: code)
        await MainActor.run {
            weatherByDay[key] = weather
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
        fetchPendingIfPossible()
        if let loc = locations.last {
            reverseGeocode(loc)
        }
    }

    /// 反地理编码拿到地点名（城市 / 区）
    private func reverseGeocode(_ loc: CLLocation) {
        geocoder.reverseGeocodeLocation(loc) { [weak self] placemarks, _ in
            guard let self, let pm = placemarks?.first else { return }
            let name = pm.locality ?? pm.subLocality ?? pm.administrativeArea
            DispatchQueue.main.async {
                self.placeName = name
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 定位失败则保持无天气显示
    }
}
