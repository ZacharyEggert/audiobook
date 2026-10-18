import Playback
import SwiftUI

/// Start, extend or cancel the sleep timer: presets from 5 to 120 min, a custom length, or the end of the chapter.
struct SleepTimerSheet: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var custom = 45

    private static let presets = [5, 10, 15, 30, 45, 60, 90, 120]

    var body: some View {
        let timer = player.sleepTimer
        NavigationStack {
            List {
                if let remaining = timer.remaining {
                    Section {
                        Text(Duration.seconds(remaining.rounded(.up)).formatted(.time(pattern: .hourMinuteSecond)))
                            .font(.system(size: 48, weight: .bold).monospacedDigit())
                            .frame(maxWidth: .infinity)
                            .accessibilityLabel("Stops in \(Self.spoken(remaining))")
                        Button("Add \(Int((timer.lastDuration ?? SleepTimer.defaultExtension) / 60)) Minutes", systemImage: "plus") {
                            player.extendSleepTimer()
                        }
                        Button("Cancel Timer", systemImage: "xmark", role: .destructive) {
                            timer.cancel()
                            dismiss()
                        }
                    }
                }
                Section("Stop After") {
                    ForEach(Self.presets, id: \.self) { minutes in
                        Button("\(minutes) minutes") { start(minutes) }
                    }
                    if player.chapter != nil {
                        Button("End of Chapter") {
                            player.startSleepTimerAtChapterEnd()
                            dismiss()
                        }
                    }
                }
                Section("Custom") {
                    Stepper("\(custom) minutes", value: $custom, in: 1 ... 600)
                    Button("Start") { start(custom) }
                }
            }
            .navigationTitle("Sleep Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done", role: .confirm) { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private static func spoken(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds.rounded(.up)).formatted(.units(allowed: [.hours, .minutes, .seconds]))
    }

    private func start(_ minutes: Int) {
        player.startSleepTimer(.duration(TimeInterval(minutes) * 60))
        dismiss()
    }
}

#Preview {
    SleepTimerSheet().environment(PlayerController.preview())
}
