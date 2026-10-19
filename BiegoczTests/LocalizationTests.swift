import Foundation
import Testing
@testable import Biegocz

struct PolishPluralTests {
    private let bundle = TestSupport.bundle(for: "pl")
    private let locale = TestSupport.polish

    private func sets(_ count: Int) -> String {
        String(localized: "\(count) sets", bundle: bundle, locale: locale)
    }

    private func sessions(_ count: Int) -> String {
        String(localized: "\(count) sessions", bundle: bundle, locale: locale)
    }

    private func reps(_ count: Int) -> String {
        String(localized: "\(count) reps", bundle: bundle, locale: locale)
    }

    @Test(arguments: [
        (1, "1 seria"), (2, "2 serie"), (4, "4 serie"), (5, "5 serii"),
        (12, "12 serii"), (22, "22 serie"), (25, "25 serii"), (0, "0 serii"),
    ])
    func setPlurals(count: Int, expected: String) {
        #expect(sets(count) == expected)
    }

    @Test(arguments: [(1, "1 trening"), (3, "3 treningi"), (5, "5 treningów"), (14, "14 treningów"), (23, "23 treningi")])
    func sessionPlurals(count: Int, expected: String) {
        #expect(sessions(count) == expected)
    }

    @Test(arguments: [(1, "1 powtórzenie"), (2, "2 powtórzenia"), (8, "8 powtórzeń"), (32, "32 powtórzenia")])
    func repPlurals(count: Int, expected: String) {
        #expect(reps(count) == expected)
    }

    @Test func englishPlurals() {
        let bundle = TestSupport.bundle(for: "en")
        #expect(String(localized: "\(1) sets", bundle: bundle, locale: TestSupport.english) == "1 set")
        #expect(String(localized: "\(3) sets", bundle: bundle, locale: TestSupport.english) == "3 sets")
    }
}

struct BuiltInExerciseNameTests {
    @Test func everyBuiltInHasPolishAndEnglishNames() {
        let polish = TestSupport.bundle(for: "pl")
        let english = TestSupport.bundle(for: "en")
        for definition in BuiltInExercises.all {
            let key = BuiltInExercises.localizationKey(for: definition.key)
            let pl = BuiltInExercises.localizedName(forKey: definition.key, bundle: polish, locale: TestSupport.polish)
            let en = BuiltInExercises.localizedName(forKey: definition.key, bundle: english, locale: TestSupport.english)
            #expect(pl != key, "Missing Polish name for \(definition.key)")
            #expect(en != key, "Missing English name for \(definition.key)")
        }
    }

    @Test func establishedPolishNames() {
        let polish = TestSupport.bundle(for: "pl")
        func name(_ key: String) -> String {
            BuiltInExercises.localizedName(forKey: key, bundle: polish, locale: TestSupport.polish)
        }
        #expect(name("bench_press") == "Wyciskanie sztangi leżąc")
        #expect(name("deadlift") == "Martwy ciąg")
        #expect(name("back_squat") == "Przysiad ze sztangą")
    }

    @Test func keysAreUnique() {
        let keys = BuiltInExercises.all.map(\.key)
        #expect(Set(keys).count == keys.count)
    }

    @Test func libraryCoversEveryMuscleGroup() {
        let groups = Set(BuiltInExercises.all.map(\.muscleGroup))
        #expect(groups == Set(MuscleGroup.allCases))
        #expect(BuiltInExercises.all.count >= 40)
    }
}
