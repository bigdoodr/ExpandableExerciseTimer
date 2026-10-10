import SwiftUI

/// The reorderable, swipeable list of exercises/intervals plus its "Add" row — shared by the
/// main builder (`SessionBuilderView`) and `RoutineEditorView`, so editing a saved routine gets
/// the same superset/duplicate/delete affordances as building a fresh list from scratch.
struct ExerciseListEditor: View {
    @Binding var exercises: [Exercise]
    let kind: SessionKind

    var body: some View {
        Group {
            exerciseListSection
            addExerciseSection
        }
    }

    private var exerciseListSection: some View {
        Section {
            ForEach(Array(exercises.indices), id: \.self) { index in
                let isAnchor = index + 1 < exercises.count && exercises[index + 1].isSupersetContinuation
                ExerciseEntryRow(exercise: $exercises[index], kind: kind, isSupersetAnchor: isAnchor)
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        if index > 0 {
                            Button {
                                exercises[index].isSupersetContinuation.toggle()
                                exercises.normalizeSupersets()
                            } label: {
                                Label(
                                    exercises[index].isSupersetContinuation ? kind.unlinkSupersetActionLabel : kind.supersetActionLabel,
                                    systemImage: exercises[index].isSupersetContinuation ? "link.badge.minus" : "link"
                                )
                            }
                            .tint(.purple)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            exercises.remove(at: index)
                            exercises.normalizeSupersets()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            var copy = exercises[index]
                            copy.id = UUID()
                            exercises.insert(copy, at: index + 1)
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        .tint(.blue)
                    }
                    .contextMenu {
                        Button {
                            var copy = exercises[index]
                            copy.id = UUID()
                            exercises.insert(copy, at: index + 1)
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        if index > 0 {
                            Button {
                                exercises[index].isSupersetContinuation.toggle()
                                exercises.normalizeSupersets()
                            } label: {
                                Label(
                                    exercises[index].isSupersetContinuation ? kind.unlinkSupersetActionLabel : kind.supersetWithPreviousLabel,
                                    systemImage: exercises[index].isSupersetContinuation ? "link.badge.minus" : "link"
                                )
                            }
                        }
                    }
            }
            .onMove { (indices: IndexSet, newOffset: Int) in
                exercises.move(fromOffsets: indices, toOffset: newOffset)
                exercises.normalizeSupersets()
            }
            .onDelete { (indexSet: IndexSet) in
                exercises.remove(atOffsets: indexSet)
                exercises.normalizeSupersets()
            }
        }
    }

    @ViewBuilder
    private var addExerciseSection: some View {
        Section {
            Button(action: {
                exercises.append(Exercise())
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text(kind.addItemLabel)
                }
                .font(.headline)
                .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
        }
    }
}

// Helper row to reduce type-checker load
private struct ExerciseEntryRow: View {
    @Binding var exercise: Exercise
    let kind: SessionKind
    var isSupersetAnchor: Bool = false

    var body: some View {
        ExerciseEntryView(exercise: $exercise, kind: kind, isSupersetAnchor: isSupersetAnchor)
#if os(macOS)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
#endif
    }
}

struct ExerciseEntryView: View {
    @Binding var exercise: Exercise
    let kind: SessionKind
    /// True when the *next* exercise in the list continues a superset with this one — meaning this exercise has no rest of its own.
    var isSupersetAnchor: Bool = false
    @State private var isExpanded = false
    /// Text buffer backing the weight field. Kept separate from `exercise.weight` so the default
    /// "0" can be cleared outright on focus instead of having typed digits append to it (e.g. "025").
    @State private var weightText: String = ""
    @FocusState private var isWeightFieldFocused: Bool

    /// True when this exercise starts a multi-exercise superset chain — it owns the chain's repeat count
    /// instead of its own Number of Sets.
    private var isChainHead: Bool {
        isSupersetAnchor && !exercise.isSupersetContinuation
    }

    /// True for every exercise in a chain except the first — its own Number of Sets doesn't apply,
    /// since chain members each perform one set per round.
    private var isGroupedNonHead: Bool {
        exercise.isSupersetContinuation
    }

    /// Renders a weight value the same way whether it's a whole number or has a fractional part.
    private func formattedWeight(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(value))" : String(format: "%.1f", value)
    }

    @ViewBuilder
    private var supersetBadge: some View {
        if exercise.isSupersetContinuation {
            Image(systemName: "arrow.turn.down.right")
                .font(.caption)
                .foregroundStyle(.purple)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
#if os(macOS)
            HStack(spacing: 0) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
                    .font(.callout)
                    .frame(width: 20)
                HStack {
                    supersetBadge
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    Text(exercise.name.isEmpty ? kind.newItemPlaceholder : exercise.name)
                        .font(.headline)
                    Spacer()
                }
                .foregroundStyle(.primary)
                .padding()
                .padding(.leading, exercise.isSupersetContinuation ? 16 : 0)
                .background(exercise.isSupersetContinuation ? Color.purple.opacity(0.12) : Color(nsColor: .windowBackgroundColor))
                .cornerRadius(12)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation {
                        isExpanded.toggle()
                    }
                }
            }
#else
            HStack {
                supersetBadge
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                Text(exercise.name.isEmpty ? kind.newItemPlaceholder : exercise.name)
                    .font(.headline)
                Spacer()
            }
            .foregroundStyle(.primary)
            .padding()
            .padding(.leading, exercise.isSupersetContinuation ? 16 : 0)
#if os(iOS)
            .background(exercise.isSupersetContinuation ? Color.purple.opacity(0.12) : Color(uiColor: .systemGray6))
#else
            .background(exercise.isSupersetContinuation ? Color.purple.opacity(0.12) : Color.gray.opacity(0.15))
#endif
            .cornerRadius(12)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation {
                    isExpanded.toggle()
                }
            }
#endif
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(kind.itemNameFieldLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TextField("Name", text: $exercise.name)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(kind.itemTypeFieldLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Picker("Type", selection: $exercise.isTimeBased) {
                            Text("Time-Based").tag(true)
                            Text(kind.manualTypeLabel).tag(false)
                        }
                        .pickerStyle(.segmented)
                    }

                    if isChainHead {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "repeat")
                                    .font(.caption)
                                    .foregroundStyle(.purple)
                                Text("Repeat Chain")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Stepper("\(exercise.chainRepeatCount) round\(exercise.chainRepeatCount == 1 ? "" : "s")", value: $exercise.chainRepeatCount, in: 1...99)
                            Text("Each linked \(kind.itemName.lowercased()) performs one set per round.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Toggle(isOn: Binding(
                                get: { exercise.groupTimeBudget != nil },
                                set: { exercise.groupTimeBudget = $0 ? (exercise.groupTimeBudget ?? 300) : nil }
                            )) {
                                HStack(spacing: 6) {
                                    Image(systemName: "timer")
                                        .foregroundStyle(.purple)
                                    Text(kind.timedSupersetLabel)
                                }
                            }
                            .padding(.top, 4)

                            if exercise.groupTimeBudget != nil {
                                DurationPickerView(title: "Time Budget per Round", duration: Binding(
                                    get: { exercise.groupTimeBudget ?? 300 },
                                    set: { exercise.groupTimeBudget = $0 }
                                ))
                                Text("Complete every linked \(kind.itemName.lowercased()) within this time, back-to-back — any time left over becomes rest before the next round.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else if isGroupedNonHead {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(kind.numberOfSetsLabel)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("Performed once per round — set the round count on the first \(kind.itemName.lowercased()) in this chain.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(kind.numberOfSetsLabel)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Stepper("\(exercise.sets)", value: $exercise.sets, in: 1...99)
                        }
                    }

                    if exercise.isTimeBased {
                        DurationPickerView(title: "\(kind.itemName) Duration", duration: $exercise.exerciseDuration)
                    } else if kind == .workout {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Target Reps")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if exercise.targetReps != nil {
                                Stepper(
                                    "\(exercise.targetReps ?? 10) reps",
                                    value: Binding(
                                        get: { exercise.targetReps ?? 10 },
                                        set: { exercise.targetReps = $0 }
                                    ),
                                    in: 1...999
                                )
                                Button("Clear") { exercise.targetReps = nil }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Button("Set target reps") { exercise.targetReps = 10 }
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }

                    if isSupersetAnchor {
                        VStack(alignment: .leading, spacing: 8) {
                            DurationPickerView(title: kind.restBeforeNextLabel, duration: $exercise.restDuration)
                            if exercise.restDuration == 0 {
                                HStack(spacing: 8) {
                                    Image(systemName: "link")
                                        .foregroundStyle(.purple)
                                    Text(kind.noRestContinuationMessage)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 10)
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.purple.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    } else {
                        DurationPickerView(title: kind.restFieldLabel, duration: $exercise.restDuration)
                    }

                    if kind == .workout {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Weight")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if exercise.weight != nil {
                                HStack(spacing: 8) {
                                    TextField("0", text: $weightText)
#if os(iOS)
                                    .keyboardType(.decimalPad)
#endif
                                    .textFieldStyle(.roundedBorder)
                                    .frame(maxWidth: 90)
                                    .focused($isWeightFieldFocused)
                                    .onAppear {
                                        weightText = formattedWeight(exercise.weight ?? 0)
                                    }
                                    .onChange(of: isWeightFieldFocused) { _, focused in
                                        if focused {
                                            // Replace the default "0" outright instead of letting typed digits append to it.
                                            if weightText == "0" {
                                                weightText = ""
                                            }
                                        } else {
                                            let parsed = max(0, Double(weightText) ?? 0)
                                            exercise.weight = parsed
                                            weightText = formattedWeight(parsed)
                                        }
                                    }
                                    .onChange(of: weightText) { _, newValue in
                                        if let parsed = Double(newValue) {
                                            exercise.weight = max(0, parsed)
                                        }
                                    }

                                    Picker("Unit", selection: $exercise.weightUnit) {
                                        Text("LB").tag(WeightUnit.lbs)
                                        Text("KG").tag(WeightUnit.kg)
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(maxWidth: 80)

                                    Spacer()

                                    Button("Clear") { exercise.weight = nil }
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .buttonStyle(.plain)
                                }
                            } else {
                                Button("Add weight") { exercise.weight = 0 }
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding()
#if os(iOS)
                .background(Color(uiColor: .systemGray5))
#elseif os(macOS)
                .background(Color(nsColor: .underPageBackgroundColor))
#else
                .background(Color.gray.opacity(0.2))
#endif
                .cornerRadius(12)
            }
        }
        .padding(.horizontal)
    }
}

struct DurationPickerView: View {
    let title: String
    @Binding var duration: TimeInterval
    
#if !os(iOS)
    private let twoDigitFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .none
        f.minimum = 0
        f.maximum = 59
        f.allowsFloats = false
        f.generatesDecimalNumbers = false
        return f
    }()
    private let hourFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .none
        f.minimum = 0
        f.maximum = 23
        f.allowsFloats = false
        f.generatesDecimalNumbers = false
        return f
    }()
#endif
    
    var hours: Int { Int(duration) / 3600 }
    var minutes: Int { (Int(duration) % 3600) / 60 }
    var seconds: Int { Int(duration) % 60 }
    
    private func setHours(_ newHours: Int) {
        duration = TimeInterval((newHours * 3600) + (minutes * 60) + seconds)
    }
    
    private func setMinutes(_ newMinutes: Int) {
        duration = TimeInterval((hours * 3600) + (newMinutes * 60) + seconds)
    }
    
    private func setSeconds(_ newSeconds: Int) {
        duration = TimeInterval((hours * 3600) + (minutes * 60) + newSeconds)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 16) {
                VStack {
                    Text("Hours")
                        .font(.caption)
                        .foregroundStyle(.secondary)
#if os(iOS)
                    Picker("Hours", selection: Binding(
                        get: { hours },
                        set: { setHours($0) }
                    )) {
                        ForEach(0..<24) { hour in
                            Text("\(hour)").tag(hour)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 80, height: 100)
                    .clipped()
#else
                    HStack(spacing: 4) {
                        TextField(
                            "0",
                            value: Binding(
                                get: { hours },
                                set: { setHours(max(0, min(23, $0))) }
                            ),
                            formatter: hourFormatter
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        Text("h")
                            .foregroundStyle(.secondary)
                    }
#endif
                }
                
                VStack {
                    Text("Minutes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
#if os(iOS)
                    Picker("Minutes", selection: Binding(
                        get: { minutes },
                        set: { setMinutes($0) }
                    )) {
                        ForEach(0..<60) { minute in
                            Text("\(minute)").tag(minute)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 80, height: 100)
                    .clipped()
#else
                    HStack(spacing: 4) {
                        TextField(
                            "0",
                            value: Binding(
                                get: { minutes },
                                set: { setMinutes(max(0, min(59, $0))) }
                            ),
                            formatter: twoDigitFormatter
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        Text("m")
                            .foregroundStyle(.secondary)
                    }
#endif
                }
                
                VStack {
                    Text("Seconds")
                        .font(.caption)
                        .foregroundStyle(.secondary)
#if os(iOS)
                    Picker("Seconds", selection: Binding(
                        get: { seconds },
                        set: { setSeconds($0) }
                    )) {
                        ForEach(0..<60) { second in
                            Text("\(second)").tag(second)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(width: 80, height: 100)
                    .clipped()
#else
                    HStack(spacing: 4) {
                        TextField(
                            "0",
                            value: Binding(
                                get: { seconds },
                                set: { setSeconds(max(0, min(59, $0))) }
                            ),
                            formatter: twoDigitFormatter
                        )
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 60)
                        Text("s")
                            .foregroundStyle(.secondary)
                    }
#endif
                }
            }
        }
    }
}
