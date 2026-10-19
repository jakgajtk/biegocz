import Foundation

enum SetFormatting {
    /// "80 kg × 8", "12 reps", "+10 kg × 8" or "1:30", depending on the logging type.
    static func summary(
        of set: ExerciseSet,
        loggingType: LoggingType,
        bundle: Bundle = .main,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let reps = set.reps ?? 0
        switch loggingType {
        case .weightReps:
            let weight = Formatters.weight(kg: set.weightKg ?? 0, locale: locale)
            return String(localized: "\(weight) × \(reps)", bundle: bundle, locale: locale)
        case .bodyweightReps:
            if let added = set.weightKg, added > 0 {
                let weight = Formatters.weight(kg: added, locale: locale)
                return String(localized: "+\(weight) × \(reps)", bundle: bundle, locale: locale)
            }
            return String(localized: "\(reps) reps", bundle: bundle, locale: locale)
        case .duration:
            return Formatters.duration(seconds: set.durationSeconds ?? 0, locale: locale)
        }
    }
}
