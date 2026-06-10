import AppKit
import ClowderKit

/// Owns the main status item. Animation and the panel arrive in the next task;
/// this version proves the app launches and puts a frame in the bar.
@MainActor
final class StatusItemController {
    private let environment: AppEnvironment
    private let statusItem: NSStatusItem

    init(environment: AppEnvironment) {
        self.environment = environment
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = CharacterRenderer.frames(for: environment.config.general.character).first
    }

    func loadCharacter(_ character: RunnerCharacter) {
        statusItem.button?.image = CharacterRenderer.frames(for: character).first
    }
}
