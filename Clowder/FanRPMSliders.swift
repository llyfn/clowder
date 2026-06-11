import ClowderKit
import SwiftUI

/// Per-fan RPM sliders for manual mode, shared by Settings → Power and the
/// expanded Temps tile. Writing a value persists it; FanControlCoordinator
/// pushes manual targets to the helper on the next poll tick.
struct FanRPMSliders: View {
    @Bindable var config: ConfigStore
    let fans: [FanReading]

    var body: some View {
        ForEach(fans) { fan in
            LabeledContent("Fan \(fan.id)") {
                Slider(value: Binding(
                    get: { config.power.manualRPMs[fan.id] ?? fan.minRPM },
                    set: { v in var p = config.power
                           p.manualRPMs[fan.id] = v.rounded(); config.power = p }),
                    in: fan.minRPM...fan.maxRPM)
                Text("\(Int(config.power.manualRPMs[fan.id] ?? fan.minRPM)) rpm")
                    .font(.caption.monospacedDigit()).frame(width: 70)
            }
        }
    }
}
