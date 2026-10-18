import Playback
import SwiftUI

/// Playback speed for the current book: a fine stepper, a slider and presets. The controller clamps and remembers it.
struct SpeedSheet: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var player = player
        NavigationStack {
            VStack(spacing: 24) {
                Text("\(player.rate.formatted())×")
                    .font(.system(size: 56, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityHidden(true)
                HStack(spacing: 16) {
                    Button("Slower", systemImage: "minus") { nudge(-PlaybackSpeed.step) }
                    Slider(value: $player.rate, in: PlaybackSpeed.range, step: PlaybackSpeed.step)
                        .accessibilityLabel("Speed")
                        .accessibilityValue("\(player.rate.formatted()) times")
                    Button("Faster", systemImage: "plus") { nudge(PlaybackSpeed.step) }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                HStack {
                    ForEach(PlaybackSpeed.presets, id: \.self) { preset in
                        if player.rate == preset {
                            Button("\(preset.formatted())×") { player.rate = preset }.buttonStyle(.glassProminent)
                        } else {
                            Button("\(preset.formatted())×") { player.rate = preset }.buttonStyle(.glass)
                        }
                    }
                }
                .monospacedDigit()
                Spacer(minLength: 0)
            }
            .padding(24)
            .navigationTitle("Speed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done", role: .confirm) { dismiss() } }
            }
        }
        .presentationDetents([.height(320)])
    }

    private func nudge(_ delta: Float) {
        player.rate += delta
    }
}

#Preview {
    SpeedSheet().environment(PlayerController.preview())
}
