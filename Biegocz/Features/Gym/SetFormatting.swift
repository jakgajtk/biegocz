import Foundation

enum SetFormatting {
    /// "80 kg × 8", "12 reps", "+10 kg × 8" or "1:30", depending on the logging type.
    static func summary(
        of values: SetValues,
        loggingType: LoggingType,
        bundle: Bundle = .main,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let reps = values.reps ?? 0
        switch loggingType {
        case .weightReps:
            let weight = Formatters.weight(kg: values.weightKg ?? 0, locale: locale)
            return String(localized: "\(weight) × \(reps)", bundle: bundle, locale: locale)
        case .bodyweightReps:
            if let added = values.weightKg, added > 0 {
                let weight = Formatters.weight(kg: added, locale: locale)
                return String(localized: "+\(weight) × \(reps)", bundle: bundle, locale: locale)
            }
            return String(localized: "\(reps) reps", bundle: bundle, locale: locale)
        case .duration:
            return Formatters.duration(seconds: values.durationSeconds ?? 0, locale: locale)
        }
    }

    static func summary(of set: ExerciseSet, loggingType: LoggingType) -> String {
        summary(of: set.values, loggingType: loggingType)
    }
}

enum LastTimeFormatting {
    /// "Last time: 3 × 8 @ 80 kg", or the sets one by one when they differed.
    static func text(
        for summary: LastTimeSummary,
        loggingType: LoggingType,
        bundle: Bundle = .main,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        switch summary {
        case .uniform(let count, let values):
            let reps = values.reps ?? 0
            switch loggingType {
            case .weightReps:
                let weight = Formatters.weight(kg: values.weightKg ?? 0, locale: locale)
                return String(localized: "Last time: \(count) × \(reps) @ \(weight)", bundle: bundle, locale: locale)
            case .bodyweightReps:
                if let added = values.weightKg, added > 0 {
                    let weight = Formatters.weight(kg: added, locale: locale)
                    return String(localized: "Last time: \(count) × \(reps) @ +\(weight)", bundle: bundle, locale: locale)
                }
                return String(localized: "Last time: \(count) × \(reps)", bundle: bundle, locale: locale)
            case .duration:
                let duration = Formatters.duration(seconds: values.durationSeconds ?? 0, locale: locale)
                return String(localized: "Last time: \(count) × \(duration)", bundle: bundle, locale: locale)
            }
        case .varied(let sets):
            let list = sets
                .map { SetFormatting.summary(of: $0, loggingType: loggingType, bundle: bundle, locale: locale) }
                .formatted(.list(type: .and, width: .narrow).locale(locale))
            return String(localized: "Last time: \(list)", bundle: bundle, locale: locale)
        }
    }
}
