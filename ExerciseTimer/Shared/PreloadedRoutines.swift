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
    static let all: [PreloadedRoutine] = [pull1, pull2, push1, push2, legs1, legs2,
                                          perfectChest, perfectBack, perfectShoulders, perfectLegs, perfectBiceps,
                                          homeABeginner, homeBBeginner, homeAAdvanced, homeBAdvanced,
                                          fiveByFiveA, fiveByFiveB, bwfRecommendedRoutine,
                                          sixMinuteChest, arnoldsCircuit]

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
        name: "Arnold's 20 Minute Workout",
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

    // MARK: - Added in 3.0 (researched from free, published workouts)

    private static let perfectSeries = "Athlean-X Perfect Workouts"
    private static let homeSeries = "Perfect Home Workout (4 Weeks)"
    private static let fiveByFiveSeries = "Classic 5×5"
    private static let viewArticle = "View Article"

    /// A no-rest, one-minute-per-exercise bodyweight circuit (Perfect Home Workout format).
    private static func minuteCircuit(_ names: [String], rounds: Int, lastRest: TimeInterval = 60) -> [Exercise] {
        names.enumerated().map { i, name in
            var e = timeExercise(name, sets: 1, duration: 60, isSupersetContinuation: i > 0,
                                 restDuration: i == names.count - 1 ? lastRest : 0,
                                 chainRepeatCount: i == 0 ? rounds : nil)
            if i == 0 { e.notes = "One minute per exercise, no rest — rest/pause inside the minute if you need to." }
            return e
        }
    }

    static let perfectChest = PreloadedRoutine(
        id: UUID(uuidString: "EA65CA6D-67ED-40C0-8582-3327A92D9845")!,
        name: "Perfect Chest Workout",
        seriesName: perfectSeries,
        routineDescription: "Upper, middle and lower chest, each pressed heavy and then taken through midline with a crossover drop set, plus a pushup finisher.",
        source: athleanX,
        sourceURL: "https://learn.athleanx.com/articles/the-perfect-chest-workout",
        sourceLinkLabel: viewArticle,
        exercises: [
            repExercise("Barbell Bench Press", sets: 1, reps: 6, repsMax: 12, notes: "4 sets: 6, 8, 10, then 12 reps. Drop straight into the crossovers.", restDuration: 0, chainRepeatCount: 4),
            repExercise("Horizontal Cable or Band Crossovers", sets: 1, reps: 15, isSupersetContinuation: true, restDuration: 90),
            repExercise("Incline Bench Press", sets: 1, reps: 6, repsMax: 12, notes: "4 sets: 6, 8, 10, then 12 reps.", restDuration: 0, chainRepeatCount: 4),
            repExercise("Low-to-High Cable or Band Crossovers", sets: 1, reps: 15, isSupersetContinuation: true, restDuration: 90),
            repExercise("Weighted Dips", sets: 1, reps: 6, repsMax: 12, notes: "4 sets: 6, 8, 10, then 12 reps.", restDuration: 0, chainRepeatCount: 4),
            repExercise("High-to-Low Cable or Band Crossovers", sets: 1, reps: 15, isSupersetContinuation: true, restDuration: 90),
            repExercise("Weighted Pushups", sets: 1, notes: "To failure.", restDuration: 0, chainRepeatCount: 3),
            repExercise("Band Crossover Pushups", sets: 1, reps: 15, notes: "Each side.", isSupersetContinuation: true, restDuration: 90),
        ],
        accentColorName: "red",
        systemImage: "figure.strengthtraining.traditional"
    )

    static let perfectBack = PreloadedRoutine(
        id: UUID(uuidString: "4B813093-4603-4037-8CA8-DBEF8695110E")!,
        name: "Perfect Back Workout",
        seriesName: perfectSeries,
        routineDescription: "Deadlifts paired with chin-up and pull-up grips, an explosive row, focused lat work, then rotator cuff and trap finishers.",
        source: athleanX,
        sourceURL: "https://learn.athleanx.com/articles/back-for-men/the-perfect-back-workout",
        sourceLinkLabel: viewArticle,
        exercises: [
            repExercise("Deadlifts", sets: 1, reps: 6, repsMax: 8, notes: "Set 1: 8RM, set 2: 6RM. Do a set of Straight Arm Pushdowns with each warm-up set. Rest 2 min after each set.", restDuration: 120, chainRepeatCount: 2),
            repExercise("Weighted Chin-Ups", sets: 1, reps: 4, repsMax: 10, notes: "Set 1: 4RM weight. Set 2: half the weight for 8–10.", isSupersetContinuation: true, restDuration: 0),
            repExercise("Deadlifts (Heavy)", sets: 1, reps: 4, notes: "4RM. Rest 30 sec after each set.", restDuration: 30, chainRepeatCount: 2),
            repExercise("Wide Grip Pull-Ups", sets: 1, notes: "Bodyweight, to failure.", isSupersetContinuation: true, restDuration: 90),
            repExercise("Barbell Dead Rows", sets: 3, reps: 8, repsMax: 10, notes: "Use a 10–12RM weight and move explosively — not to failure.", restDuration: 90),
            repExercise("Alternating High Pulley Rows or Rocking Pulldowns", sets: 3, reps: 10, repsMax: 12, notes: "Choose one. 10–12RM, to failure.", restDuration: 90),
            repExercise("Hyper Y-W Combo", sets: 2, reps: 14, repsMax: 20, notes: "Alternate Ys and Ws every rep.", restDuration: 60),
            repExercise("Barbell Shrug Ladder", sets: 1, notes: "Ladder 1 → 10 reps, holding the top for as many seconds as reps."),
        ],
        accentColorName: "indigo",
        systemImage: "figure.strengthtraining.traditional"
    )

    static let perfectShoulders = PreloadedRoutine(
        id: UUID(uuidString: "83E1D441-CAA5-48AE-90D5-CFB9BC73920F")!,
        name: "Perfect Shoulder Workout",
        seriesName: perfectSeries,
        routineDescription: "Every head of the delts through full range of motion: heavy pressing, a stretch-focused tri-set, explosive work and face pulls.",
        source: athleanX,
        sourceURL: "https://learn.athleanx.com/articles/shoulders-for-men/the-perfect-shoulder-workout",
        sourceLinkLabel: viewArticle,
        exercises: [
            repExercise("Overhead Band Press (Warm-Up)", sets: 2, reps: 15, notes: "3-second hold each rep.", restDuration: 30),
            repExercise("Overhead Press or Handstand Pushups", sets: 4, reps: 6, repsMax: 10, notes: "10, 8, 6, 6RM. Finish with 1 set of banded overhead DB press × 15.", restDuration: 120),
            repExercise("Delt Stretch Tri-Set (21s)", sets: 3, reps: 21, notes: "7 reps each: front, middle, rear. 2–3 sets.", restDuration: 90),
            repExercise("DB Cheat Laterals", sets: 1, notes: "To failure, one arm at a time.", restDuration: 0, chainRepeatCount: 3),
            repExercise("DB Push Press", sets: 1, notes: "To failure, one arm at a time.", isSupersetContinuation: true, restDuration: 90),
            repExercise("Cable or Band Face Pulls", sets: 3, reps: 15, notes: "Use the \"15 sets of 1\" concept.", restDuration: 60),
        ],
        accentColorName: "orange",
        systemImage: "figure.strengthtraining.traditional"
    )

    static let perfectLegs = PreloadedRoutine(
        id: UUID(uuidString: "2CBEAE48-2D7D-4653-80D2-F7B979218463")!,
        name: "Perfect Leg Workout",
        seriesName: perfectSeries,
        routineDescription: "Heavy squats, a posterior chain compound, split squats and lunges, adductors, and a hip band finisher.",
        source: athleanX,
        sourceURL: "https://learn.athleanx.com/articles/legs-for-men/the-perfect-leg-workout",
        sourceLinkLabel: viewArticle,
        exercises: [
            repExercise("Barbell Squats", sets: 4, reps: 5, repsMax: 25, notes: "5RM, 5RM, 10RM, 25RM. First a box squat touch-up set (5RM + 10%); hang from a bar 30 sec between sets.", restDuration: 150),
            repExercise("Barbell Hip Thrusts or Glute-Ham Raises", sets: 4, reps: 5, repsMax: 25, notes: "25, 10, 5, 5.", restDuration: 120),
            repExercise("DB Bulgarian Hi/Low Split Squats", sets: 3, reps: 10, repsMax: 12, notes: "Each leg. 2 sets alternating hi/low torso, then 1 bodyweight set of plyo hops to failure.", restDuration: 90),
            repExercise("DB TKE Drop Lunges", sets: 3, reps: 10, repsMax: 12, notes: "Each leg.", restDuration: 90),
            repExercise("DB Adductor Goblet Squats", sets: 2, reps: 10, repsMax: 12, notes: "Each leg.", restDuration: 60),
            repExercise("Hip Band Ladder Finisher", sets: 2, notes: "Ladder up to 10 reps. 1 or 2 rounds."),
        ],
        accentColorName: "green",
        systemImage: "figure.strengthtraining.traditional"
    )

    static let perfectBiceps = PreloadedRoutine(
        id: UUID(uuidString: "F1A460E7-0BD1-4208-94B1-F55A18A70CC9")!,
        name: "Perfect Biceps Workout",
        seriesName: perfectSeries,
        routineDescription: "Overload with cheat curls and weighted chin-ups, each dropped into a second move, then stretch, band and position work.",
        source: athleanX,
        sourceURL: "https://learn.athleanx.com/articles/the-perfect-biceps-workout",
        sourceLinkLabel: viewArticle,
        exercises: [
            repExercise("Barbell Cheat Curls", sets: 1, notes: "To failure, then drop straight into drag curls.", restDuration: 0, chainRepeatCount: 3),
            repExercise("Barbell Drag Curls", sets: 1, notes: "To failure.", isSupersetContinuation: true, restDuration: 90),
            repExercise("Weighted Chin-Ups", sets: 1, notes: "To failure, then drop into chin curls.", restDuration: 0, chainRepeatCount: 3),
            repExercise("Peak Contraction Chin Curls", sets: 1, notes: "To failure.", isSupersetContinuation: true, restDuration: 90),
            repExercise("Banded DB Curls", sets: 3, notes: "To failure.", restDuration: 60),
            repExercise("DB Incline Curls", sets: 2, notes: "To failure, using the stretch reflex.", restDuration: 60),
            repExercise("DB Curl Trifecta", sets: 2, reps: 24, notes: "Alternate positions: 8 reps in each, each arm.", restDuration: 60),
        ],
        accentColorName: "purple",
        systemImage: "figure.strengthtraining.traditional"
    )

    private static let homeURL = "https://learn.athleanx.com/articles/the-perfect-home-workout-one-month-plan"
    private static let homeDescription = "No equipment needed. Lower and upper body alternate so you never rest: one minute per exercise, straight through. Alternate A and B three days a week for a month — or start it as a 4-week plan from the Plan tab."

    static let homeABeginner = PreloadedRoutine(
        id: UUID(uuidString: "4CC69940-75B6-472F-A19B-DB53C9795F52")!,
        name: "Home Workout A · Beginner", seriesName: homeSeries, routineDescription: homeDescription,
        source: athleanX, sourceURL: homeURL, sourceLinkLabel: viewArticle,
        exercises: minuteCircuit(["Alt. Single Leg High Box Squats", "1½ Bottomed Out Squats", "Jump Squats",
                                  "Power Pushaways", "Knee Rotational Pushups", "Knee Cobra Pushups",
                                  "Alt. Kickstand Heel Touch Squats", "Alt. Sprinter Lunges", "High Plyo Sprinter Lunges",
                                  "Seated Pullups", "Bodyweight Sliding Pulldowns", "Inverted Chin Curls",
                                  "Reverse Corkscrews", "Black Widow Knee Slides", "Levitation Crunches",
                                  "Angels and Devils"], rounds: 2),
        accentColorName: "teal", systemImage: "house.fill")

    static let homeBBeginner = PreloadedRoutine(
        id: UUID(uuidString: "66F9EA22-8727-44EB-98B8-E372BFABF227")!,
        name: "Home Workout B · Beginner", seriesName: homeSeries, routineDescription: homeDescription,
        source: athleanX, sourceURL: homeURL, sourceLinkLabel: viewArticle,
        exercises: minuteCircuit(["Slick Floor Bridge Curls", "Long Leg Marches", "High Hip Bucks",
                                  "Knee Decline to Flat Pushups", "Knee Bodyweight Side Lateral Raises", "Bodyweight Triceps Extensions",
                                  "Alt. Crossover Step Ups", "Alt. Reverse Lunges", "Split Squat Jumps",
                                  "Seated Chinups", "Inverted Rows", "Back Widows",
                                  "Ab Halos", "V-Up Tucks", "Sit Up Elbow Thrusts",
                                  "Reverse Hyperextensions"], rounds: 2),
        accentColorName: "teal", systemImage: "house.fill")

    static let homeAAdvanced = PreloadedRoutine(
        id: UUID(uuidString: "39FF7FCD-D503-4D41-B15D-508A440D584E")!,
        name: "Home Workout A · Advanced", seriesName: homeSeries, routineDescription: homeDescription,
        source: athleanX, sourceURL: homeURL, sourceLinkLabel: viewArticle,
        exercises: minuteCircuit(["Alt. Single Leg Low Box Squats", "1½ Bottomed Out Squats", "Jump Squats",
                                  "Handstand Pushups", "Rotational Pushups", "Cobra Pushups",
                                  "Alt. Single Leg Heel Touch Squats", "Alt. Sprinter Lunges", "Low Plyo Sprinter Lunges",
                                  "Pullups", "Human Pullovers", "Inverted Chin Curls",
                                  "Reverse Corkscrews", "Black Widow Knee Slides", "Levitation Crunches",
                                  "Angels and Devils"], rounds: 3),
        accentColorName: "blue", systemImage: "house.fill")

    static let homeBAdvanced = PreloadedRoutine(
        id: UUID(uuidString: "481AF889-2582-47F2-A713-BB9981F7EE2B")!,
        name: "Home Workout B · Advanced", seriesName: homeSeries, routineDescription: homeDescription,
        source: athleanX, sourceURL: homeURL, sourceLinkLabel: viewArticle,
        exercises: minuteCircuit(["Slick Floor Bridge Curls", "Long Leg Marches", "High Hip Bucks",
                                  "Variable Wall Pushups", "Alt. Bodyweight Side Lateral Raises", "Bodyweight Triceps Extensions",
                                  "Alt. Crossover Step Ups", "Alt. Reverse Lunges", "Split Squat Jumps",
                                  "Chinups", "Inverted Rows", "Back Widows",
                                  "Ab Halos", "V-Up Tucks", "Sit Up Elbow Thrusts",
                                  "Reverse Hyperextensions"], rounds: 3),
        accentColorName: "blue", systemImage: "house.fill")

    private static let fiveByFiveDescription = "The classic beginner barbell program: alternate A and B three days a week and add weight every session you complete all your reps — the app suggests the next weight for you."

    static let fiveByFiveA = PreloadedRoutine(
        id: UUID(uuidString: "74A98382-36D8-44CA-8292-13DC141A5707")!,
        name: "5×5 Workout A", seriesName: fiveByFiveSeries, routineDescription: fiveByFiveDescription,
        source: "StrongLifts 5×5", sourceURL: "https://stronglifts.com/stronglifts-5x5/workout-program/", sourceLinkLabel: viewArticle,
        exercises: [
            repExercise("Barbell Squat", sets: 5, reps: 5, restDuration: 180),
            repExercise("Barbell Bench Press", sets: 5, reps: 5, restDuration: 180),
            repExercise("Barbell Row", sets: 5, reps: 5, restDuration: 180),
        ],
        accentColorName: "yellow", systemImage: "scalemass.fill")

    static let fiveByFiveB = PreloadedRoutine(
        id: UUID(uuidString: "A121D6E3-CDBB-45D2-B76E-1C4DACD9F875")!,
        name: "5×5 Workout B", seriesName: fiveByFiveSeries, routineDescription: fiveByFiveDescription,
        source: "StrongLifts 5×5", sourceURL: "https://stronglifts.com/stronglifts-5x5/workout-program/", sourceLinkLabel: viewArticle,
        exercises: [
            repExercise("Barbell Squat", sets: 5, reps: 5, restDuration: 180),
            repExercise("Overhead Press", sets: 5, reps: 5, restDuration: 180),
            repExercise("Deadlift", sets: 1, reps: 5),
        ],
        accentColorName: "yellow", systemImage: "scalemass.fill")

    static let bwfRecommendedRoutine = PreloadedRoutine(
        id: UUID(uuidString: "B3612291-C225-424D-99C5-67F18E7C9F02")!,
        name: "Bodyweight Recommended Routine",
        seriesName: nil,
        routineDescription: "The r/bodyweightfitness community's starter routine: three strength pairs and a core triplet, 3×/week. Pick the hardest variation of each movement you can do for 3 sets of 5–8 with good form, and move up a variation when you hit 3×8.",
        source: "r/bodyweightfitness",
        sourceURL: "https://redditbwf.github.io/wiki/recommended_routine.html",
        sourceLinkLabel: "View Routine",
        exercises: [
            repExercise("Pull-Up Progression", sets: 1, reps: 5, repsMax: 8, notes: "e.g. scapular pulls → negatives → pull-ups.", restDuration: 90, chainRepeatCount: 3),
            repExercise("Squat Progression", sets: 1, reps: 5, repsMax: 8, notes: "e.g. assisted → split squat → Bulgarian → shrimp.", isSupersetContinuation: true, restDuration: 90),
            repExercise("Dip Progression", sets: 1, reps: 5, repsMax: 8, notes: "e.g. parallel bar support → negatives → dips.", restDuration: 90, chainRepeatCount: 3),
            repExercise("Hinge Progression", sets: 1, reps: 5, repsMax: 8, notes: "e.g. Romanian deadlift → single-leg deadlift.", isSupersetContinuation: true, restDuration: 90),
            repExercise("Row Progression", sets: 1, reps: 5, repsMax: 8, notes: "e.g. vertical → incline → horizontal rows.", restDuration: 90, chainRepeatCount: 3),
            repExercise("Push-Up Progression", sets: 1, reps: 5, repsMax: 8, notes: "e.g. incline → full → diamond → pseudo-planche.", isSupersetContinuation: true, restDuration: 90),
            repExercise("Anti-Extension (e.g. Ab Wheel)", sets: 1, reps: 8, repsMax: 12, restDuration: 60, chainRepeatCount: 3),
            repExercise("Anti-Rotation (e.g. Band Pallof Press)", sets: 1, reps: 8, repsMax: 12, isSupersetContinuation: true, restDuration: 60),
            repExercise("Extension (e.g. Reverse Hyperextension)", sets: 1, reps: 8, repsMax: 12, isSupersetContinuation: true, restDuration: 60),
        ],
        accentColorName: "orange",
        systemImage: "figure.core.training"
    )

    static let sixMinuteChest = PreloadedRoutine(
        id: UUID(uuidString: "C11A45C7-6116-4019-BD66-8620BEF366A9")!,
        name: "6-Minute Bodyweight Chest",
        seriesName: nil,
        routineDescription: "Six straight minutes: pushups from three angles, each followed by a minute of dips. Rest/pause inside a minute if you have to, but don't stop the clock.",
        source: athleanX,
        sourceURL: "https://learn.athleanx.com/articles/bodyweight-chest-workout",
        sourceLinkLabel: viewArticle,
        exercises: minuteCircuit(["Decline Pushups", "Dips", "Flat Pushups", "Dips", "Incline Pushups", "Dips"], rounds: 1, lastRest: 0),
        accentColorName: "red",
        systemImage: "flame.fill"
    )
}
