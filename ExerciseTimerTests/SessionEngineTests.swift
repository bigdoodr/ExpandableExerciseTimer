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

@MainActor
struct TrainingPlanTests {
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    /// Monday 2026-11-30, 00:00 UTC.
    private var monday: Date { utc.date(from: DateComponents(year: 2026, month: 11, day: 30))! }

    @Test func sessionsAlternateWorkoutsAcrossWeeksLikeABA_BAB() {
        let plan = PlanGenerator.make(.init(goal: .muscle, equipment: .dumbbells, weekdays: [2, 4, 6], length: .short, startDate: monday))
        let sessions = plan.sessions(calendar: utc)
        #expect(sessions.count == 12)
        #expect(sessions.map(\.workoutIndex).prefix(6) == [0, 1, 0, 1, 0, 1])
        #expect(sessions.map(\.week) == [1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4])
        #expect(utc.component(.weekday, from: sessions[1].date) == 4) // Wednesday
        #expect(sessions.last!.date == utc.date(byAdding: .day, value: 25, to: monday))
        #expect(plan.workouts.map(\.name) == ["Full Body A", "Full Body B"])
        #expect(plan.workouts[0].exercises.count == 5)
    }

    @Test func splitFollowsDaysPerWeek() {
        let four = PlanGenerator.make(.init(weekdays: [2, 3, 5, 6], startDate: monday))
        #expect(four.workouts.map(\.name) == ["Upper", "Lower"])
        let five = PlanGenerator.make(.init(weekdays: [2, 3, 4, 5, 6], startDate: monday))
        #expect(five.workouts.map(\.name) == ["Push", "Pull", "Legs"])
    }

    @Test func strengthPlanIsFiveByFiveOnMainLifts() {
        let plan = PlanGenerator.make(.init(goal: .strength, equipment: .fullGym, weekdays: [2, 4, 6], length: .long, startDate: monday))
        let a = plan.workouts[0].exercises
        #expect(a[0].sets == 5 && a[0].targetReps == 5 && a[0].targetRepsMax == nil)
        #expect(a[3].sets == 3 && a[3].targetReps == 8 && a[3].targetRepsMax == 10)
    }

    @Test func weeklyWaveAdjustsSetsRepsAndDeloadWeight() {
        var bench = reps("Bench", sets: 3, reps: 8, weight: 100)
        bench.targetRepsMax = 12
        let plan = TrainingPlan(name: "T", startDate: monday, weekdays: [2], workouts: [PlanWorkout(name: "A", exercises: [bench])])
        let s = plan.sessions(calendar: utc)
        let none: (Exercise) -> LastPerformance? = { _ in nil }
        #expect(plan.exercises(for: s[0], lastPerformance: none)[0].sets == 3)
        #expect(plan.exercises(for: s[1], lastPerformance: none)[0].targetReps == 12)
        #expect(plan.exercises(for: s[2], lastPerformance: none)[0].sets == 4)
        let deload = plan.exercises(for: s[3], lastPerformance: none)[0]
        #expect(deload.sets == 2)
        #expect(deload.weight == 90)
    }

    @Test func overloadAddsARoundToSupersets() {
        var a = reps("A")
        a.chainRepeatCount = 3
        let plan = TrainingPlan(name: "T", startDate: monday, weekdays: [2], workouts: [PlanWorkout(name: "A", exercises: [a, reps("B", linked: true)])])
        let week3 = plan.exercises(for: plan.sessions(calendar: utc)[2], lastPerformance: { _ in nil })
        #expect(week3[0].chainRepeatCount == 4)
        #expect(week3[1].sets == 1)
    }

    @Test func sessionAdaptsToWhatWasLogged() {
        var squat = reps("Goblet Squat", sets: 3, reps: 8)
        squat.targetRepsMax = 10
        let plan = TrainingPlan(name: "T", startDate: monday, weekdays: [2, 4], workouts: [PlanWorkout(name: "A", exercises: [squat])])
        let hitTop = LastPerformance(date: monday, sets: (1...3).map { r in
            SetRecord(exerciseID: squat.id, exerciseIndex: 0, exerciseName: "Goblet Squat", round: r, reps: 10,
                      weight: 50, weightUnit: .lbs, activeDuration: 30, skipped: false, completedAt: monday)
        })
        let next = plan.exercises(for: plan.sessions(calendar: utc)[1], lastPerformance: { _ in hitTop })
        #expect(next[0].weight == 55) // carried 50 forward, then +5 for hitting every rep
        #expect(plan.note(for: plan.sessions(calendar: utc)[1], lastPerformance: { _ in hitTop }).count == 2)
    }

    @Test func completionTracksTaggedWorkouts() {
        let plan = PlanGenerator.make(.init(weekdays: [2, 4, 6], startDate: monday))
        var history: [CompletedWorkout] = []
        #expect(plan.nextSession(history: history, calendar: utc)?.index == 0)
        history.append(CompletedWorkout(date: monday, kind: .workout, routineName: nil, duration: 1, completedNaturally: true,
                                        records: [], planSession: PlanSessionRef(planID: plan.id, index: 0)))
        history.append(CompletedWorkout(date: monday, kind: .workout, routineName: nil, duration: 1, completedNaturally: true,
                                        records: [], planSession: PlanSessionRef(planID: UUID(), index: 1)))
        #expect(plan.completedIndices(in: history) == [0])
        #expect(plan.nextSession(history: history, calendar: utc)?.index == 1)
    }

    @Test func oldHistoryWithoutPlanFieldStillDecodes() throws {
        let json = #"[{"id":"\#(UUID())","date":0,"kind":"workout","duration":10,"completedNaturally":true,"records":[]}]"#
        let decoded = try JSONDecoder().decode([CompletedWorkout].self, from: Data(json.utf8))
        #expect(decoded[0].planSession == nil)
    }

    @Test func planStoreRoundTrips() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let plan = PlanGenerator.make(.init(startDate: monday))
        TrainingPlanStore(directory: dir).save(plan)
        #expect(TrainingPlanStore(directory: dir).plan == plan)
    }
}

@MainActor
struct Phase1FollowUpTests {
    @Test func noProgressionHintsInsideTimedSuperset() {
        var a = reps("Burpees", reps: 10)
        a.chainRepeatCount = 10
        a.groupTimeBudget = 720
        a.groupTimeBudgetScope = .wholeChain
        let pushups = reps("Push-Up", reps: 15, linked: true)
        let ex = [a, pushups, reps("Plain Push-Up", reps: 15)]
        let hitAll = LastPerformance(date: t0, sets: [SetRecord(exerciseID: UUID(), exerciseIndex: 1, exerciseName: "Push-Up", round: 1,
                                                                reps: 15, weight: nil, weightUnit: .lbs, activeDuration: 20, skipped: false, completedAt: t0)])
        #expect(ex.isInTimedChain(1))
        #expect(Progression.hint(for: ex, at: 1, last: hitAll) == nil)
        #expect(Progression.hint(for: ex, at: 2, last: hitAll) == .increaseReps(to: 16))
        let plan = TrainingPlan(name: "T", startDate: t0, weekdays: [1, 2, 3, 4, 5, 6, 7], workouts: [PlanWorkout(name: "M", exercises: ex)])
        let adjusted = plan.exercises(for: plan.sessions()[0], lastPerformance: { _ in hitAll })
        #expect(adjusted[1].targetReps == 15)
        #expect(adjusted[2].targetReps == 16)
    }

    @Test func blockProgressAndWeights() {
        let ex = [reps("Bench", sets: 2, rest: 60), reps("OHP", sets: 3, rest: 60), reps("Row"), reps("Curl")]
        var engine = SessionEngine(exercises: ex, now: t0)
        engine.completeSet(now: at(10))           // Bench set 1 → rest
        engine.skip(now: at(11))                  // → Bench set 2
        #expect(engine.blockProgress(0) == 2.0 / 4.0)
        #expect(engine.blockProgress(1) == 0)
        engine.completeSet(now: at(20))           // → rest after Bench (headline OHP), still block 0
        #expect(engine.headlineExerciseIndex() == 1)
        #expect(engine.blockProgress(0) == 3.0 / 4.0)
        let w = engine.blockWeights()
        #expect(w.count == 4)
        #expect(abs(w.reduce(0, +) - 1) < 1e-9)
        #expect(w[1] > w[3])
    }
}
