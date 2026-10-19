import Foundation
import SwiftData

enum PersistenceController {
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(
            for: schema,
            migrationPlan: BiegoczMigrationPlan.self,
            configurations: configuration
        )
    }
}
