import Foundation

enum SolarTimes {
    struct Day: Equatable {
        let sunrise: Date
        let sunset: Date
    }

    static let fallbackCoordinate = Coordinate(lat: 52.0907, lon: 5.1214)

    private static let j2000 = 2_451_545.0
    private static let unixEpochJulian = 2_440_587.5

    // NOAA solar calculator equations, evaluated once at the UTC day's noon (about a minute of error at Dutch latitudes).
    static func day(containing date: Date, at coordinate: Coordinate) -> Day? {
        let midnight = (date.timeIntervalSince1970 / 86400).rounded(.down) * 86400
        let century = ((midnight + 43200) / 86400 + unixEpochJulian - j2000) / 36525
        let meanLongitude = normalized(280.46646 + century * (36000.76983 + century * 0.0003032))
        let meanAnomaly = 357.52911 + century * (35999.05029 - 0.0001537 * century)
        let eccentricity = 0.016708634 - century * (0.000042037 + 0.0000001267 * century)
        let m = radians(meanAnomaly)
        let center = sin(m) * (1.914602 - century * (0.004817 + 0.000014 * century))
            + sin(2 * m) * (0.019993 - 0.000101 * century)
            + sin(3 * m) * 0.000289
        let omega = radians(125.04 - 1934.136 * century)
        let apparentLongitude = radians(meanLongitude + center - 0.00569 - 0.00478 * sin(omega))
        let meanObliquity = 23 + (26 + (21.448 - century * (46.815 + century * (0.00059 - century * 0.001813))) / 60) / 60
        let obliquity = radians(meanObliquity + 0.00256 * cos(omega))
        let declination = asin(sin(obliquity) * sin(apparentLongitude))
        let y = pow(tan(obliquity / 2), 2)
        let l0 = radians(meanLongitude)
        let equationOfTimeMinutes = 4 * degrees(
            y * sin(2 * l0) - 2 * eccentricity * sin(m) + 4 * eccentricity * y * sin(m) * cos(2 * l0)
                - 0.5 * y * y * sin(4 * l0) - 1.25 * eccentricity * eccentricity * sin(2 * m)
        )
        let latitude = radians(coordinate.lat)
        let cosHourAngle = cos(radians(90.833)) / (cos(latitude) * cos(declination)) - tan(latitude) * tan(declination)
        guard (-1...1).contains(cosHourAngle) else { return nil }
        let hourAngleMinutes = 4 * degrees(acos(cosHourAngle))
        let noonMinutes = 720 - 4 * coordinate.lon - equationOfTimeMinutes
        return Day(
            sunrise: Date(timeIntervalSince1970: midnight + (noonMinutes - hourAngleMinutes) * 60),
            sunset: Date(timeIntervalSince1970: midnight + (noonMinutes + hourAngleMinutes) * 60)
        )
    }

    static func isNight(at date: Date, coordinate: Coordinate) -> Bool {
        guard let day = day(containing: date, at: coordinate) else { return false }
        return date < day.sunrise || date >= day.sunset
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }

    private static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }

    private static func normalized(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }
}
