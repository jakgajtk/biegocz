import Foundation

/// Locale-aware formatting for every number shown in the UI.
/// Polish gets a decimal comma ("5,20 km") automatically.
enum Formatters {
    /// The current locale, but always with 24-hour time.
    static var appLocale: Locale {
        var components = Locale.Components(locale: .autoupdatingCurrent)
        components.hourCycle = .zeroToTwentyThree
        return Locale(components: components)
    }

    static func dateTime(_ date: Date, locale: Locale = appLocale) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year().hour().minute().locale(locale))
    }

    /// Without the year, for lists already grouped by month, e.g. "niedz., 18 paź, 07:30".
    static func dayAndTime(_ date: Date, locale: Locale = appLocale) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute().locale(locale))
    }

    static func distance(meters: Double, fractionDigits: Int = 2, locale: Locale = .autoupdatingCurrent) -> String {
        Measurement(value: meters / 1000, unit: UnitLength.kilometers).formatted(
            .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(fractionDigits)))
                .locale(locale)
        )
    }

    static func weight(kg: Double, locale: Locale = .autoupdatingCurrent) -> String {
        Measurement(value: kg, unit: UnitMass.kilograms).formatted(
            .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0...2)))
                .locale(locale)
        )
    }

    /// Whole meters, e.g. "42 m".
    static func elevation(meters: Double, locale: Locale = .autoupdatingCurrent) -> String {
        Measurement(value: meters.rounded(), unit: UnitLength.meters).formatted(
            .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0)))
                .locale(locale)
        )
    }

    static func speed(metersPerSecond: Double, locale: Locale = .autoupdatingCurrent) -> String {
        Measurement(value: metersPerSecond * 3.6, unit: UnitSpeed.kilometersPerHour).formatted(
            .measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(1)))
                .locale(locale)
        )
    }

    /// "42:05" below an hour, "1:02:03" from an hour up.
    static func duration(seconds: Double, locale: Locale = .autoupdatingCurrent) -> String {
        let pattern: Duration.TimeFormatStyle.Pattern = seconds >= 3600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(seconds.rounded(.down)).formatted(.time(pattern: pattern).locale(locale))
    }

    /// Minutes and seconds per kilometer, e.g. "5:12". Returns "--" when not moving.
    static func pace(secondsPerKilometer: Double?, locale: Locale = .autoupdatingCurrent) -> String {
        guard let secondsPerKilometer, secondsPerKilometer.isFinite, secondsPerKilometer > 0 else { return "--" }
        return Duration.seconds(secondsPerKilometer.rounded()).formatted(.time(pattern: .minuteSecond).locale(locale))
    }

    static func decimal(_ value: Double, maxFractionDigits: Int = 2, locale: Locale = .autoupdatingCurrent) -> String {
        value.formatted(.number.precision(.fractionLength(0...maxFractionDigits)).locale(locale))
    }
}
