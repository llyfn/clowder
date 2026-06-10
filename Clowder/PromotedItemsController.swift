import AppKit
import ClowderKit
import SwiftUI

/// Creates/destroys one extra NSStatusItem per module with `promotedToBar` on.
@MainActor
final class PromotedItemsController {
    private let environment: AppEnvironment
    private var items: [ModuleID: NSStatusItem] = [:]
    private var observationTask: Task<Void, Never>?

    init(environment: AppEnvironment) {
        self.environment = environment
        sync()
        observationTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.observeConfigOnce()
            }
        }
    }

    deinit {
        observationTask?.cancel()
    }

    private func observeConfigOnce() async {
        await withCheckedContinuation { continuation in
            withObservationTracking {
                for module in environment.allModules {
                    _ = environment.config.config(for: module.id).promotedToBar
                }
            } onChange: {
                Task { @MainActor in continuation.resume() }
            }
        }
        sync()
    }

    private func sync() {
        for module in environment.allModules {
            let wantsItem = environment.config.config(for: module.id).promotedToBar
                && module.barItemView != nil
            if wantsItem, items[module.id] == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                let host = makeHost(for: module)
                host.translatesAutoresizingMaskIntoConstraints = false
                if let button = item.button {
                    button.addSubview(host)
                    NSLayoutConstraint.activate([
                        host.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                        host.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                        host.topAnchor.constraint(equalTo: button.topAnchor),
                        host.bottomAnchor.constraint(equalTo: button.bottomAnchor),
                    ])
                }
                items[module.id] = item
            } else if !wantsItem, let item = items[module.id] {
                NSStatusBar.system.removeStatusItem(item)
                items[module.id] = nil
            }
        }
    }

    private func makeHost(for module: some Module) -> NSView {
        NSHostingView(rootView: BarItemWrapper(module: module))
    }
}

/// Re-renders the module's bar view when snapshots update.
private struct BarItemWrapper<M: Module>: View {
    let module: M

    var body: some View {
        (module.barItemView ?? AnyView(EmptyView()))
            .font(.system(size: 12))
            .padding(.horizontal, 4)
            .fixedSize()
    }
}
