import Foundation
import SwiftData

enum ExerciseSeeder {
    /// Inserts any built-in exercise that isn't in the store yet.
    /// Safe to call on every launch; new built-ins added later get seeded too.
    static func seedIfNeeded(in context: ModelContext) throws {
        let builtIns = FetchDescriptor<Exercise>(predicate: #Predicate { $0.builtInKey != nil })
        let existingKeys = Set(try context.fetch(builtIns).compactMap(\.builtInKey))

        for definition in BuiltInExercises.all where !existingKeys.contains(definition.key) {
            context.insert(Exercise(
                builtInKey: definition.key,
                muscleGroup: definition.muscleGroup,
                loggingType: definition.loggingType
            ))
        }
        try context.save()
    }
}
