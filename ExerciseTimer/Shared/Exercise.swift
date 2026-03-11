import Foundation

struct Exercise: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String = ""
    var isTimeBased: Bool = true
    var sets: Int = 1
    var exerciseDuration: TimeInterval = 30
    var restDuration: TimeInterval = 10
}
