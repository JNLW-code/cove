import Foundation

/// Weather from Open-Meteo (free, no key). One place to look up: the city set in the menu, Sydney by default.
/// Refreshes on a one-shot timer every 30 min and when the island opens after 15 min.
@MainActor
@Observable
final class WeatherModel {
    private(set) var now: WeatherNow?
    private(set) var city: String
    private var latitude: Double?
    private var longitude: Double?
    private var fetchedAt = Date.distantPast
    private var refreshTask: Task<Void, Never>?
    var onChange: (() -> Void)?

    static let refreshEvery: TimeInterval = 30 * 60
    static let staleAfter: TimeInterval = 15 * 60

    init() {
        city = UserDefaults.standard.string(forKey: "weatherCity") ?? "Sydney"
        if let lat = UserDefaults.standard.object(forKey: "weatherLat") as? Double,
           let lon = UserDefaults.standard.object(forKey: "weatherLon") as? Double { latitude = lat; longitude = lon }
        scheduleRefresh(after: 1)
    }

    func setCity(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        city = trimmed
        latitude = nil
        longitude = nil
        now = nil
        UserDefaults.standard.set(trimmed, forKey: "weatherCity")
        UserDefaults.standard.removeObject(forKey: "weatherLat")
        UserDefaults.standard.removeObject(forKey: "weatherLon")
        onChange?()
        scheduleRefresh(after: 0.1)
    }

    /// Called when the island opens: refresh if the reading is older than 15 min.
    func islandOpened() {
        if Date().timeIntervalSince(fetchedAt) > Self.staleAfter { scheduleRefresh(after: 0.1) }
    }

    private func scheduleRefresh(after seconds: TimeInterval) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds), tolerance: .seconds(min(60, seconds / 4 + 1)))
            guard let self, !Task.isCancelled else { return }
            await self.refresh()
            guard !Task.isCancelled else { return }
            // A failed fetch (no network yet, city not found) retries after a minute, not half an hour.
            let gotData = Date().timeIntervalSince(self.fetchedAt) < 60
            self.scheduleRefresh(after: gotData ? Self.refreshEvery : 60)
        }
    }

    private func refresh() async {
        if latitude == nil { await geocode() }
        guard let latitude, let longitude else { return }
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(latitude)), .init(name: "longitude", value: String(longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            .init(name: "forecast_days", value: "1"), .init(name: "timezone", value: "auto"),
        ]
        guard let url = components.url, let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let current = json["current"] as? [String: Any], let daily = json["daily"] as? [String: Any],
              let temp = current["temperature_2m"] as? Double, let code = current["weather_code"] as? Int,
              let highs = daily["temperature_2m_max"] as? [Double], let lows = daily["temperature_2m_min"] as? [Double],
              let high = highs.first, let low = lows.first else {
            Log.app.error("Weather refresh failed")
            return
        }
        let day = (current["is_day"] as? Int ?? 1) == 1
        now = WeatherNow(temperature: Int(temp.rounded()), high: Int(high.rounded()), low: Int(low.rounded()),
                         symbol: Self.symbol(code: code, day: day), city: city)
        fetchedAt = Date()
        onChange?()
    }

    private func geocode() async {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [.init(name: "name", value: city), .init(name: "count", value: "1"), .init(name: "language", value: "en")]
        guard let url = components.url, let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let first = (json["results"] as? [[String: Any]])?.first,
              let lat = first["latitude"] as? Double, let lon = first["longitude"] as? Double else {
            Log.app.error("Weather: city not found")
            return
        }
        latitude = lat
        longitude = lon
        if let name = first["name"] as? String { city = name; UserDefaults.standard.set(name, forKey: "weatherCity") }
        UserDefaults.standard.set(lat, forKey: "weatherLat")
        UserDefaults.standard.set(lon, forKey: "weatherLon")
    }

    /// WMO weather code → SF Symbol.
    static func symbol(code: Int, day: Bool) -> String {
        switch code {
        case 0: day ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: day ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55, 56, 57: "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67, 80, 81, 82: "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }
}
