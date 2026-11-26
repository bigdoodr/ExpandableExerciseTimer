import SwiftUI

/// Built-in multi-week programs that map cleanly onto a plan: a set of workouts rotated on fixed days.
struct PlanProgram: Identifiable {
    let id: String
    let name: String
    let summary: String
    let source: String
    let sourceURL: String
    let weekdays: [Int]
    let routines: [PreloadedRoutine]
    /// Programs with their own built-in progression skip the base/build/overload/deload wave.
    let usesWeeklyWave: Bool

    static let all: [PlanProgram] = [
        PlanProgram(id: "home-beginner", name: "Perfect Home Workout · Beginner",
                    summary: "No equipment. Workouts A and B alternate Mon/Wed/Fri for four weeks.",
                    source: "Athlean-X", sourceURL: "https://learn.athleanx.com/articles/the-perfect-home-workout-one-month-plan",
                    weekdays: [2, 4, 6], routines: [PreloadedRoutines.homeABeginner, PreloadedRoutines.homeBBeginner], usesWeeklyWave: false),
        PlanProgram(id: "home-advanced", name: "Perfect Home Workout · Advanced",
                    summary: "The harder variations of the same no-equipment month.",
                    source: "Athlean-X", sourceURL: "https://learn.athleanx.com/articles/the-perfect-home-workout-one-month-plan",
                    weekdays: [2, 4, 6], routines: [PreloadedRoutines.homeAAdvanced, PreloadedRoutines.homeBAdvanced], usesWeeklyWave: false),
        PlanProgram(id: "5x5", name: "Classic 5×5",
                    summary: "Barbell basics, A/B on Mon/Wed/Fri. Add weight whenever you finish every rep.",
                    source: "StrongLifts 5×5", sourceURL: "https://stronglifts.com/stronglifts-5x5/workout-program/",
                    weekdays: [2, 4, 6], routines: [PreloadedRoutines.fiveByFiveA, PreloadedRoutines.fiveByFiveB], usesWeeklyWave: false),
        PlanProgram(id: "ppl", name: "Perfect PPL Split",
                    summary: "Push, Pull, Legs twice a week (Mon–Sat), with the 4-week wave applied.",
                    source: "Athlean-X", sourceURL: "https://youtu.be/HE45jVN7XKM",
                    weekdays: [2, 3, 4, 5, 6, 7],
                    routines: [PreloadedRoutines.push1, PreloadedRoutines.pull1, PreloadedRoutines.legs1,
                               PreloadedRoutines.push2, PreloadedRoutines.pull2, PreloadedRoutines.legs2], usesWeeklyWave: true),
    ]

    func makePlan(startDate: Date) -> TrainingPlan {
        var plan = PlanGenerator.make(from: routines.map { Routine(name: $0.name, exercises: $0.exercises, kind: .workout) },
                                      weekdays: weekdays, startDate: startDate, name: name)
        plan.source = source
        plan.sourceURL = sourceURL
        plan.usesWeeklyWave = usesWeeklyWave
        return plan
    }
}

/// The Plan tab: a Fitness+-style four-week program — what's next, why, and how far along you are.
struct TrainingPlanView: View {
    let savedRoutines: [Routine]
    let onStart: (RoutineLoadRequest) -> Void

    @State private var plan: TrainingPlan? = TrainingPlanStore.shared.plan
    @State private var history: [CompletedWorkout] = WorkoutHistoryStore.shared.workouts
    @State private var showCreate = false
    @State private var showEndConfirm = false

#if DEBUG
    /// Screenshot mode: the `createPlan` scene opens the New Plan sheet immediately.
    init(savedRoutines: [Routine], onStart: @escaping (RoutineLoadRequest) -> Void) {
        self.savedRoutines = savedRoutines
        self.onStart = onStart
        self._showCreate = State(initialValue: ScreenshotMode.opensCreatePlan)
    }
#endif

    var body: some View {
        Group {
            if let plan {
                activePlan(plan)
            } else {
                emptyState
            }
        }
        .navigationTitle("Plan")
        .toolbar {
            if plan != nil {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("New Plan…", systemImage: "plus") { showCreate = true }
                        Button("End Plan", systemImage: "xmark.circle", role: .destructive) { showEndConfirm = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showCreate) {
            CreatePlanView(savedRoutines: savedRoutines) { newPlan in
                TrainingPlanStore.shared.save(newPlan)
                plan = newPlan
            }
        }
        .confirmationDialog("End this plan?", isPresented: $showEndConfirm, titleVisibility: .visible) {
            Button("End Plan", role: .destructive) {
                TrainingPlanStore.shared.save(nil)
                plan = nil
            }
        } message: {
            Text("Your logged workouts stay in your history.")
        }
        .onAppear { history = WorkoutHistoryStore.shared.workouts }
    }

    // MARK: Empty

    private var emptyState: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 40))
                        .foregroundStyle(.green)
                    Text("Train with a 4-Week Plan")
                        .font(.title2.bold())
                    Text("Pick your goal, the days you train and the equipment you have. Each week builds on the last, and every session adjusts to the reps and weight you logged.")
                        .foregroundStyle(.secondary)
                    Button {
                        showCreate = true
                    } label: {
                        Label("Create a Plan", systemImage: "plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .padding(.top, 4)
                }
                .padding(.vertical, 8)
            }
            Section("How the 4 Weeks Work") {
                ForEach(WeekPhase.allCases, id: \.self) { phase in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Week \(phase.rawValue) · \(phase.title)").font(.subheadline.bold())
                        Text(phase.summary).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Active

    @ViewBuilder
    private func activePlan(_ plan: TrainingPlan) -> some View {
        let sessions = plan.sessions()
        let done = plan.completedIndices(in: history)
        let next = plan.nextSession(history: history)
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(plan.name).font(.title3.bold())
                    if let next {
                        Text("Week \(next.week) of \(plan.weeks) · \(plan.usesWeeklyWave ? WeekPhase.forWeek(next.week).title : "Program")")
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Plan complete!", systemImage: "trophy.fill").foregroundStyle(.yellow)
                    }
                    ProgressView(value: Double(done.count), total: Double(max(1, plan.totalSessions)))
                        .tint(.green)
                    Text("\(done.count) of \(plan.totalSessions) workouts done")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let source = plan.source, let url = plan.sourceURL.flatMap(URL.init(string:)) {
                        Link("Based on \(source)", destination: url).font(.caption)
                    }
                }
                .padding(.vertical, 4)
            }

            if let next {
                Section("Up Next") {
                    upNextCard(plan: plan, session: next)
                }
            } else {
                Section {
                    Button("Start a New Plan", systemImage: "arrow.clockwise") { showCreate = true }
                }
            }

            ForEach(1...plan.weeks, id: \.self) { week in
                Section("Week \(week)" + (plan.usesWeeklyWave ? " · \(WeekPhase.forWeek(week).title)" : "")) {
                    ForEach(sessions.filter { $0.week == week }) { session in
                        sessionRow(plan: plan, session: session, isDone: done.contains(session.index), isNext: session.index == next?.index)
                    }
                }
            }
        }
    }

    private func upNextCard(plan: TrainingPlan, session: PlannedSession) -> some View {
        let lookup: (Exercise) -> LastPerformance? = { WorkoutHistoryStore.shared.lastPerformance(of: $0) }
        let exercises = plan.exercises(for: session, lastPerformance: lookup)
        let workoutName = plan.workouts[session.workoutIndex].name
        let notes = plan.usesWeeklyWave ? plan.note(for: session, lastPerformance: lookup)
                                        : Array(plan.note(for: session, lastPerformance: lookup).dropFirst())
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text(workoutName).font(.headline)
                    Text(dateLabel(session.date)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                let estimate = Int((WorkoutPlan(exercises: exercises).estimatedDuration() / 60).rounded())
                Text("~\(max(1, estimate)) min").font(.subheadline).foregroundStyle(.secondary)
            }
            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Training Note", systemImage: "text.bubble").font(.caption.bold()).foregroundStyle(.green)
                    ForEach(notes, id: \.self) { Text($0).font(.footnote) }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            ForEach(exercises.prefix(6)) { e in
                HStack {
                    Text(e.name.isEmpty ? "Exercise" : e.name).lineLimit(1)
                    Spacer()
                    Text(targetSummary(e)).foregroundStyle(.secondary).monospacedDigit()
                }
                .font(.subheadline)
            }
            if exercises.count > 6 {
                Text("+ \(exercises.count - 6) more").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                NavigationLink {
                    WorkoutOverviewView(kind: .workout, exercises: exercises)
                } label: {
                    Label("Preview", systemImage: "list.bullet.rectangle")
                }
                .buttonStyle(.bordered)
                Spacer()
                Button {
                    start(plan: plan, session: session, exercises: exercises)
                } label: {
                    Label("Start", systemImage: "play.fill")
                        .font(.headline)
                        // Inside a List row the symbol otherwise picks up the accent (blue) tint.
                        .foregroundStyle(.white)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .captureID("plan.start")
            }
        }
        .padding(.vertical, 4)
    }

    private func sessionRow(plan: TrainingPlan, session: PlannedSession, isDone: Bool, isNext: Bool) -> some View {
        HStack {
            Image(systemName: isDone ? "checkmark.circle.fill" : (isNext ? "circle.inset.filled" : "circle"))
                .foregroundStyle(isDone ? Color.green : (isNext ? Color.accentColor : Color.secondary))
            VStack(alignment: .leading) {
                Text(plan.workouts[session.workoutIndex].name)
                Text(dateLabel(session.date)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !isDone && !isNext {
                Menu {
                    Button("Start This Workout", systemImage: "play.fill") {
                        let exercises = plan.exercises(for: session) { WorkoutHistoryStore.shared.lastPerformance(of: $0) }
                        start(plan: plan, session: session, exercises: exercises)
                    }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func start(plan: TrainingPlan, session: PlannedSession, exercises: [Exercise]) {
        let name = "\(plan.workouts[session.workoutIndex].name) · Week \(session.week)"
        var request = RoutineLoadRequest(routine: Routine(name: name, exercises: exercises, kind: .workout),
                                         isSavedRoutine: false, autoStart: false)
        request.planSession = PlanSessionRef(planID: plan.id, index: session.index)
        onStart(request)
    }

    private func targetSummary(_ e: Exercise) -> String {
        let count = e.chainRepeatCount > 1 && !e.isSupersetContinuation ? e.chainRepeatCount : e.sets
        let amount = e.isTimeBased ? SessionFormat.time(e.exerciseDuration) : SessionFormat.reps(e.targetReps, max: e.targetRepsMax).replacingOccurrences(of: " reps", with: "")
        var text = e.isSupersetContinuation ? amount : "\(count) × \(amount)"
        if let w = e.weight, w > 0 { text += " @ " + SessionFormat.weight(w, unit: e.weightUnit) }
        return text
    }

    private func dateLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInTomorrow(date) { return "Tomorrow" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

// MARK: - Create

struct CreatePlanView: View {
    let savedRoutines: [Routine]
    let onCreate: (TrainingPlan) -> Void
    @Environment(\.dismiss) private var dismiss

    enum Source: String, CaseIterable, Identifiable {
        case build = "Build One", program = "Programs", mine = "My Routines"
        var id: String { rawValue }
    }

    @State private var source: Source = .build
    @State private var options = PlanGenerator.Options()
    @State private var programID = PlanProgram.all.first?.id ?? ""
    @State private var chosenRoutineIDs: [Routine.ID] = []

    private var workoutRoutines: [Routine] { savedRoutines.filter { $0.kind == .workout } }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Source", selection: $source) {
                    ForEach(Source.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                switch source {
                case .build: buildSections
                case .program: programSection
                case .mine: mineSections
                }

                Section {
                    DatePicker("Start", selection: $options.startDate, displayedComponents: .date)
                }
            }
            .captureID("createPlan.form")
            .navigationTitle("New 4-Week Plan")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(makePlan())
                        dismiss()
                    }
                    .disabled(!canCreate)
                }
            }
        }
    }

    @ViewBuilder
    private var buildSections: some View {
        Section("Goal") {
            ForEach(TrainingGoal.allCases) { goal in
                Button {
                    options.goal = goal
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(goal.title).foregroundStyle(.primary)
                            Text(goal.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if options.goal == goal { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        Section("Equipment") {
            Picker("Equipment", selection: $options.equipment) {
                ForEach(EquipmentLevel.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        Section {
            WeekdayPicker(selection: $options.weekdays)
        } header: {
            Text("Training Days")
        } footer: {
            Text(splitDescription)
        }
        Section("Workout Length") {
            Picker("Length", selection: $options.length) {
                ForEach(SessionLength.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    private var splitDescription: String {
        switch options.weekdays.count {
        case 0: return "Pick at least two days."
        case 1: return "Pick at least two days."
        case 2, 3: return "Full-body workouts A and B, alternating."
        case 4: return "Upper and lower body, alternating."
        default: return "Push, pull and legs in rotation."
        }
    }

    @ViewBuilder
    private var programSection: some View {
        Section {
            ForEach(PlanProgram.all) { program in
                Button {
                    programID = program.id
                } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(program.name).foregroundStyle(.primary)
                            Text(program.summary).font(.caption).foregroundStyle(.secondary)
                            Text(program.source).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if programID == program.id { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                    }
                }
                .buttonStyle(.plain)
            }
        } footer: {
            Text("Programs keep their own schedule; each session still suggests weights from what you logged.")
        }
    }

    @ViewBuilder
    private var mineSections: some View {
        Section {
            if workoutRoutines.isEmpty {
                Text("Save a workout from the Exercises tab first, then build a plan from it here.")
                    .foregroundStyle(.secondary)
            }
            ForEach(workoutRoutines) { routine in
                Button {
                    if let i = chosenRoutineIDs.firstIndex(of: routine.id) { chosenRoutineIDs.remove(at: i) }
                    else { chosenRoutineIDs.append(routine.id) }
                } label: {
                    HStack {
                        Text(routine.name).foregroundStyle(.primary)
                        Spacer()
                        if let i = chosenRoutineIDs.firstIndex(of: routine.id) {
                            Text(String(Character(UnicodeScalar(UInt8(65 + min(25, i))))))
                                .font(.caption.bold())
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Color.accentColor.opacity(0.2)))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Rotate These Workouts")
        } footer: {
            Text("Tap in the order you want them to rotate (A, B, C…).")
        }
        Section("Training Days") {
            WeekdayPicker(selection: $options.weekdays)
        }
    }

    private var canCreate: Bool {
        switch source {
        case .build: return options.weekdays.count >= 2
        case .program: return PlanProgram.all.contains { $0.id == programID }
        case .mine: return !chosenRoutineIDs.isEmpty && !options.weekdays.isEmpty
        }
    }

    private func makePlan() -> TrainingPlan {
        switch source {
        case .build:
            return PlanGenerator.make(options)
        case .program:
            let program = PlanProgram.all.first { $0.id == programID } ?? PlanProgram.all[0]
            return program.makePlan(startDate: options.startDate)
        case .mine:
            let routines = chosenRoutineIDs.compactMap { id in workoutRoutines.first { $0.id == id } }
            return PlanGenerator.make(from: routines, weekdays: options.weekdays, startDate: options.startDate)
        }
    }
}

/// Seven toggleable day chips, Monday first.
struct WeekdayPicker: View {
    @Binding var selection: [Int]
    private let order = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(order, id: \.self) { day in
                let on = selection.contains(day)
                Button {
                    if on { selection.removeAll { $0 == day } } else { selection.append(day); selection.sort() }
                } label: {
                    Text(Calendar.current.veryShortWeekdaySymbols[day - 1])
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(Circle().fill(on ? Color.green : Color.secondary.opacity(0.15)))
                        .foregroundStyle(on ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}
