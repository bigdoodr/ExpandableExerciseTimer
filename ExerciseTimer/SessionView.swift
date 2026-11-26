import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// The running-session screen. All timing and superset logic lives in `SessionEngine` (shared,
/// unit-tested) and `SessionController`; this view only renders state and forwards taps.
///
/// Layout borrows from Fitness+ Gym Strength's flow: a block-by-block progress strip, one clear
/// exercise card with today's target and what you did last time, a set tracker you log into,
/// and a single overflow menu for in-the-moment changes (swap, skip, add a set) instead of a
/// wall of buttons.
struct SessionView: View {
    let kind: SessionKind
    @Binding var isActive: Bool
    /// Notifies the builder of a mid-session weight/reps edit (see `SessionBuilderView.applyLiveAdjustment`).
    var onExerciseAdjusted: (Exercise) -> Void = { _ in }
#if canImport(UIKit)
    @Binding var keepScreenAwake: Bool
    @Binding var enableBackgroundAudio: Bool
#endif
    @StateObject private var controller: SessionController
    @Environment(\.scenePhase) private var scenePhase
#if canImport(WatchConnectivity)
    @StateObject private var connectivity = WatchConnectivityManager.shared
#endif

    // Editors
    @State private var editingWeightFor: Int?
    @State private var editingRepsFor: Int?
    @State private var swappingExercise: Int?
    @State private var showPlan = false
    @State private var showEndConfirmation = false
    /// Reps the person is about to log for a rep-based set; reset to the target on each new set.
    @State private var pendingReps: Int?
    @State private var pendingStepIndex: Int = -1

    // Split per platform combo — `#if` inside one parameter list isn't reliably parsed.
#if canImport(UIKit) && canImport(HealthKit)
    init(kind: SessionKind, exercises: [Exercise], isActive: Binding<Bool>, keepScreenAwake: Binding<Bool>, enableBackgroundAudio: Binding<Bool>, healthKitEnabled: Bool, activityType: WorkoutActivityOption, routineName: String? = nil, planSession: PlanSessionRef? = nil) {
        self.kind = kind
        self._isActive = isActive
        self._keepScreenAwake = keepScreenAwake
        self._enableBackgroundAudio = enableBackgroundAudio
        self._controller = StateObject(wrappedValue: SessionController(kind: kind, exercises: exercises, routineName: routineName, planSession: planSession, healthKitEnabled: healthKitEnabled, activityType: activityType))
    }
#elseif canImport(HealthKit)
    init(kind: SessionKind, exercises: [Exercise], isActive: Binding<Bool>, healthKitEnabled: Bool, activityType: WorkoutActivityOption, routineName: String? = nil, planSession: PlanSessionRef? = nil) {
        self.kind = kind
        self._isActive = isActive
        self._controller = StateObject(wrappedValue: SessionController(kind: kind, exercises: exercises, routineName: routineName, planSession: planSession, healthKitEnabled: healthKitEnabled, activityType: activityType))
    }
#else
    init(kind: SessionKind, exercises: [Exercise], isActive: Binding<Bool>, routineName: String? = nil, planSession: PlanSessionRef? = nil) {
        self.kind = kind
        self._isActive = isActive
        self._controller = StateObject(wrappedValue: SessionController(kind: kind, exercises: exercises, routineName: routineName, planSession: planSession, healthKitEnabled: false, activityType: .functionalStrengthTraining))
    }
#endif

    private var engine: SessionEngine { controller.engine }

    var body: some View {
        Group {
            if let recap = controller.recap {
                SessionRecapView(controller: controller, recap: recap) { isActive = false }
            } else {
                sessionContent
            }
        }
        .onAppear {
            controller.onExerciseAdjusted = onExerciseAdjusted
#if canImport(UIKit)
            controller.start(backgroundAudio: enableBackgroundAudio)
            UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
#else
            controller.start(backgroundAudio: false)
#endif
        }
        .onDisappear {
            controller.tearDown()
#if canImport(UIKit)
            UIApplication.shared.isIdleTimerDisabled = false
#endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { controller.catchUp() }
        }
#if canImport(UIKit)
        .onChange(of: keepScreenAwake) { _, on in UIApplication.shared.isIdleTimerDisabled = on }
        .onChange(of: enableBackgroundAudio) { _, on in controller.setBackgroundAudio(on) }
#endif
#if canImport(WatchConnectivity)
        .onChange(of: connectivity.commandSequence) { _, _ in
            controller.handle(connectivity.receivedCommand)
        }
#endif
        .alert(kind.endAlertTitle, isPresented: $showEndConfirmation) {
            Button(kind.endButtonLabel, role: .destructive) { controller.endEarly() }
            Button("Keep Going", role: .cancel) {}
        } message: {
            Text(kind.endAlertMessage)
        }
        .sheet(item: $editingWeightFor.asIdentifiable) { item in
            WeightEditorSheet(exercise: engine.exercises[item.id]) { weight, unit in
                controller.updateWeight(exerciseIndex: item.id, weight: weight, unit: unit)
            }
        }
        .sheet(item: $editingRepsFor.asIdentifiable) { item in
            RepsEditorSheet(exercise: engine.exercises[item.id]) { reps, max in
                controller.updateReps(exerciseIndex: item.id, reps: reps, repsMax: max)
            }
        }
        .sheet(item: $swappingExercise.asIdentifiable) { item in
            SwapExerciseSheet(kind: kind, currentName: engine.displayName(ofExercise: item.id, kind: kind)) { name in
                controller.swapExercise(at: item.id, toName: name)
            }
        }
        .sheet(isPresented: $showPlan) {
            NavigationStack {
                WorkoutOverviewView(kind: kind, exercises: engine.exercises, engine: engine)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showPlan = false } }
                    }
            }
        }
    }

    // MARK: - Session layout

    /// Width at which the session switches to two columns. Read from a GeometryReader rather than
    /// the size class: the Duo's inner display can report a compact width.
    private static let wideLayoutMinWidth: CGFloat = 700

    private var sessionContent: some View {
        GeometryReader { geo in
            if geo.size.width >= Self.wideLayoutMinWidth {
                wideSessionContent(in: geo.size)
            } else {
                narrowSessionContent
            }
        }
        .overlay(alignment: .bottom) { undoToast }
        .onChange(of: engine.state.stepIndex, initial: true) { _, _ in resetPendingReps() }
    }

    /// The single-column layout used below `wideLayoutMinWidth`.
    private var narrowSessionContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                topBar
                BlockProgressStrip(engine: engine)
                exerciseCard
                phaseCard()
                setTrackerSection
                lastSetLogSection
                upNextSection
                healthSection
                controls
            }
            .padding()
        }
        // Inside the GeometryReader the scroll view would stop at the safe area; let it run under
        // the home indicator as it always has.
        .ignoresSafeArea(.container, edges: .bottom)
    }

    /// Two columns for wide windows (iPad, iPhone landscape, the Duo's inner display): the top bar
    /// and progress strip across the top, the exercise and phase cards on the left (about 55%), and
    /// the set log, Up Next and Health on the right with the controls pinned underneath. Each
    /// column scrolls on its own if it is taller than the screen.
    private func wideSessionContent(in size: CGSize) -> some View {
        let padding: CGFloat = 16
        let gap: CGFloat = 20
        let leftWidth = (size.width - padding * 2 - gap) * 0.55
        // Grow the ring to fill the left column, within what the height leaves after the exercise card.
        let ringDiameter = min(300, max(160, min(leftWidth - 96, size.height - 400)))
        let isShort = size.height < 520
        return VStack(spacing: 12) {
            VStack(spacing: 12) {
                topBar
                BlockProgressStrip(engine: engine)
            }
            HStack(alignment: .top, spacing: gap) {
                ScrollView {
                    VStack(spacing: 20) {
                        exerciseCard
                        phaseCard(ringDiameter: ringDiameter)
                    }
                    .padding(.bottom)
                }
                .frame(width: leftWidth)
                VStack(spacing: 12) {
                    ScrollView {
                        VStack(spacing: 20) {
                            setTrackerSection
                            lastSetLogSection
                            upNextSection
                            healthSection
                            // On a short window (iPhone in landscape) pinned controls would leave
                            // the column almost no room, so they scroll with the rest.
                            if isShort { controls }
                        }
                    }
                    if !isShort { controls }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, padding)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var setTrackerSection: some View {
        if kind == .workout, let index = engine.headlineExerciseIndex() {
            SetTracker(engine: engine, exerciseIndex: index)
        }
    }

    @ViewBuilder
    private var lastSetLogSection: some View {
        if engine.currentStep?.isRest == true, kind == .workout, let last = engine.lastRecord,
           !last.skipped, last.reps != nil || last.weight != nil {
            LastSetLogCard(record: last) { reps, weight in
                controller.amendLastRecord(reps: reps, weight: weight)
            }
        }
    }

    @ViewBuilder
    private var upNextSection: some View {
        let upNext = engine.upNextText(kind: kind, now: controller.now)
        if !upNext.isEmpty {
            Text(upNext)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var healthSection: some View {
#if canImport(HealthKit) && canImport(UIKit)
        if controller.healthKitEnabled && HealthKitWorkoutManager.shared.isWorkoutActive {
            HealthMetricsStrip(manager: HealthKitWorkoutManager.shared)
        }
#endif
    }

    private var topBar: some View {
        HStack {
            Label(SessionFormat.time(controller.now.timeIntervalSince(engine.state.startedAt)), systemImage: "clock")
                .monospacedDigit()
            Spacer()
            if engine.state.isPaused {
                Label("Paused", systemImage: "pause.circle.fill").foregroundStyle(.orange)
            }
            Spacer()
            Button { showPlan = true } label: {
                Label("Plan", systemImage: "list.bullet.rectangle")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var exerciseCard: some View {
        if let index = engine.headlineExerciseIndex() {
            let exercise = engine.exercises[index]
            VStack(spacing: 8) {
                if let superset = engine.supersetPositionLabel(kind: kind) {
                    Text(superset.uppercased())
                        .font(.caption.bold())
                        .foregroundStyle(.purple)
                }
                Text(engine.displayName(ofExercise: index, kind: kind))
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                Text(engine.progressLabel(kind: kind))
                    .font(.title3)
                    .foregroundStyle(.secondary)

                if kind == .workout {
                    HStack(spacing: 6) {
                        if !exercise.isTimeBased {
                            Button { editingRepsFor = index } label: {
                                editableValue(SessionFormat.reps(exercise.targetReps, max: exercise.targetRepsMax), tint: .purple)
                            }
                            .buttonStyle(.plain)
                            Text("@").foregroundStyle(.secondary)
                        }
                        Button { editingWeightFor = index } label: {
                            editableValue(SessionFormat.weight(exercise.weight, unit: exercise.weightUnit), tint: .blue)
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.title3)

                    if let last = controller.lastPerformance(forExercise: index), !last.summary.isEmpty {
                        Text("Last time: \(last.summary)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let hint = controller.progressionHint(forExercise: index) {
                        Label(hint.message, systemImage: "chart.line.uptrend.xyaxis")
                            .font(.footnote)
                            .foregroundStyle(.green)
                            .multilineTextAlignment(.center)
                    }
                }
                if let notes = exercise.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func editableValue(_ text: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Text(text).bold().foregroundStyle(tint)
            Image(systemName: "pencil.circle.fill").font(.caption).foregroundStyle(tint.opacity(0.6))
        }
    }

    @ViewBuilder
    private func phaseCard(ringDiameter: CGFloat = 220) -> some View {
        let style = engine.phaseStyle()
        let tint: Color = style == .rest ? .orange : (style == .manualWork ? .blue : .green)
        VStack(spacing: 16) {
            Text(engine.phaseLabel(kind: kind))
                .font(.headline)
                .foregroundStyle(tint)

            switch style {
            case .timedWork, .rest:
                CountdownRing(remaining: engine.timeRemaining(at: controller.now) ?? 0,
                              total: phaseLength, tint: tint, diameter: ringDiameter)
            case .manualWork:
                if kind == .workout, let exercise = engine.currentExercise, !exercise.isTimeBased {
                    // Starts at the target; AMRAP starts blank and only logs a count if you set one.
                    Stepper(value: Binding(get: { pendingReps ?? 0 }, set: { pendingReps = max(0, $0) }), in: 0...999) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(pendingReps.map(String.init) ?? "–")
                                .font(.system(size: 56, weight: .bold, design: .rounded))
                                .monospacedDigit()
                            Text("reps").foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal)
                }
                GlassActionButton(tint: .blue, action: {
                    controller.completeSet(reps: kind == .workout ? pendingReps : nil)
                }) {
                    Text(kind.manualAdvanceButtonLabel).font(.headline)
                }
            case .finished:
                EmptyView()
            }

            if let budget = engine.windowTimeRemaining(at: controller.now) {
                Label(engine.currentWindow?.isHardCap == true ? "\(SessionFormat.time(budget)) left" : "\(SessionFormat.time(budget)) left in round",
                      systemImage: "timer")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var phaseLength: TimeInterval {
        guard let end = engine.state.phaseEnd else { return 1 }
        return max(1, end.timeIntervalSince(engine.state.phaseStart) - engine.state.phasePausedTotal)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                GlassActionButton(tint: .orange, action: controller.togglePause) {
                    Label(engine.state.isPaused ? "Resume" : "Pause",
                          systemImage: engine.state.isPaused ? "play.fill" : "pause.fill")
                        .font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                }
                GlassActionButton(tint: .orange, action: controller.skip) {
                    Label("Skip", systemImage: "forward.end.fill")
                        .font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                }
                moreMenu
            }
            GlassActionButton(tint: .red, action: { showEndConfirmation = true }) {
                Label(kind.endButtonLabel, systemImage: "xmark.circle.fill").font(.headline)
            }
        }
    }

    private var moreMenu: some View {
        Menu {
            if let step = engine.currentStep {
                let isSuperset = engine.plan.blocks[step.block].isSuperset
                Button { controller.addSet() } label: {
                    Label(isSuperset ? "Add Round" : "Add \(kind.setUnitSingular)", systemImage: "plus.circle")
                }
                Button { controller.skipBlock() } label: {
                    Label(isSuperset ? "Skip Rest of \(kind.supersetActionLabel)" : "Skip Rest of \(kind.itemName)",
                          systemImage: "forward.frame")
                }
                if let index = engine.headlineExerciseIndex() {
                    Button { swappingExercise = index } label: {
                        Label("Swap \(kind.itemName)…", systemImage: "arrow.triangle.swap")
                    }
                }
            }
            if engine.canUndo {
                Button { controller.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
            }
            Divider()
            Button { showPlan = true } label: { Label("Workout Plan", systemImage: "list.bullet.rectangle") }
#if canImport(UIKit)
            Toggle(isOn: $keepScreenAwake) { Label("Keep Screen Awake", systemImage: "bolt") }
            Toggle(isOn: $enableBackgroundAudio) { Label("Background Audio", systemImage: "speaker.wave.2") }
#endif
        } label: {
            Image(systemName: "ellipsis")
                .font(.headline)
                .frame(maxWidth: 56)
                .padding(.vertical, 12)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .accessibilityLabel("More")
    }

    @ViewBuilder
    private var undoToast: some View {
        if controller.showUndoToast && engine.canUndo {
            HStack {
                Text(controller.undoToastText).foregroundStyle(.white)
                Spacer()
                Button("Undo", action: controller.undo)
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .bold()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding()
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func resetPendingReps() {
        guard pendingStepIndex != engine.state.stepIndex else { return }
        pendingStepIndex = engine.state.stepIndex
        pendingReps = engine.currentExercise?.targetReps
    }
}

// MARK: - Components

/// One segment per block (exercise or superset): done, in progress (partially filled), upcoming.
/// Widths are proportional to each block's length, computed explicitly — `layoutPriority` on
/// greedy segments let the first segments take all the width and hid the rest.
struct BlockProgressStrip: View {
    let engine: SessionEngine
    private let spacing: CGFloat = 4

    var body: some View {
        let blocks = engine.plan.blocks
        let weights = engine.blockWeights()
        let current = engine.currentStep?.block ?? blocks.count
        GeometryReader { geo in
            let usable = max(0, geo.size.width - spacing * CGFloat(max(0, blocks.count - 1)))
            HStack(spacing: spacing) {
                ForEach(blocks.indices, id: \.self) { i in
                    let width = usable * CGFloat(weights.indices.contains(i) ? weights[i] : 0)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.2))
                        Capsule().fill(blocks[i].isSuperset ? Color.purple : Color.green)
                            .frame(width: width * CGFloat(engine.blockProgress(i)))
                    }
                    .frame(width: width, height: 6)
                }
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityLabel("Block \(min(current + 1, blocks.count)) of \(blocks.count)")
    }
}

struct CountdownRing: View {
    let remaining: TimeInterval
    let total: TimeInterval
    let tint: Color
    /// 220 pt in the single-column layout; the two-column layout grows it (up to 300 pt).
    var diameter: CGFloat = 220

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.2), lineWidth: 12)
            Circle()
                .trim(from: 0, to: max(0, min(1, remaining / total)))
                .stroke(tint, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: remaining)
            Text(SessionFormat.time(remaining))
                .font(.system(size: 64 * diameter / 220, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .padding(24)
        }
        .frame(width: diameter, height: diameter)
    }
}

/// The sets of one exercise in this session: logged ones with their reps/weight, the current
/// one highlighted, and the ones still to come.
struct SetTracker: View {
    let engine: SessionEngine
    let exerciseIndex: Int

    var body: some View {
        let steps = engine.plan.steps.enumerated().filter { $0.element.kind == .work && $0.element.exerciseIndex == exerciseIndex }
        let records = engine.records(forExercise: exerciseIndex)
        if steps.count > 1 {
            VStack(spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { n, item in
                    let record = records.first { $0.round == item.element.round }
                    let isCurrent = item.offset == engine.state.stepIndex
                    HStack {
                        Text("\(n + 1)")
                            .font(.subheadline.bold())
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(isCurrent ? Color.accentColor : Color.secondary.opacity(0.15)))
                            .foregroundStyle(isCurrent ? Color.white : Color.primary)
                        if let record {
                            if record.skipped {
                                Text("Skipped").foregroundStyle(.secondary)
                            } else {
                                Text(recordText(record))
                            }
                            Spacer()
                            Image(systemName: record.skipped ? "forward.end" : "checkmark.circle.fill")
                                .foregroundStyle(record.skipped ? Color.secondary : Color.green)
                        } else {
                            Text(targetText).foregroundStyle(isCurrent ? Color.primary : Color.secondary)
                            Spacer()
                        }
                    }
                    .font(.subheadline)
                    .padding(.vertical, 6)
                    if n < steps.count - 1 { Divider() }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var targetText: String {
        let e = engine.exercises[exerciseIndex]
        if e.isTimeBased { return SessionFormat.time(e.exerciseDuration) + (e.weight.map { _ in " · " + SessionFormat.weight(e.weight, unit: e.weightUnit) } ?? "") }
        return "\(SessionFormat.reps(e.targetReps, max: e.targetRepsMax)) · \(SessionFormat.weight(e.weight, unit: e.weightUnit))"
    }

    private func recordText(_ r: SetRecord) -> String {
        var parts: [String] = []
        if let reps = r.reps { parts.append("\(reps) reps") } else { parts.append(SessionFormat.time(r.activeDuration)) }
        parts.append(SessionFormat.weight(r.weight, unit: r.weightUnit))
        return parts.joined(separator: " · ")
    }
}

/// During rest: quickly correct what the set you just finished actually was.
struct LastSetLogCard: View {
    let record: SetRecord
    let onChange: (Int?, Double?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Log \(record.exerciseName.isEmpty ? "last set" : record.exerciseName) · Set \(record.round)")
                .font(.subheadline.bold())
            if let reps = record.reps {
                Stepper("\(reps) reps", value: Binding(get: { reps }, set: { onChange(max(0, $0), record.weight) }), in: 0...999)
            }
            if let weight = record.weight, weight > 0 {
                let step = Progression.increment(for: record.weightUnit, weight: weight)
                Stepper(SessionFormat.weight(weight, unit: record.weightUnit),
                        value: Binding(get: { weight }, set: { onChange(record.reps, max(0, $0)) }),
                        in: 0...2000, step: step)
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#if canImport(HealthKit) && canImport(UIKit)
struct HealthMetricsStrip: View {
    @ObservedObject var manager: HealthKitWorkoutManager

    var body: some View {
        HStack {
            metric("heart.fill", .red, "BPM", manager.heartRate > 0 ? "\(Int(manager.heartRate))" : "--")
            Divider().frame(height: 44)
            metric("waveform.path.ecg", manager.currentHRZoneIndex.map { HRZoneColors.color($0 + 1) } ?? .secondary, "Zone",
                   manager.currentHRZoneIndex.map { "Z\($0 + 1)" } ?? "--")
            Divider().frame(height: 44)
            metric("flame.fill", .orange, "Calories", manager.activeCalories > 0 ? "\(Int(manager.activeCalories))" : "--")
        }
        .padding()
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func metric(_ icon: String, _ tint: Color, _ label: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Label(label, systemImage: icon).font(.caption).foregroundStyle(tint)
            Text(value).font(.system(.title, design: .rounded).bold()).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}
#endif

enum HRZoneColors {
    static func color(_ zone: Int) -> Color {
        switch zone {
        case 1: return .blue
        case 2: return .teal
        case 3: return .green
        case 4: return .orange
        default: return .red
        }
    }
}

// MARK: - Editor sheets

struct WeightEditorSheet: View {
    let exercise: Exercise
    let onSave: (Double?, WeightUnit) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var unit: WeightUnit = .lbs
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                HStack(spacing: 8) {
                    TextField("0", text: $text)
                        .focused($focused)
#if os(iOS)
                        .keyboardType(.decimalPad)
#endif
                    Picker("Unit", selection: $unit) {
                        Text("LB").tag(WeightUnit.lbs)
                        Text("KG").tag(WeightUnit.kg)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 120)
                }
            }
            .navigationTitle("Adjust Weight")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(Double(text).map { max(0, $0) }, unit)
                        dismiss()
                    }
                }
            }
            .onAppear {
                unit = exercise.weightUnit
                if let w = exercise.weight { text = w.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(w))" : String(format: "%.1f", w) }
                focused = true
            }
        }
        .presentationDetents([.medium])
    }
}

struct RepsEditorSheet: View {
    let exercise: Exercise
    let onSave: (Int?, Int?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isRange = false
    @State private var maxText = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Reps (blank = AMRAP)", text: $text)
#if os(iOS)
                    .keyboardType(.numberPad)
#endif
                Toggle("Range", isOn: $isRange)
                if isRange {
                    TextField("Max reps", text: $maxText)
#if os(iOS)
                        .keyboardType(.numberPad)
#endif
                }
            }
            .navigationTitle("Adjust Target Reps")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let reps = Int(text).map { max(0, $0) }
                        let upper = isRange ? Int(maxText).map { max(0, $0) } : nil
                        // A max below the lower bound isn't a valid range — drop it rather than swap.
                        let valid = (reps != nil && upper != nil && upper! >= reps!) ? upper : nil
                        onSave(reps, valid)
                        dismiss()
                    }
                }
            }
            .onAppear {
                text = exercise.targetReps.map(String.init) ?? ""
                if let m = exercise.targetRepsMax { isRange = true; maxText = String(m) }
            }
        }
        .presentationDetents([.medium])
    }
}

/// "The machine's taken" — rename this exercise for today's session only.
struct SwapExerciseSheet: View {
    let kind: SessionKind
    let currentName: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(kind.itemNameFieldLabel, text: $name)
                } footer: {
                    Text("Only this session changes — your saved routine keeps \(currentName). Sets, reps and weight stay the same; adjust them from the session screen if needed.")
                }
            }
            .navigationTitle("Swap \(kind.itemName)")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Swap") { onSave(name.trimmingCharacters(in: .whitespaces)); dismiss() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Small utilities

struct IdentifiableIndex: Identifiable { let id: Int }

extension Binding where Value == Int? {
    /// Lets an optional index drive `.sheet(item:)`.
    var asIdentifiable: Binding<IdentifiableIndex?> {
        Binding<IdentifiableIndex?>(
            get: { wrappedValue.map(IdentifiableIndex.init) },
            set: { wrappedValue = $0?.id }
        )
    }
}
