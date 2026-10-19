import Foundation
import Testing
@testable import Biegocz

struct FormattingTests {
    private let pl = TestSupport.polish
    private let en = TestSupport.english

    private func normalized(_ string: String) -> String {
        TestSupport.normalizingSpaces(string)
    }

    @Test func polishDistanceUsesDecimalComma() {
        #expect(normalized(Formatters.distance(meters: 5_200, locale: pl)) == "5,20 km")
        #expect(normalized(Formatters.distance(meters: 21_097.5, locale: pl)) == "21,10 km")
    }

    @Test func englishDistanceUsesDecimalPoint() {
        #expect(normalized(Formatters.distance(meters: 5_200, locale: en)) == "5.20 km")
    }

    @Test func polishWeight() {
        #expect(normalized(Formatters.weight(kg: 82.5, locale: pl)) == "82,5 kg")
        #expect(normalized(Formatters.weight(kg: 80, locale: pl)) == "80 kg")
        #expect(normalized(Formatters.weight(kg: 1.25, locale: pl)) == "1,25 kg")
    }

    @Test func polishSpeed() {
        // CLDR's Polish abbreviation for km/h is "km/godz."
        #expect(normalized(Formatters.speed(metersPerSecond: 25 / 3.6, locale: pl)) == "25,0 km/godz.")
        #expect(normalized(Formatters.speed(metersPerSecond: 25 / 3.6, locale: en)) == "25.0 km/h")
    }

    @Test func durations() {
        #expect(Formatters.duration(seconds: 125, locale: pl) == "2:05")
        #expect(Formatters.duration(seconds: 3_723, locale: pl) == "1:02:03")
    }

    @Test func pace() {
        #expect(Formatters.pace(secondsPerKilometer: 312, locale: pl) == "5:12")
        #expect(Formatters.pace(secondsPerKilometer: nil, locale: pl) == "--")
        #expect(Formatters.pace(secondsPerKilometer: .infinity, locale: pl) == "--")
    }

    @Test func polishDecimal() {
        #expect(Formatters.decimal(2.5, locale: pl) == "2,5")
    }
}
