import Foundation
import SwiftUI

/// A built-in, non-editable routine bundled with the app (as opposed to a user-saved `Routine`).
struct PreloadedRoutine: Identifiable, Equatable {
    var id = UUID()
    var name: String
    /// Groups related routines together, e.g. "Perfect PPL Split". `nil` for standalone routines.
    var seriesName: String?
    var routineDescription: String
    var source: String
    var sourceURL: String
    /// Link text shown for `sourceURL`, since not every source is a video, e.g. "Watch on YouTube" vs "View Article".
    var sourceLinkLabel: String
    var exercises: [Exercise]
    var accentColorName: String
    var systemImage: String

    var accentColor: Color {
        switch accentColorName {
        case "indigo": return .indigo
        case "purple": return .purple
        case "red": return .red
        case "orange": return .orange
        case "green": return .green
        case "teal": return .teal
        case "yellow": return .yellow
        default: return .blue
        }
    }

    /// Total sets across the routine — a lone exercise's own `sets`, or a superset chain member's round count.
    var totalSets: Int {
        exercises.indices.reduce(0) { $0 + exercises.roundCount(for: exercises.supersetGroupRange(containing: $1)) }
    }

    /// Rep-based routines don't map cleanly to a total duration, so summarize by exercise/set count instead.
    var summaryLine: String {
        let exerciseWord = exercises.count == 1 ? "exercise" : "exercises"
        return "\(exercises.count) \(exerciseWord) · \(totalSets) sets"
    }
}
