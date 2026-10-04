import Foundation
import SwiftUI

/// Heart-rate zone boundaries the person has set by hand in this app, overriding both the Health
/// app's preferred zones and the 220−age estimate. `upperBounds` holds the 4 boundaries between
/// the 5 standard zones, in ascending BPM order (e.g. [100, 120, 140, 160] splits zones 1–5).
struct HRZoneSettings: Codable, Equatable {
    var upperBounds: [Double]?

    static let standard = HRZoneSettings(upperBounds: nil)
}

/// Persists `HRZoneSettings` to UserDefaults under one shared key, read by both the Settings UI
/// (iOS/macOS) and `HealthKitWorkoutManager` when it starts a workout (iOS/watchOS) — the watch's
/// copy arrives via `WatchConnectivityManager`'s application context, written here on receipt, so
/// both devices end up reading the same key name out of their own (separate) UserDefaults.
enum HRZoneStore {
    static let key = "hrZoneSettings"

    static func load() -> HRZoneSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(HRZoneSettings.self, from: data) else {
            return .standard
        }
        return decoded
    }

    static func save(_ settings: HRZoneSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

/// Shared math behind the 5-zone model used throughout the app (`Recovery`/`Fat Burn`/`Cardio`/
/// `Threshold`/`Peak`, at 50/60/70/85% of max heart rate) — mirrors `HRZone.zone(for:maxHR:)` in
/// `WorkoutState.swift`, which classifies a single live BPM reading rather than computing bounds.
enum HRZoneCalculator {
    /// Max heart rate assumed when no date of birth is available at all.
    static let defaultMaxHR: Double = 185

    static let zoneNames = ["Recovery", "Fat Burn", "Cardio", "Threshold", "Peak"]

    /// Age in whole years as of `now`. Unlike a plain `now.year - birthYear` subtraction, this
    /// accounts for whether this year's birthday has already passed, so it doesn't overstate the
    /// age of someone born later in the year by one.
    static func age(from dob: DateComponents, now: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard let birthYear = dob.year else { return nil }
        guard let month = dob.month, let day = dob.day else {
            return calendar.component(.year, from: now) - birthYear
        }
        var birthdayComponents = DateComponents()
        birthdayComponents.year = birthYear
        birthdayComponents.month = month
        birthdayComponents.day = day
        guard let birthDate = calendar.date(from: birthdayComponents) else {
            return calendar.component(.year, from: now) - birthYear
        }
        return calendar.dateComponents([.year], from: birthDate, to: now).year
    }

    static func maxHR(age: Int) -> Double {
        Double(220 - age)
    }

    /// The 4 boundaries between zones 1–5, as fractions of max HR: 50/60/70/85%.
    static func boundaries(maxHR: Double) -> [Double] {
        [0.50, 0.60, 0.70, 0.85].map { maxHR * $0 }
    }

    static func color(forZone number: Int) -> Color {
        switch number {
        case 1: return .blue
        case 2: return .teal
        case 3: return .green
        case 4: return .orange
        default: return .red
        }
    }

    static func name(forZone number: Int) -> String {
        zoneNames[safe: number - 1] ?? "Peak"
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
