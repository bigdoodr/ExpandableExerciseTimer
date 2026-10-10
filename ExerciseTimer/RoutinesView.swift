import SwiftUI
import UniformTypeIdentifiers

/// The Routines tab: preloaded routines, plus saved workouts and saved timers in their own
/// sections. Loading a routine routes it (via `onLoad`) to the builder tab matching its kind.
struct RoutinesView: View {
    @Binding var savedRoutines: [Routine]
    let onLoad: (RoutineLoadRequest) -> Void

    @State private var editingRoutine: Routine?
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var exportDocument = RoutineDocument(routine: Routine(name: "", exercises: []))
    @State private var importError: String?
    @State private var exportError: String?

    /// Series names in the order their routines first appear in `PreloadedRoutines.all`.
    private var seriesNames: [String] {
        var seen = Set<String>()
        var order: [String] = []
        for routine in PreloadedRoutines.all {
            if let series = routine.seriesName, !seen.contains(series) {
                seen.insert(series)
                order.append(series)
            }
        }
        return order
    }
    private func preloadedRoutines(inSeries series: String) -> [PreloadedRoutine] {
        PreloadedRoutines.all.filter { $0.seriesName == series }
    }
    private var standaloneRoutines: [PreloadedRoutine] {
        PreloadedRoutines.all.filter { $0.seriesName == nil }
    }
    private var myWorkouts: [Routine] {
        savedRoutines.filter { $0.kind == .workout }
    }
    private var myTimers: [Routine] {
        savedRoutines.filter { $0.kind == .timer }
    }

    var body: some View {
        List {
            if !seriesNames.isEmpty {
                Section("Routine Series") {
                    ForEach(seriesNames, id: \.self) { series in
                        let routines = preloadedRoutines(inSeries: series)
                        NavigationLink {
                            PreloadedSeriesView(seriesName: series, routines: routines, onLoad: loadPreloaded)
                        } label: {
                            FolderRow(name: series, subtitle: routines.first?.source, count: routines.count, color: .blue)
                        }
                    }
                }
            }

            if !standaloneRoutines.isEmpty {
                Section("Other Routines") {
                    ForEach(standaloneRoutines) { routine in
                        NavigationLink {
                            PreloadedRoutineDetailView(routine: routine, onLoad: loadPreloaded)
                        } label: {
                            PreloadedRoutineRow(routine: routine)
                        }
                    }
                }
            }

            savedRoutinesSection(title: "My Workouts", routines: myWorkouts)
            savedRoutinesSection(title: "My Timers", routines: myTimers)
        }
        .navigationTitle("Routines")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Import", systemImage: "square.and.arrow.down") { showingImporter = true }
            }
        }
#else
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Import", systemImage: "square.and.arrow.down") { showingImporter = true }
            }
        }
        // See RoutineEditorView for why macOS List-in-sheet contexts need an explicit size;
        // this view is a tab root so it isn't strictly required here, but kept for consistency.
#endif
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            importRoutine(result)
        }
        .fileExporter(isPresented: $showingExporter, document: exportDocument, contentType: .json, defaultFilename: exportDocument.routine.name.isEmpty ? "routine" : exportDocument.routine.name) { result in
            if case .failure(let error) = result {
                exportError = error.localizedDescription
            }
        }
        .alert("Import Failed", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .alert("Export Failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .sheet(item: $editingRoutine) { routine in
            RoutineEditorView(routine: routine) { updated in
                if let index = savedRoutines.firstIndex(where: { $0.id == updated.id }) {
                    savedRoutines[index] = updated
                }
            }
        }
    }

    /// Trims a routine's category and treats blank as uncategorized.
    private func normalizedCategory(_ routine: Routine) -> String? {
        guard let category = routine.category?.trimmingCharacters(in: .whitespaces), !category.isEmpty else { return nil }
        return category
    }

    /// Distinct category names among `routines`, in first-appearance order. Empty when nobody
    /// has categorized anything in this group — callers use that to fall back to a flat list.
    private func categoryNames(in routines: [Routine]) -> [String] {
        var seen = Set<String>()
        var order: [String] = []
        for routine in routines {
            if let category = normalizedCategory(routine), !seen.contains(category) {
                seen.insert(category)
                order.append(category)
            }
        }
        return order
    }

    @ViewBuilder
    private func savedRoutinesSection(title: String, routines: [Routine]) -> some View {
        Section(title) {
            if routines.isEmpty {
                Text("No saved \(title.lowercased()) yet.")
                    .foregroundStyle(.secondary)
            } else {
                let categories = categoryNames(in: routines)
                if categories.isEmpty {
                    // Nobody has categorized anything in this group yet — flat list, as before.
                    ForEach(routines) { routine in
                        SavedRoutineRow(routine: routine, onLoad: onLoad, onEdit: { editingRoutine = routine }, onExport: { export(routine) })
                    }
                    .onDelete { indexSet in deleteRoutines(at: indexSet, from: routines) }
                } else {
                    ForEach(categories, id: \.self) { category in
                        let inCategory = routines.filter { normalizedCategory($0) == category }
                        NavigationLink {
                            SavedRoutineFolderView(title: category, routines: inCategory, onLoad: onLoad, editingRoutine: $editingRoutine, onExport: export, onDelete: deleteRoutines)
                        } label: {
                            FolderRow(name: category, subtitle: nil, count: inCategory.count, color: .indigo)
                        }
                    }
                    let uncategorized = routines.filter { normalizedCategory($0) == nil }
                    if !uncategorized.isEmpty {
                        NavigationLink {
                            SavedRoutineFolderView(title: "Uncategorized", routines: uncategorized, onLoad: onLoad, editingRoutine: $editingRoutine, onExport: export, onDelete: deleteRoutines)
                        } label: {
                            FolderRow(name: "Uncategorized", subtitle: nil, count: uncategorized.count, color: .gray)
                        }
                    }
                }
            }
        }
    }

    private func deleteRoutines(at indexSet: IndexSet, from routines: [Routine]) {
        let toRemove = indexSet.map { routines[$0].id }
        savedRoutines.removeAll { toRemove.contains($0.id) }
    }

    private func loadPreloaded(_ preloaded: PreloadedRoutine) {
        let routine = Routine(name: preloaded.name, exercises: preloaded.exercises, kind: .workout)
        onLoad(RoutineLoadRequest(routine: routine, isSavedRoutine: false, autoStart: false))
    }

    /// Snapshotted into `exportDocument` before presenting the exporter, so the document handed
    /// to `.fileExporter` has a stable identity for the lifetime of the picker — building it
    /// inline from a row's routine would recreate it on every re-render while the picker is open.
    private func export(_ routine: Routine) {
        exportDocument = RoutineDocument(routine: routine)
        showingExporter = true
    }

    /// Accepts either a routine exported from this app, or a legacy plain `[Exercise]` array
    /// (the old per-builder export format), which becomes a new workout named after the file.
    private func importRoutine(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }

        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            if let routine = try? JSONDecoder().decode(Routine.self, from: data) {
                var imported = routine
                imported.id = UUID()
                savedRoutines.append(imported)
            } else {
                let exercises = try JSONDecoder().decode([Exercise].self, from: data)
                let name = url.deletingPathExtension().lastPathComponent
                savedRoutines.append(Routine(name: name.isEmpty ? "Imported Routine" : name, exercises: exercises, kind: .workout))
            }
        } catch {
            importError = error.localizedDescription
        }
    }
}

/// Renaming and editing the exercises/intervals of an existing saved routine — reuses
/// `ExerciseListEditor` so this gets the same reorder/superset/duplicate affordances as the main
/// builder. `routine.id` is preserved on save: Siri/`ExerciseTimerAppIntents` and
/// `pendingRoutineStart` resolve saved routines by id, so a rename or exercise edit must not change it.
struct RoutineEditorView: View {
    let routine: Routine
    let onSave: (Routine) -> Void

    @State private var name: String
    @State private var category: String
    @State private var exercises: [Exercise]
    @Environment(\.dismiss) private var dismiss

    init(routine: Routine, onSave: @escaping (Routine) -> Void) {
        self.routine = routine
        self.onSave = onSave
        _name = State(initialValue: routine.name)
        _category = State(initialValue: routine.category ?? "")
        _exercises = State(initialValue: routine.exercises)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        exercises.normalizeSupersets()
        let trimmedCategory = category.trimmingCharacters(in: .whitespaces)
        onSave(Routine(id: routine.id, name: name.trimmingCharacters(in: .whitespaces), exercises: exercises, kind: routine.kind, category: trimmedCategory.isEmpty ? nil : trimmedCategory))
        dismiss()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Routine Name", text: $name)
                    TextField("Category (optional)", text: $category)
                }
                ExerciseListEditor(exercises: $exercises, kind: routine.kind)
            }
#if os(iOS)
            .listStyle(.insetGrouped)
#else
            .listStyle(.inset)
#endif
            .navigationTitle("Edit Routine")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                // Pinned so this prominent action stays reachable even in a vertically-presented
                // toolbar (e.g. iPhone Duo's outer display) — see "Preparing your app for iPhone Duo".
                // topBarPinnedTrailing needs iOS 27; older iOS falls back to the plain trailing spot.
                if #available(iOS 27.0, *) {
                    ToolbarItem(placement: .topBarPinnedTrailing) {
                        Button("Save", action: save).disabled(!canSave)
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save", action: save).disabled(!canSave)
                    }
                }
            }
#else
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
            // See RoutineManagerSheet (now RoutinesView) for why macOS sheets need an explicit size.
            .frame(minWidth: 420, idealWidth: 480, minHeight: 480, idealHeight: 560)
#endif
        }
    }
}

/// A folder-style row used for both preloaded series (e.g. "Perfect PPL Split") and a saved
/// routine's category — tapping it drills into the routines it contains.
private struct FolderRow: View {
    let name: String
    let subtitle: String?
    let count: Int
    var color: Color = .indigo

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 8)
                .fill(color)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(.white)
                        .font(.title3)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.body)
                    .fontWeight(.medium)
                HStack(spacing: 6) {
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                        Text("·")
                    }
                    Text("\(count) routine\(count == 1 ? "" : "s")")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// The routines within one preloaded series (e.g. the 6 Perfect PPL Split routines).
private struct PreloadedSeriesView: View {
    let seriesName: String
    let routines: [PreloadedRoutine]
    let onLoad: (PreloadedRoutine) -> Void

    var body: some View {
        List {
            ForEach(routines) { routine in
                NavigationLink {
                    PreloadedRoutineDetailView(routine: routine, onLoad: onLoad)
                } label: {
                    PreloadedRoutineRow(routine: routine)
                }
            }
        }
        .navigationTitle(seriesName)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

/// One saved routine's row — Load button, tap to edit, swipe/context menu for Edit and Export.
/// Shared by the flat list (no categories in use) and `SavedRoutineFolderView` (a category's contents).
private struct SavedRoutineRow: View {
    let routine: Routine
    let onLoad: (RoutineLoadRequest) -> Void
    let onEdit: () -> Void
    let onExport: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(routine.name)
                    .font(.headline)
                Text("\(routine.exercises.count) \(routine.kind.itemName.lowercased())\(routine.exercises.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Load") { onLoad(RoutineLoadRequest(routine: routine, isSavedRoutine: true, autoStart: false)) }
                .buttonStyle(.bordered)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
            Button(action: onExport) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .tint(.green)
        }
        .contextMenu {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            Button(action: onExport) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
        }
    }
}

/// The routines within one saved-routine category (or the "Uncategorized" bucket).
private struct SavedRoutineFolderView: View {
    let title: String
    let routines: [Routine]
    let onLoad: (RoutineLoadRequest) -> Void
    @Binding var editingRoutine: Routine?
    let onExport: (Routine) -> Void
    let onDelete: (IndexSet, [Routine]) -> Void

    var body: some View {
        List {
            ForEach(routines) { routine in
                SavedRoutineRow(routine: routine, onLoad: onLoad, onEdit: { editingRoutine = routine }, onExport: { onExport(routine) })
            }
            .onDelete { indexSet in onDelete(indexSet, routines) }
        }
        .navigationTitle(title)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

private struct PreloadedRoutineRow: View {
    let routine: PreloadedRoutine

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 8)
                .fill(routine.accentColor)
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: routine.systemImage)
                        .foregroundStyle(.white)
                        .font(.title3)
                }

            VStack(alignment: .leading, spacing: 3) {
                Text(routine.name)
                    .font(.body)
                    .fontWeight(.medium)
                HStack(spacing: 6) {
                    Text(routine.source)
                    Text("·")
                    Text(routine.summaryLine)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PreloadedRoutineDetailView: View {
    let routine: PreloadedRoutine
    let onLoad: (PreloadedRoutine) -> Void

    private var isVideoSource: Bool {
        routine.sourceURL.contains("youtu")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(routine.source)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(routine.name)
                        .font(.title2)
                        .fontWeight(.bold)
                    if !routine.routineDescription.isEmpty {
                        Text(routine.routineDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if !routine.sourceURL.isEmpty, let url = URL(string: routine.sourceURL) {
                        Link(destination: url) {
                            Label(routine.sourceLinkLabel, systemImage: isVideoSource ? "play.rectangle.fill" : "doc.text.fill")
                                .font(.caption)
                                .foregroundStyle(routine.accentColor)
                        }
                        .padding(.top, 2)
                    }
                }
                .padding()
                .background(.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Exercises")
                        .font(.title3)
                        .fontWeight(.semibold)

                    ForEach(Array(routine.exercises.enumerated()), id: \.offset) { index, exercise in
                        let displaySets = routine.exercises.roundCount(for: routine.exercises.supersetGroupRange(containing: index))
                        PreloadedExerciseRow(index: index, exercise: exercise, displaySets: displaySets, accentColor: routine.accentColor)
                    }
                }

                Button {
                    onLoad(routine)
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Load Routine")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(routine.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
        .navigationTitle(routine.name)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

private struct PreloadedExerciseRow: View {
    let index: Int
    let exercise: Exercise
    /// Sets to display: a lone exercise's own `sets`, or its superset chain's round count.
    let displaySets: Int
    let accentColor: Color

    private var repsLabel: String {
        guard !exercise.isTimeBased else {
            return "\(Int(exercise.exerciseDuration))s"
        }
        guard let reps = exercise.targetReps else { return "failure" }
        if let repsMax = exercise.targetRepsMax, repsMax != reps {
            return "\(reps)–\(repsMax)"
        }
        return "\(reps)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if exercise.isSupersetContinuation {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .trailing)
            } else {
                Text("\(index + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .trailing)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.subheadline)
                    .fontWeight(exercise.isSupersetContinuation ? .regular : .medium)
                if let notes = exercise.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text("\(displaySets) × \(repsLabel)")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(accentColor)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(exercise.isSupersetContinuation ? accentColor.opacity(0.08) : Color.gray.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.leading, exercise.isSupersetContinuation ? 16 : 0)
    }
}

struct RoutineDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    var routine: Routine

    init(routine: Routine) {
        self.routine = routine
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        routine = try JSONDecoder().decode(Routine.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(routine)
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = "\(routine.name.isEmpty ? "routine" : routine.name).json"
        return wrapper
    }
}
