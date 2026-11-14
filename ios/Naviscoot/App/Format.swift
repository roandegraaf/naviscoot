import Foundation

enum Format {
    static func distance(meters: Int) -> String {
        if meters < 1000 {
            return "\(meters) m"
        }
        return String(format: "%.1f km", locale: Locale(identifier: "en_US_POSIX"), Double(meters) / 1000)
    }

    static func duration(seconds: Double) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        if minutes < 60 {
            return "\(minutes) min"
        }
        return "\(minutes / 60) h \(minutes % 60) min"
    }

    static func clockTime(_ date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
