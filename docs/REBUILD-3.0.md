# 3.0 rebuild: session engine

Branch: `rebuild/session-engine`

## Why

The superset oddities came from how a running session was modelled. `SessionView` (1,800+ lines) walked the editor's flat exercise list with interlocking flags — `currentSet`, `isResting`, `restAdvancesWithinGroup`, `currentRestDurationOverride`, `groupRoundEndDate` — and three places worked out "what happens next" separately: the phone timer, the phone's Up Next label, and the watch's Up Next label. Each new feature (in-chain rests, Timed Supersets, whole-chain budgets) had to be added to all three, and they drifted apart.

Bugs found in the audit:

| Symptom | Cause |
|---|---|
| Watch Up Next says "Round N" during a rest *inside* a superset | The watch assumed rest only happens after a chain's last exercise. It never got `restAdvancesWithinGroup`. |
| A Timed Superset's budget keeps draining while paused (whole-chain caps fire on resume) | Pause/resume shifted `phaseEndDate` but not `groupRoundEndDate`. |
| Watch recap set counts wrong for supersets | It added up each exercise's `sets` and ignored `chainRepeatCount`. |
| Undo restores only some state | It restored index, set and active time, but not rest time, budget state or the in-chain rest flag. It also never re-synced the watch. |
| Locked phone: only the first phase end chimes; timing drifts | One notification was scheduled at a time, and on wake each new phase started from "now" instead of when the last one ended. |
| Stale Timed Superset budget on an exercise that was unlinked | The budget was read from any group head, including single exercises. |
| Pointless rest after the very last set | A trailing rest was always added when `restDuration > 0`. |
| Audio node leak | Each beep attached a new `AVAudioPlayerNode` and never detached it. |
| `ended early` recap counted "exercises completed" as index + 1 | It was rebuilt from indices instead of from what actually happened. |

## New architecture

```
Exercise list ──compile──▶ WorkoutPlan (linear steps + blocks + budget windows)
                                │
                                ▼
                         SessionEngine (pure value type; every call takes `now`)
                          ▲          │
         actions (phone/watch)       ├─▶ SessionPresentation (all labels, shared)
                                     └─▶ SessionRecap (from the set log)

SessionController (phone/Mac): clock, sounds, notifications, HealthKit, watch sync, history
WatchWorkoutEngine (watch):    rebuilds the same SessionEngine from each SessionSync
```

- **`WorkoutPlan`** (`Shared/WorkoutPlan.swift`) flattens the routine once into steps: `work`, `rest`, or `budgetRest`, the leftover-time rest a Timed Superset's budget produces. Supersets, round counts and budgets are resolved here and nowhere else.
- **`SessionEngine`** (`Shared/SessionEngine.swift`) is the state machine:
  - `tick(now:)` catches up through every phase that ended, chaining each from the previous phase's end time.
  - Pause freezes countdowns and budgets alike.
  - Undo restores a full snapshot and works for any action.
  - A set log (`SetRecord`) records what was actually done.
- **`SessionPresentation`** derives every label, so the iPhone, Mac and watch can't disagree.
- **Watch sync**: the old `.updatePhase` / `.updateWeight` / `.updateTargetReps` commands are replaced by one `.sync(SessionSync)` that carries the exercise list and the engine state.
  - The newest copy is also parked in the WatchConnectivity application context, so a watch that was asleep catches up when it reconnects.
  - The watch advances its own copy through timed phases, so it keeps counting while the phone is locked.

## Behaviour changes to know about

- During a rest, the headline shows the exercise **coming up**, not the one just finished. Up Next then looks one step further ("Then: …").
- A set cut off by a whole-chain time cap counts as skipped, not completed.
- There's no rest after the final set of the workout.
- A Timed Superset budget left on a single (unlinked) exercise is ignored.
- Notifications are scheduled for every hands-free phase end, up to the next rep-based set (maximum 24).
- **Watch and phone must be on the same build.** The command protocol changed (`.sync` replaces `.updatePhase`).

## Fitness+ Gym Strength-inspired features

- **Set logging**: rep-based sets show a reps stepper prefilled with the target. During the next rest, a "Log" card lets you correct the reps or weight of the set you just finished.
- **Last time + progression**: each exercise shows what you did last session. A double-progression hint appears too: if every set hit the top of the rep range, the hint suggests the next weight up; for bodyweight exercises it suggests one more rep.
- **Milestones** in the recap: heaviest weight yet, most reps yet, and exercises logged for the first time.
- **Workout preview** from the builder: blocks in order, supersets grouped (A/B/C), estimated time, total sets, and "Last:" for each exercise. The same view opens mid-session as **Plan**, with your position marked.
- **In-the-moment changes** (••• menu): swap an exercise (rename it for this session only), skip the rest of an exercise or superset, add a set or round, and undo.
- **Block progress strip** across the top, plus a countdown ring.
- History is stored on-device in `Application Support/WorkoutHistory.json` (capped at 500 workouts) and can be cleared in Settings.

## Tests

`ExerciseTimerTests/SessionEngineTests.swift` (27 tests) covers:

- plan shapes
- background catch-up
- pausing during countdowns and budgets
- whole-chain caps cutting mid-round
- per-round leftover rest
- superset round looping
- undo
- add round / skip block
- set logging and early end
- notification projection
- phone/watch label parity
- progression and history

The engine files are plain Foundation. These tests were run on Swift 6.1 (Linux) against the same source files.

## Not built yet (ideas)

- Watch: log reps with the Digital Crown before confirming, and add an Undo button. The `.undo` command already exists.
- A 4-week progressive plan generator from goals, schedule and equipment, like Fitness+. History now provides the data it would need.
- An on-device Foundation Models "training note": a pre-workout preview and a post-workout summary of progression.
- Equipment tags on exercises, plus "similar exercise" suggestions for Swap.
- Live Activity / Dynamic Island countdown, driven by `SessionEngine.nextEventDate`.
- An exercise history screen with charts (estimated 1RM using `Progression.estimatedOneRepMax`).
