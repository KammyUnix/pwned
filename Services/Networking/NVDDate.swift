import Foundation

/// Date handling for NVD, which reports UTC timestamps without a zone suffix
/// (for example `2021-12-10T10:15:09.143`) and date-only strings
/// (`2021-12-10`). Implemented with plain integer arithmetic so it needs no
/// shared formatter objects and is safe to call from any thread.
enum NVDDate {
    /// Parses `YYYY-MM-DD` or `YYYY-MM-DDThh:mm:ss[.fff]`, treating the value as UTC.
    /// Any trailing zone designator is ignored.
    static func parse(_ text: String?) -> Date? {
        guard let text else { return nil }
        let bytes = Array(text.utf8)
        guard bytes.count >= 10, bytes[4] == 45, bytes[7] == 45,
              let year = number(bytes, 0, 4),
              let month = number(bytes, 5, 2),
              let day = number(bytes, 8, 2),
              (1...12).contains(month), (1...31).contains(day) else {
            return nil
        }

        var seconds = Double(daysFromCivil(year: year, month: month, day: day)) * 86_400

        if bytes.count >= 19, bytes[10] == 84, bytes[13] == 58, bytes[16] == 58 {
            guard let hour = number(bytes, 11, 2),
                  let minute = number(bytes, 14, 2),
                  let second = number(bytes, 17, 2) else {
                return nil
            }
            seconds += Double(hour * 3600 + minute * 60 + second)

            if bytes.count > 20, bytes[19] == 46 {
                var scale = 0.1
                var index = 20
                while index < bytes.count, bytes[index] >= 48, bytes[index] <= 57 {
                    seconds += Double(bytes[index] - 48) * scale
                    scale /= 10
                    index += 1
                }
            }
        }
        return Date(timeIntervalSince1970: seconds)
    }

    /// Formats a date for NVD request parameters: `YYYY-MM-DDThh:mm:ss.000Z` (UTC).
    static func requestString(_ date: Date) -> String {
        let total = Int(date.timeIntervalSince1970.rounded(.down))
        let days = floorDiv(total, 86_400)
        let secondsOfDay = total - days * 86_400
        let civil = civilFromDays(days)
        let date = "\(pad(civil.year, 4))-\(pad(civil.month, 2))-\(pad(civil.day, 2))"
        let time = "\(pad(secondsOfDay / 3600, 2)):\(pad((secondsOfDay % 3600) / 60, 2)):\(pad(secondsOfDay % 60, 2))"
        return "\(date)T\(time).000Z"
    }

    // MARK: Helpers

    private static func pad(_ value: Int, _ width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(width - digits.count, 0)) + digits
    }

    private static func number(_ bytes: [UInt8], _ start: Int, _ count: Int) -> Int? {
        guard start + count <= bytes.count else { return nil }
        var value = 0
        for index in start..<(start + count) {
            let byte = bytes[index]
            guard byte >= 48, byte <= 57 else { return nil }
            value = value * 10 + Int(byte - 48)
        }
        return value
    }

    private static func floorDiv(_ value: Int, _ divisor: Int) -> Int {
        let quotient = value / divisor
        return (value % divisor != 0 && (value < 0) != (divisor < 0)) ? quotient - 1 : quotient
    }

    /// Days since 1970-01-01 for a proleptic Gregorian date (Howard Hinnant's algorithm).
    private static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = floorDiv(y, 400)
        let yearOfEra = y - era * 400
        let monthIndex = (month + 9) % 12
        let dayOfYear = (153 * monthIndex + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    private static func civilFromDays(_ days: Int) -> (year: Int, month: Int, day: Int) {
        let z = days + 719_468
        let era = floorDiv(z, 146_097)
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let y = yearOfEra + era * 400
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthIndex = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
        let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
        return (month <= 2 ? y + 1 : y, month, day)
    }
}
