import Foundation

enum Format {
    static func distance(meters: Int, language: Language = .current) -> String {
        if meters < 1000 {
            return "\(meters) m"
        }
        return String(format: "%.1f km", locale: language.locale, Double(meters) / 1000)
    }

    static func approximateDistance(meters: Double, language: Language = .current) -> String {
        let step: Double = meters < 1000 ? 10 : 100
        return distance(meters: Int((meters / step).rounded() * step), language: language)
    }

    static func duration(seconds: Double, language: Language = .current) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        if minutes < 60 {
            return Strings.format("format.minutes", minutes, language: language)
        }
        return Strings.format("format.hoursMinutes", minutes / 60, minutes % 60, language: language)
    }

    static func speed(kmh: Double, language: Language = .current) -> String {
        "\(Int(kmh.rounded())) \(Strings.tr("ride.kmh", language: language))"
    }

    static func clockTime(_ date: Date, timeZone: TimeZone = .current, language: Language = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("HHmm")
        return formatter.string(from: date)
    }

    static func dayTime(_ date: Date, timeZone: TimeZone = .current, language: Language = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.timeZone = timeZone
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
