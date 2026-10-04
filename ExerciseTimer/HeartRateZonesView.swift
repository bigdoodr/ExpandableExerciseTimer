import SwiftUI

/// Shows how heart-rate zones break down — from the person's age (read from the Health app) when
/// available, or a default max heart rate otherwise — and lets them override with manual zones,
/// similar to the Health app's own zone editor. Pushed from `SettingsView`.
struct HeartRateZonesView: View {
    /// Called after a manual-zone edit is saved, so the caller can re-push the updated settings
    /// to the watch (there's no other signal for "zones changed" short of the exercise list itself
    /// changing, which is what normally triggers a resync).
    var onSettingsChanged: () -> Void = {}

#if os(iOS) && canImport(HealthKit)
    @ObservedObject private var healthKit = HealthKitWorkoutManager.shared
#endif

    @State private var zoneSettings = HRZoneStore.load()

    private var effectiveMaxHR: Double {
#if os(iOS) && canImport(HealthKit)
        healthKit.maxHeartRate
#else
        HRZoneCalculator.defaultMaxHR
#endif
    }

    private var effectiveBoundaries: [Double] {
        if let manual = zoneSettings.upperBounds, !manual.isEmpty {
            return manual
        }
        return HRZoneCalculator.boundaries(maxHR: effectiveMaxHR)
    }

    private var zoneSourceDescription: String {
        if zoneSettings.upperBounds != nil { return "Manual" }
#if os(iOS) && canImport(HealthKit)
        if healthKit.age != nil { return "Based on your age" }
#endif
        return "Default"
    }

    var body: some View {
        Form {
#if os(iOS) && canImport(HealthKit)
            Section {
                if let age = healthKit.age {
                    Label(
                        "You allowed Exercise Timer to read your age from the Health app. It indicates you're \(age) years old — estimated max heart rate \(Int(healthKit.maxHeartRate)) BPM. Here's how that breaks down per zone.",
                        systemImage: "heart.text.square.fill"
                    )
                    .foregroundStyle(.secondary)
                } else {
                    Label(
                        "Your age isn't available — Health access may be off, or no birthday is set in Health. Showing default zones (max heart rate \(Int(HRZoneCalculator.defaultMaxHR)) BPM) until manual zones are set.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    Button("Allow Health Access") {
                        Task { await HealthKitWorkoutManager.shared.requestAuthorization() }
                    }
                }
            }
#endif
            Section {
                ForEach(1...5, id: \.self) { zoneNumber in
                    zoneRow(zoneNumber)
                }
            } header: {
                Text("Zones")
            } footer: {
                Text("Source: \(zoneSourceDescription)")
            }

            Section {
                Toggle("Use Manual Zones", isOn: Binding(
                    get: { zoneSettings.upperBounds != nil },
                    set: { enabled in
                        zoneSettings.upperBounds = enabled ? effectiveBoundaries : nil
                        save()
                    }
                ))

                if let bounds = zoneSettings.upperBounds {
                    ForEach(bounds.indices, id: \.self) { index in
                        Stepper(value: Binding(
                            get: { bounds[index] },
                            set: { newValue in
                                var updated = zoneSettings.upperBounds ?? bounds
                                let lowerLimit = index > 0 ? updated[index - 1] + 1 : 30
                                let upperLimit = index < updated.count - 1 ? updated[index + 1] - 1 : 220
                                updated[index] = min(max(newValue, lowerLimit), upperLimit)
                                zoneSettings.upperBounds = updated
                                save()
                            }
                        ), in: 30...220, step: 1) {
                            Text("Zone \(index + 1)/\(index + 2) boundary: \(Int(bounds[index])) BPM")
                        }
                    }
                    Button("Reset to Automatic", role: .destructive) {
                        zoneSettings.upperBounds = nil
                        save()
                    }
                }
            } header: {
                Text("Manual Zones")
            } footer: {
                Text("Overrides both the Health app's zones and the age-based estimate.")
            }
        }
        .navigationTitle("Heart Rate Zones")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }

    private func zoneRow(_ number: Int) -> some View {
        let boundaries = effectiveBoundaries
        let lower: Double? = number == 1 ? nil : boundaries[safe: number - 2]
        let upper: Double? = boundaries[safe: number - 1]
        return HStack {
            Circle()
                .fill(HRZoneCalculator.color(forZone: number))
                .frame(width: 12, height: 12)
            Text(HRZoneCalculator.name(forZone: number))
            Spacer()
            Text(rangeText(lower: lower, upper: upper))
                .foregroundStyle(.secondary)
        }
    }

    private func rangeText(lower: Double?, upper: Double?) -> String {
        switch (lower, upper) {
        case (nil, let upper?): return "< \(Int(upper)) BPM"
        case (let lower?, let upper?): return "\(Int(lower))–\(Int(upper)) BPM"
        case (let lower?, nil): return "\(Int(lower))+ BPM"
        default: return ""
        }
    }

    private func save() {
        HRZoneStore.save(zoneSettings)
        onSettingsChanged()
    }
}
