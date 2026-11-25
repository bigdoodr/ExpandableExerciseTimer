import SwiftUI
#if canImport(HealthKit)
import HealthKit
#endif

/// End-of-session summary. Numbers come straight from the engine's set log (`SessionRecap`), so
/// supersets, skips and early ends are counted the same on every device.
struct SessionRecapView: View {
    @ObservedObject var controller: SessionController
    let recap: SessionRecap
    let onDone: () -> Void
#if canImport(WatchConnectivity)
    @ObservedObject private var connectivity = WatchConnectivityManager.shared
#endif

    private var kind: SessionKind { controller.kind }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Image(systemName: recap.completedNaturally ? "checkmark.circle.fill" : "stop.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(recap.completedNaturally ? .green : .orange)
                        Text(recap.completedNaturally ? kind.recapCompletedTitle : kind.recapEndedTitle)
                            .font(.title.bold())
                        if let name = controller.routineName {
                            Text(name).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top)

                    if !controller.milestones.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Milestones", systemImage: "trophy.fill")
                                .font(.headline)
                                .foregroundStyle(.yellow)
                            ForEach(controller.milestones) { m in
                                HStack {
                                    Text(m.exerciseName).bold()
                                    Spacer()
                                    Text(m.detail).foregroundStyle(.secondary)
                                }
                                .font(.subheadline)
                            }
                        }
                        .padding()
                        .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal)
                    }

                    stats
                        .padding()
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.horizontal)

                    if kind == .workout, recap.records.contains(where: { !$0.skipped }) {
                        setLog
                            .padding()
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .padding(.horizontal)
                    }

                    GlassActionButton(tint: .green, action: onDone) {
                        Text("Done").font(.headline)
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom)
            }
            .navigationTitle("Summary")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
        }
    }

    private var stats: some View {
        VStack(spacing: 16) {
            row("clock", .blue, "Duration", SessionFormat.time(recap.duration))
            Divider()
            row(kind.recapItemsIcon, .green, kind.recapItemsLabel, "\(recap.exercisesPerformed) of \(recap.exerciseCount)")
            Divider()
            row(kind.recapSetsIcon, .purple, kind.recapSetsLabel, "\(recap.setsCompleted) of \(recap.totalSets)")
            Divider()
            row(kind.recapActiveIcon, .green, kind.recapActiveLabel, SessionFormat.time(recap.activeTime))
            Divider()
            row(kind.recapRestIcon, .blue, kind.recapRestLabel, SessionFormat.time(recap.restTime))
            if recap.setsSkipped > 0 {
                Divider()
                row("forward.end.fill", .orange, kind == .workout ? "Sets Skipped" : "Cycles Skipped", "\(recap.setsSkipped)")
            }
            if recap.restSkipped > 0 {
                Divider()
                row("forward.end.fill", .orange, kind.recapRestSkippedLabel, SessionFormat.time(recap.restSkipped))
            }
#if canImport(HealthKit) && !os(macOS)
            if kind == .workout {
                healthRows
            }
#endif
        }
    }

    /// Per-exercise log of what was actually lifted — the data that feeds "Last time" next session.
    private var setLog: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sets Logged").font(.headline)
            let grouped = Dictionary(grouping: recap.records.filter { !$0.skipped }, by: \.exerciseIndex)
            ForEach(grouped.keys.sorted(), id: \.self) { index in
                let sets = grouped[index] ?? []
                VStack(alignment: .leading, spacing: 4) {
                    Text(sets.first?.exerciseName.isEmpty == false ? sets[0].exerciseName : "\(kind.itemName) \(index + 1)")
                        .font(.subheadline.bold())
                    Text(sets.map(describe).joined(separator: "  ·  "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func describe(_ r: SetRecord) -> String {
        let amount = r.reps.map { "\($0)" } ?? SessionFormat.time(r.activeDuration)
        guard let w = r.weight, w > 0 else { return amount }
        return "\(amount) × \(SessionFormat.weight(w, unit: r.weightUnit))"
    }

    private func row(_ icon: String, _ color: Color, _ label: String, _ value: String) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(color).frame(width: 28)
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).bold().monospacedDigit()
        }
    }

#if canImport(HealthKit) && !os(macOS)
    @ViewBuilder
    private var healthRows: some View {
        let hr = controller.averageHeartRate
        let calories = HealthKitWorkoutManager.shared.activeCalories
        if hr > 0 {
            Divider()
            row("heart.fill", .red, "Avg Heart Rate", "\(Int(hr)) BPM")
        }
        if calories > 0 {
            Divider()
            row("flame.fill", .orange, "Calories", "\(Int(calories)) CAL")
        }
        let zones = zoneEntries
        if !zones.isEmpty {
            Divider()
            HeartRateZoneBreakdown(entries: zones)
        } else if hr > 0 {
#if os(iOS)
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("Heart Rate Zones").font(.subheadline).foregroundStyle(.secondary)
                Text("Calculating your zone breakdown — this can take a few seconds to appear.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
#endif
        }
    }

    /// Zones forwarded from the watch (it owns the HealthKit session when present), else read
    /// from the iPhone's own finished workout.
    private var zoneEntries: [HRZoneRecapEntry] {
#if canImport(WatchConnectivity)
        if !connectivity.completedZoneSummary.isEmpty { return connectivity.completedZoneSummary }
#endif
#if os(iOS)
        if #available(iOS 27.0, *), controller.healthKitEnabled,
           let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate),
           let zoneGroups = HealthKitWorkoutManager.shared.finishedWorkout?.zoneGroupsByType,
           let group = zoneGroups[hrType] {
            let bpm = HKUnit.count().unitDivided(by: .minute())
            return group.zoneDurations.enumerated().map { index, zd in
                HRZoneRecapEntry(zoneIndex: index, duration: zd.duration,
                                 minBPM: zd.zone.minimum?.doubleValue(for: bpm),
                                 maxBPM: zd.zone.maximum?.doubleValue(for: bpm))
            }
        }
#endif
        return []
    }
#endif
}

/// Time-in-zone bars (unchanged from the previous recap, just extracted).
struct HeartRateZoneBreakdown: View {
    let entries: [HRZoneRecapEntry]

    var body: some View {
        let total = entries.reduce(0.0) { $0 + $1.duration }
        // A 6th (lowest) zone means a resting-HR boundary was prepended — label it "Resting".
        let hasResting = entries.count == 6
        VStack(alignment: .leading, spacing: 10) {
            Text("Heart Rate Zones").font(.subheadline).foregroundStyle(.secondary)
            ForEach(entries, id: \.zoneIndex) { entry in
                let isResting = hasResting && entry.zoneIndex == 0
                let number = hasResting ? entry.zoneIndex : entry.zoneIndex + 1
                let color = isResting ? Color.gray : HRZoneColors.color(number)
                VStack(spacing: 6) {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4, height: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isResting ? "Resting" : "Zone \(number)").font(.subheadline)
                            let label = bpmLabel(entry)
                            if !label.isEmpty { Text(label).font(.caption2).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Text(SessionFormat.time(entry.duration))
                            .font(.subheadline.bold())
                            .foregroundStyle(entry.duration > 0 ? Color.primary : Color.secondary)
                            .monospacedDigit()
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.2))
                            if total > 0 && entry.duration > 0 {
                                Capsule().fill(color).frame(width: geo.size.width * CGFloat(entry.duration / total))
                            }
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
    }

    private func bpmLabel(_ e: HRZoneRecapEntry) -> String {
        switch (e.minBPM.map { Int($0) }, e.maxBPM.map { Int($0) }) {
        case (nil, let hi?): return "<\(hi) bpm"
        case (let lo?, nil): return ">\(lo) bpm"
        case (let lo?, let hi?): return "\(lo)–\(hi) bpm"
        default: return ""
        }
    }
}
