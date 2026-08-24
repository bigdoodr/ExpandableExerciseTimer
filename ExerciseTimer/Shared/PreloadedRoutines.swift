import Foundation

private func repExercise(
    _ name: String,
    sets: Int,
    reps: Int? = nil,
    repsMax: Int? = nil,
    notes: String? = nil,
    isSupersetContinuation: Bool = false,
    restDuration: TimeInterval? = nil,
    chainRepeatCount: Int? = nil
) -> Exercise {
    var e = Exercise()
    e.name = name
    e.isTimeBased = false
    e.sets = sets
    e.targetReps = reps
    e.targetRepsMax = repsMax
    e.notes = notes
    e.isSupersetContinuation = isSupersetContinuation
    if let restDuration { e.restDuration = restDuration }
    if let chainRepeatCount { e.chainRepeatCount = chainRepeatCount }
    return e
}

private func timeExercise(
    _ name: String,
    sets: Int,
    duration: TimeInterval,
    notes: String? = nil,
    isSupersetContinuation: Bool = false,
    restDuration: TimeInterval? = nil,
    chainRepeatCount: Int? = nil
) -> Exercise {
    var e = Exercise()
    e.name = name
    e.isTimeBased = true
    e.sets = sets
    e.exerciseDuration = duration
    e.notes = notes
    e.isSupersetContinuation = isSupersetContinuation
    if let restDuration { e.restDuration = restDuration }
    if let chainRepeatCount { e.chainRepeatCount = chainRepeatCount }
    return e
}

/// Built-in routines bundled with the app, styled after WorkoutRandomizer's "Saved Routines" library.
enum PreloadedRoutines {
    static let all: [PreloadedRoutine] = [pull1, pull2, push1, push2, legs1, legs2, arnoldsCircuit]

    private static let pplSeries = "Perfect PPL Split"
    private static let athleanX = "Athlean-X"
    private static let watchOnYouTube = "Watch on YouTube"

    static let pull1 = PreloadedRoutine(
        id: UUID(uuidString: "58D888B5-11DD-4D8E-8343-FC0A07114744")!,
        name: "Pull 1",
        seriesName: pplSeries,
        routineDescription: "The first pull day of Athlean-X's Perfect PPL Split, built around a heavy deadlift and back-width work.",
        source: athleanX,
        sourceURL: "https://youtu.be/IOl42YpK_Es?si=JHjRAkA3ADLsRJzA",
        sourceLinkLabel: watchOnYouTube,
        exercises: [
            repExercise("Barbell Deadlifts", sets: 1, reps: 5, notes: "Use 80% of your 1RM. Perform 4 warmup/ramp-up sets first."),
            repExercise("Chest Supported Rows", sets: 3, reps: 8, repsMax: 10),
            repExercise("DB Lat Pullovers", sets: 3, reps: 10, repsMax: 12),
            repExercise("DB High Pulls", sets: 3, reps: 10, repsMax: 12),
            repExercise("Biceps Chin Curls", sets: 1, notes: "To failure.", chainRepeatCount: 3),
            repExercise("Overhead Triceps Extensions", sets: 1, reps: 10, repsMax: 12, notes: "Superset with Biceps Chin Curls.", isSupersetContinuation: true),
            repExercise("Angels and Devils", sets: 3, reps: 15, repsMax: 20),
        ],
        accentColorName: "indigo",
        systemImage: "dumbbell.fill"
    )

    static let pull2 = PreloadedRoutine(
        id: UUID(uuidString: "8B5A946C-18B0-4682-890B-996FC4320E84")!,
        name: "Pull 2",
        seriesName: pplSeries,
        routineDescription: "The second pull day of Athlean-X's Perfect PPL Split, emphasizing pullups and grip-intensive rowing.",
        source: athleanX,
        sourceURL: "https://youtu.be/IOl42YpK_Es?si=JHjRAkA3ADLsRJzA",
        sourceLinkLabel: watchOnYouTube,
        exercises: [
            repExercise("Snatch Grip Deadlifts", sets: 3, reps: 5, notes: "Use a weight you could do for 8 reps."),
            repExercise("Weighted Pullups", sets: 3, reps: 6, repsMax: 8, notes: "Switch order with Snatch Grip Deadlifts if grip is compromised."),
            repExercise("Alternating DB Gorilla Rows", sets: 3, reps: 10, repsMax: 12, notes: "Each arm."),
            repExercise("Straight Arm Pushdowns", sets: 3, reps: 12, repsMax: 15),
            repExercise("Barbell/EZ Curls", sets: 1, reps: 6, repsMax: 8, chainRepeatCount: 3),
            repExercise("Triceps Pushdowns", sets: 1, reps: 10, repsMax: 12, notes: "Superset with Barbell/EZ Curls.", isSupersetContinuation: true),
            repExercise("Face Pulls", sets: 3, reps: 15, repsMax: 20, notes: "Shown with an optional trap raise."),
        ],
        accentColorName: "purple",
        systemImage: "dumbbell.fill"
    )

    static let push1 = PreloadedRoutine(
        id: UUID(uuidString: "BC9F821B-CF49-475B-817F-753E7978CFBE")!,
        name: "Push 1",
        seriesName: pplSeries,
        routineDescription: "The first push day of Athlean-X's Perfect PPL Split, led by a heavy bench press.",
        source: athleanX,
        sourceURL: "https://youtu.be/HE45jVN7XKM?si=65-sKdGpSZNGFo2R",
        sourceLinkLabel: watchOnYouTube,
        exercises: [
            repExercise("Barbell Bench Press", sets: 4, reps: 4, repsMax: 6, notes: "Leave 1–2 reps in the tank."),
            repExercise("Hi-to-Low Crossovers", sets: 3, reps: 10, repsMax: 12),
            repExercise("DB Shoulder Press", sets: 4, reps: 8, repsMax: 10),
            repExercise("1½ Side Lateral Raises", sets: 3, reps: 12, repsMax: 15),
            repExercise("Lying Tricep Extensions", sets: 1, reps: 10, repsMax: 12, chainRepeatCount: 3),
            repExercise("DB Waiter's Curls", sets: 1, reps: 10, repsMax: 12, notes: "Superset with Lying Tricep Extensions.", isSupersetContinuation: true),
            repExercise("Rotator Cuff External Rotation", sets: 3, reps: 15, repsMax: 20),
        ],
        accentColorName: "red",
        systemImage: "dumbbell.fill"
    )

    static let push2 = PreloadedRoutine(
        id: UUID(uuidString: "AF8EB7C6-90F1-44E6-A88D-B7FE9EA2ECA9")!,
        name: "Push 2",
        seriesName: pplSeries,
        routineDescription: "The second push day of Athlean-X's Perfect PPL Split, led by a heavy overhead press.",
        source: athleanX,
        sourceURL: "https://youtu.be/HE45jVN7XKM?si=65-sKdGpSZNGFo2R",
        sourceLinkLabel: watchOnYouTube,
        exercises: [
            repExercise("Barbell OHP", sets: 4, reps: 4, repsMax: 6, notes: "Leave 1–2 reps in the tank."),
            repExercise("Underhand DB Bench Press", sets: 3, reps: 8, repsMax: 10),
            repExercise("DB Abduction Rows", sets: 3, reps: 8, repsMax: 10, notes: "Each arm."),
            repExercise("DB Floor Flys", sets: 3, reps: 10, repsMax: 12),
            repExercise("Close Grip Bench Press", sets: 1, reps: 6, repsMax: 8, chainRepeatCount: 3),
            repExercise("DB Curl of Choice", sets: 1, reps: 10, repsMax: 12, notes: "Superset with Close Grip Bench Press.", isSupersetContinuation: true),
            repExercise("Pushup Plus", sets: 3, notes: "To failure."),
        ],
        accentColorName: "orange",
        systemImage: "dumbbell.fill"
    )

    static let legs1 = PreloadedRoutine(
        id: UUID(uuidString: "CA697F59-630E-4CDD-BED5-CBD5C8F9DF8D")!,
        name: "Legs 1",
        seriesName: pplSeries,
        routineDescription: "The first leg day of Athlean-X's Perfect PPL Split, led by a heavy squat.",
        source: athleanX,
        sourceURL: "https://youtu.be/X6H4l9R3DnY?si=U1a5VdIUQRlvEuKb",
        sourceLinkLabel: watchOnYouTube,
        exercises: [
            repExercise("Barbell Squats", sets: 4, reps: 4, repsMax: 6, notes: "Leave 1–2 reps in the tank; increase weight as able."),
            repExercise("Barbell Hip Thrusts", sets: 3, reps: 8, repsMax: 10),
            repExercise("Barbell or DB Alternating Reverse Lunges", sets: 3, reps: 10, repsMax: 12, notes: "Each leg."),
            repExercise("DB Single Leg RDLs", sets: 3, reps: 10, repsMax: 12, notes: "Each leg."),
            repExercise("Standing DB Calf Raises", sets: 3, reps: 15, repsMax: 20, notes: "Perform one leg at a time if time allows."),
        ],
        accentColorName: "green",
        systemImage: "figure.strengthtraining.traditional"
    )

    static let legs2 = PreloadedRoutine(
        id: UUID(uuidString: "DB9C223F-8A13-42EF-A1F5-31C8E3126CD0")!,
        name: "Legs 2",
        seriesName: pplSeries,
        routineDescription: "The second leg day of Athlean-X's Perfect PPL Split. Shares its squat, hip thrust, and lunge work with Legs 1.",
        source: athleanX,
        sourceURL: "https://youtu.be/X6H4l9R3DnY?si=U1a5VdIUQRlvEuKb",
        sourceLinkLabel: watchOnYouTube,
        exercises: [
            repExercise("Barbell Squats", sets: 4, reps: 4, repsMax: 6, notes: "Leave 1–2 reps in the tank; increase weight as able."),
            repExercise("Barbell Hip Thrusts", sets: 3, reps: 8, repsMax: 10),
            repExercise("Barbell or DB Alternating Reverse Lunges", sets: 3, reps: 10, repsMax: 12, notes: "Each leg."),
            repExercise("Slick Floor Bridge Curls", sets: 3, notes: "To failure."),
            repExercise("Seated DB Calf Raises", sets: 3, reps: 15, repsMax: 20, notes: "Perform one leg at a time if time allows."),
        ],
        accentColorName: "teal",
        systemImage: "figure.strengthtraining.traditional"
    )

    static let arnoldsCircuit = PreloadedRoutine(
        id: UUID(uuidString: "3EAF8D94-25A3-4DBD-8DBF-7B92B199865D")!,
        name: "Arnold's New Workout",
        seriesName: nil,
        routineDescription: "All 8 movements are linked as one circuit — complete one round of each, back-to-back, for 3 rounds total, resting 90 seconds after each round. Focus on form and full range of motion, not speed.",
        source: "Box Life Magazine",
        sourceURL: "https://boxlifemagazine.com/arnold-new-workout/",
        sourceLinkLabel: "View Article",
        exercises: [
            repExercise("DB Goblet Squats", sets: 1, reps: 10, chainRepeatCount: 3),
            repExercise("DB Single Arm Row (Right Arm)", sets: 1, reps: 10, isSupersetContinuation: true),
            repExercise("DB Single Arm Row (Left Arm)", sets: 1, reps: 10, isSupersetContinuation: true),
            repExercise("DB Romanian Deadlift", sets: 1, reps: 10, isSupersetContinuation: true),
            repExercise("DB Push Press", sets: 1, reps: 10, isSupersetContinuation: true),
            timeExercise("DB Suitcase Carry (Right Arm)", sets: 1, duration: 30, isSupersetContinuation: true),
            timeExercise("DB Suitcase Carry (Left Arm)", sets: 1, duration: 30, isSupersetContinuation: true),
            timeExercise("Bear Crawl", sets: 1, duration: 30, isSupersetContinuation: true, restDuration: 90),
        ],
        accentColorName: "yellow",
        systemImage: "flame.fill"
    )
}
