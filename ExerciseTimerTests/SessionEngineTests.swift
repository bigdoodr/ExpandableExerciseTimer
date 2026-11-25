import Testing
import Foundation
@testable import ExerciseTimer

// Pure engine tests: every call takes an explicit `now`, so these run instantly and exactly.

private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

private func timed(_ name: String, sets: Int = 1, duration: TimeInterval = 30, rest: TimeInterval = 0, linked: Bool = false) -> Exercise {
    var e = Exercise()
    e.name = name
    e.isTimeBased = true
    e.sets = sets
    e.exerciseDuration = duration
    e.restDuration = rest
    e.isSupersetContinuation = linked
    return e
}

private func reps(_ name: String, sets: Int = 1, reps: Int? = 10, rest: TimeInterval = 0, linked: Bool = false, weight: Double? = nil) -> Exercise {
    var e = Exercise()
    e.name = name
    e.isTimeBased = false
    e.sets = sets
    e.targetReps = reps
    e.restDuration = rest
    e.isSupersetContinuation = linked
    e.weight = weight
    return e
}

private func shape(_ plan: WorkoutPlan, _ exercises: [Exercise]) -> [String] {
    plan.steps.map { step in
        switch step.kind {
        case .work: return "\(exercises[step.exerciseIndex].name)\(step.round)"
        case .rest: return "R\(Int(step.duration ?? 0))"
        case .budgetRest: return "B"
        }
    }
}

@MainActor
struct WorkoutPlanTests {
    @Test func loneExerciseRestsBetweenSetsButNotAfterTheWorkout() {
        let ex = [timed("A", sets: 3, rest: 10), timed("B", sets: 2, rest: 5)]
        #expect(shape(WorkoutPlan(exercises: ex), ex) == ["A1", "R10", "A2", "R10", "A3", "R10", "B1", "R5", "B2"])
    }

    @Test func supersetRunsOneOfEachPerRound() {
        var a = reps("A", rest: 0)
        a.chainRepeatCount = 3
        let ex = [a, reps("B", rest: 60, linked: true), reps("C", sets: 1)]
        #expect(shape(WorkoutPlan(exercises: ex), ex) == ["A1", "B1", "R60", "A2", "B2", "R60", "A3", "B3", "R60", "C1"])
    }

    @Test func memberRestInsideSupersetIsHonored() {
        var a = reps("A", rest: 15)
        a.chainRepeatCount = 2
        let ex = [a, reps("B", rest: 0, linked: true)]
        #expect(shape(WorkoutPlan(exercises: ex), ex) == ["A1", "R15", "B1", "A2", "R15", "B2"])
    }

    @Test func staleBudgetOnUnlinkedExerciseIsIgnored() {
        var a = reps("A", sets: 2)
        a.groupTimeBudget = 300
        let plan = WorkoutPlan(exercises: [a])
        #expect(plan.windows.isEmpty)
    }

    @Test func perRoundBudgetCreatesWindowPerRoundWithLeftoverRest() {
        var a = reps("A")
        a.chainRepeatCount = 2
        a.groupTimeBudget = 60
        let ex = [a, reps("B", linked: true), reps("C")]
        let plan = WorkoutPlan(exercises: ex)
        #expect(shape(plan, ex) == ["A1", "B1", "B", "A2", "B2", "B", "C1"])
        #expect(plan.windows.count == 2)
        #expect(plan.windows.allSatisfy { !$0.isHardCap })
    }
}

@MainActor
struct SessionEngineTests {
    @Test func timersAdvanceAndCatchUpAfterBackgrounding() {
        let ex = [timed("A", sets: 2, duration: 30, rest: 10), timed("B", duration: 20)]
        var engine = SessionEngine(exercises: ex, now: t0)
        // Phone was locked for 5 minutes: every phase must still be accounted for exactly.
        let events = engine.tick(now: at(300))
        #expect(events.contains(.finished))
        #expect(engine.state.finishedAt == at(30 + 10 + 30 + 10 + 20))
        let recap = engine.recap(now: at(300))
        #expect(recap.setsCompleted == 3)
        #expect(recap.activeTime == 80)
        #expect(recap.restTime == 20)
        #expect(recap.completedNaturally)
    }

    @Test func partialCatchUpLandsMidPhase() {
        let ex = [timed("A", sets: 2, duration: 30, rest: 10)]
        var engine = SessionEngine(exercises: ex, now: t0)
        engine.tick(now: at(35))
        #expect(engine.currentStep?.kind == .rest)
        #expect(engine.timeRemaining(at: at(35)) == 5)
    }

    @Test func pauseFreezesCountdown() {
        var engine = SessionEngine(exercises: [timed("A", duration: 30)], now: t0)
        engine.pause(now: at(10))
        engine.tick(now: at(100))
        #expect(!engine.state.isFinished)
        #expect(engine.timeRemaining(at: at(100)) == 20)
        engine.resume(now: at(100))
        engine.tick(now: at(119))
        #expect(!engine.state.isFinished)
        engine.tick(now: at(120))
        #expect(engine.state.isFinished)
        #expect(engine.recap(now: at(120)).activeTime == 30)
    }

    @Test func pauseFreezesTimedSupersetBudget() {
        var a = reps("A")
        a.chainRepeatCount = 5
        a.groupTimeBudget = 60
        a.groupTimeBudgetScope = .wholeChain
        var engine = SessionEngine(exercises: [a, reps("B", linked: true), reps("C")], now: t0)
        engine.pause(now: at(10))
        engine.resume(now: at(200))           // 190s paused
        engine.tick(now: at(240))             // 50s of real budget used
        #expect(engine.currentExercise?.name == "A")
        #expect(engine.windowTimeRemaining(at: at(240)) == 10)
        engine.tick(now: at(250))             // budget exhausted → chain ends, C starts
        #expect(engine.currentExercise?.name == "C")
        #expect(engine.state.records.filter(\.skipped).count == 10) // A1 was cut off, plus the 9 never reached
    }

    @Test func hardCapEndsChainMidRound() {
        var a = reps("A")
        a.chainRepeatCount = 3
        a.groupTimeBudget = 30
        a.groupTimeBudgetScope = .wholeChain
        var engine = SessionEngine(exercises: [a, reps("B", linked: true), timed("C")], now: t0)
        engine.completeSet(now: at(10))       // A1
        engine.completeSet(now: at(20))       // B1
        engine.tick(now: at(31))              // mid A2 → capped
        #expect(engine.currentExercise?.name == "C")
        #expect(engine.state.phaseStart == at(30))
        #expect(engine.recap(now: at(31)).setsCompleted == 2)
    }

    @Test func perRoundLeftoverBecomesRest() {
        var a = reps("A")
        a.chainRepeatCount = 2
        a.groupTimeBudget = 60
        var engine = SessionEngine(exercises: [a, reps("B", linked: true), reps("C")], now: t0)
        engine.completeSet(now: at(15))
        engine.completeSet(now: at(40))
        #expect(engine.currentStep?.kind == .budgetRest)
        #expect(engine.timeRemaining(at: at(40)) == 20)
        engine.tick(now: at(60))
        #expect(engine.currentExercise?.name == "A")
        #expect(engine.currentStep?.round == 2)
        // Over-time round: no leftover rest, straight on to C.
        engine.completeSet(now: at(100))
        engine.completeSet(now: at(140))
        #expect(engine.currentExercise?.name == "C")
    }

    @Test func supersetRoundsLoopCorrectlyAcrossManyCompletes() {
        var a = reps("A", rest: 0)
        a.chainRepeatCount = 3
        var engine = SessionEngine(exercises: [a, reps("B", rest: 30, linked: true), reps("C")], now: t0)
        var seen: [String] = []
        var now = 0.0
        while let step = engine.currentStep {
            now += 5
            if step.kind == .work {
                seen.append("\(engine.currentExercise!.name)\(step.round)")
                engine.completeSet(now: at(now))
            } else {
                engine.skip(now: at(now))
            }
        }
        #expect(seen == ["A1", "B1", "A2", "B2", "A3", "B3", "C1"])
    }

    @Test func undoRestoresPositionAndRemovesTheLoggedSet() {
        var a = reps("A", rest: 20)
        a.chainRepeatCount = 2
        var engine = SessionEngine(exercises: [a, reps("B", rest: 60, linked: true)], now: t0)
        engine.completeSet(now: at(10))
        #expect(engine.currentStep?.kind == .rest)
        #expect(engine.state.records.count == 1)
        let undone = engine.undo(now: at(12))
        #expect(undone)
        #expect(engine.currentExercise?.name == "A")
        #expect(engine.currentStep?.kind == .work)
        #expect(engine.state.records.isEmpty)
        // And the flow continues correctly afterwards (old bug: stale "rest within group" flag).
        engine.completeSet(now: at(20))
        engine.skip(now: at(21))
        #expect(engine.currentExercise?.name == "B")
        engine.completeSet(now: at(30))
        engine.skip(now: at(31))
        #expect(engine.currentExercise?.name == "A")
        #expect(engine.currentStep?.round == 2)
    }

    @Test func undoAfterFinishingReopensWorkout() {
        var engine = SessionEngine(exercises: [reps("A")], now: t0)
        engine.completeSet(now: at(10))
        #expect(engine.state.isFinished)
        let undone = engine.undo(now: at(11))
        #expect(undone)
        #expect(!engine.state.isFinished)
        #expect(engine.currentExercise?.name == "A")
    }

    @Test func addRoundToSupersetKeepsYourPlace() {
        var a = reps("A")
        a.chainRepeatCount = 2
        var engine = SessionEngine(exercises: [a, reps("B", linked: true)], now: t0)
        engine.completeSet(now: at(5))
        #expect(engine.currentExercise?.name == "B")
        engine.addSetToCurrentBlock(now: at(6))
        #expect(engine.currentExercise?.name == "B")
        #expect(engine.currentStep?.round == 1)
        #expect(engine.currentStep?.roundCount == 3)
        #expect(engine.plan.workStepCount == 6)
    }

    @Test func skipBlockJumpsPastRemainingSets() {
        let ex = [reps("A", sets: 4, rest: 60), reps("B")]
        var engine = SessionEngine(exercises: ex, now: t0)
        engine.completeSet(now: at(10))
        engine.skipBlock(now: at(12))
        #expect(engine.currentExercise?.name == "B")
        let recap = engine.recap(now: at(12))
        #expect(recap.setsCompleted == 1)
        #expect(recap.setsSkipped == 3)
    }

    @Test func loggedRepsAndWeightAreRecorded() {
        var engine = SessionEngine(exercises: [reps("Bench", sets: 2, reps: 8, weight: 135)], now: t0)
        engine.completeSet(now: at(30), reps: 6)
        let first = engine.state.records[0]
        #expect(first.reps == 6)
        #expect(first.weight == 135)
        engine.amendRecord(id: first.id, reps: 7, weight: 130)
        #expect(engine.state.records[0].reps == 7)
        #expect(engine.state.records[0].weight == 130)
    }

    @Test func endingEarlyCountsPartialTimeButNotTheSet() {
        var engine = SessionEngine(exercises: [timed("A", sets: 2, duration: 60), timed("B")], now: t0)
        engine.tick(now: at(60))
        engine.end(now: at(90))
        let recap = engine.recap(now: at(90))
        #expect(!recap.completedNaturally)
        #expect(recap.setsCompleted == 1)
        #expect(recap.activeTime == 90)
        #expect(recap.exercisesPerformed == 1)
        #expect(recap.totalSets == 3)
    }

    @Test func midSessionWeightEditKeepsPlace() {
        var engine = SessionEngine(exercises: [reps("A", sets: 3, weight: 50)], now: t0)
        engine.completeSet(now: at(10))
        engine.updateExercise(at: 0) { $0.weight = 55; $0.sets = 99 }
        #expect(engine.exercises[0].weight == 55)
        #expect(engine.exercises[0].sets == 3) // structural fields go through dedicated actions
        #expect(engine.currentStep?.round == 2)
    }
}

@MainActor
struct SessionPresentationTests {
    @Test func upNextDuringWithinSupersetRestNamesNextMember() {
        var a = reps("Bench", rest: 15)
        a.chainRepeatCount = 2
        var engine = SessionEngine(exercises: [a, reps("Row", linked: true)], now: t0)
        engine.completeSet(now: at(10))
        // Rest: headline is what's coming (Row), progress refers to it too.
        #expect(engine.headlineExerciseIndex() == 1)
        #expect(engine.progressLabel(kind: .workout) == "Round 1 of 2")
        #expect(engine.upNextText(kind: .workout, now: at(10)).hasPrefix("Then: Bench – Round 2"))
    }

    @Test func watchMirrorDerivesIdenticalLabels() throws {
        var a = reps("Bench", rest: 0)
        a.chainRepeatCount = 3
        var phone = SessionEngine(exercises: [a, reps("Row", rest: 45, linked: true)], now: t0)
        phone.completeSet(now: at(20))
        let sync = SessionSync(workoutID: UUID(), revision: 1, engine: phone)
        #expect(sync.setsCompleted == 1)
        #expect(sync.state.records.count == 1)
        let decoded = try JSONDecoder().decode(SessionSync.self, from: JSONEncoder().encode(sync))
        let watch = SessionEngine(exercises: decoded.exercises, state: decoded.state)
        #expect(watch.upNextText(kind: .workout, now: at(25)) == phone.upNextText(kind: .workout, now: at(25)))
        #expect(watch.progressLabel(kind: .workout) == phone.progressLabel(kind: .workout))
        #expect(watch.timeRemaining(at: at(25)) == phone.timeRemaining(at: at(25)))
    }
}

@MainActor
struct ProgressionTests {
    private func performance(reps: [Int], weight: Double?) -> LastPerformance {
        LastPerformance(date: t0, sets: reps.enumerated().map { i, r in
            SetRecord(exerciseID: UUID(), exerciseIndex: 0, exerciseName: "Bench", round: i + 1, reps: r,
                      weight: weight, weightUnit: .lbs, activeDuration: 30, skipped: false, completedAt: t0)
        })
    }

    @Test func hittingTopOfRangeSuggestsMoreWeight() {
        var bench = reps("Bench", sets: 3, reps: 8, weight: 135)
        bench.targetRepsMax = 10
        #expect(Progression.hint(for: bench, last: performance(reps: [10, 10, 10], weight: 135)) == .increaseWeight(to: 140, unit: .lbs))
        #expect(Progression.hint(for: bench, last: performance(reps: [10, 9, 8], weight: 135)) == nil)
        #expect(Progression.hint(for: bench, last: performance(reps: [9, 7, 6], weight: 135)) == .repeatWeight)
    }

    @Test func bodyweightProgressesByReps() {
        let pushups = reps("Push-ups", sets: 3, reps: 15)
        #expect(Progression.hint(for: pushups, last: performance(reps: [15, 15, 15], weight: nil)) == .increaseReps(to: 16))
    }

    @Test func noHintWhenWeightAlreadyChanged() {
        let bench = reps("Bench", sets: 3, reps: 8, weight: 145)
        #expect(Progression.hint(for: bench, last: performance(reps: [8, 8, 8], weight: 135)) == nil)
    }

    @Test func historyFindsLastPerformanceByNameAndSpotsPRs() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = WorkoutHistoryStore(directory: dir)
        let old = CompletedWorkout(date: t0, kind: .workout, routineName: nil, duration: 600, completedNaturally: true,
                                   records: performance(reps: [8, 8], weight: 135).sets)
        store.add(old)
        let bench = reps("bench ", sets: 2, reps: 8, weight: 135)
        #expect(store.lastPerformance(of: bench)?.summary == "2×8 @ 135 lbs")

        let reloaded = WorkoutHistoryStore(directory: dir)
        #expect(reloaded.workouts.count == 1)

        var heavier = performance(reps: [6], weight: 145).sets
        heavier[0].completedAt = at(86_400)
        let new = CompletedWorkout(date: at(86_400), kind: .workout, routineName: nil, duration: 300, completedNaturally: true, records: heavier)
        let milestones = Milestones.find(in: new, history: reloaded.workouts)
        #expect(milestones.map(\.kind) == [.heaviestWeight])
    }
}

@MainActor
struct ProjectionTests {
    /// The notification scheduler walks a copy of the engine forward; it must see every
    /// hands-free phase end and stop at the first rep-based set.
    @Test func projectionListsHandsFreePhaseEndsUntilManualSet() {
        let ex = [timed("Plank", sets: 2, duration: 30, rest: 15), reps("Squat", rest: 0)]
        var projection = SessionEngine(exercises: ex, now: t0)
        var fires: [Date] = []
        while let fire = projection.nextEventDate {
            fires.append(fire)
            projection.tick(now: fire)
        }
        #expect(fires == [at(30), at(45), at(75), at(90)])
        #expect(projection.currentExercise?.name == "Squat")
    }

    @Test func projectionIncludesHardCapDuringManualWork() {
        var a = reps("A")
        a.chainRepeatCount = 3
        a.groupTimeBudget = 120
        a.groupTimeBudgetScope = .wholeChain
        let engine = SessionEngine(exercises: [a, reps("B", linked: true), reps("C")], now: t0)
        #expect(engine.nextEventDate == at(120))
    }
}
