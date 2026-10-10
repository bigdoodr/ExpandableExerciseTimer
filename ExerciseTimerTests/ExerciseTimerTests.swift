//
//  ExerciseTimerTests.swift
//  ExerciseTimerTests
//
//  Created by Casey Scruggs on 12/6/25.
//

import Testing
import Foundation
@testable import ExerciseTimer

struct ExerciseTimerTests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
    }

    /// A `Routine` saved before `kind` existed has no "kind" key in its JSON — it must decode
    /// as `.workout`, since every routine was a workout at the time.
    @Test func routineWithoutKindDecodesAsWorkout() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Legacy Routine","exercises":[]}
        """
        let decoded = try JSONDecoder().decode(Routine.self, from: Data(json.utf8))
        #expect(decoded.kind == .workout)
        #expect(decoded.name == "Legacy Routine")
    }

    /// A routine saved by the Timers tab round-trips its `kind` through encode/decode.
    @Test func timerRoutineRoundTripsKind() throws {
        let routine = Routine(name: "Quick Timer", exercises: [Exercise()], kind: .timer)
        let data = try JSONEncoder().encode(routine)
        let decoded = try JSONDecoder().decode(Routine.self, from: data)
        #expect(decoded.kind == .timer)
    }

    /// The legacy per-builder export format (a bare `[Exercise]` array, no routine wrapper)
    /// must still decode — `RoutinesView.importRoutine` falls back to this when `Routine`
    /// decoding fails, wrapping the result as a new workout routine.
    @Test func legacyExerciseArrayStillDecodes() throws {
        let exercises = [Exercise(), Exercise()]
        let data = try JSONEncoder().encode(exercises)
        let decoded = try JSONDecoder().decode([Exercise].self, from: data)
        #expect(decoded.count == 2)
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(Routine.self, from: data)
        }
    }

}
