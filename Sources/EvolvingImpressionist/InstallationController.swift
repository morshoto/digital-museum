import Foundation

@MainActor
final class InstallationController: ObservableObject {
    let engine = ParameterEngine()
    let visual = VisualService()
    private let osc = OSCClient()
    private var lastVisualGeneration = Date.distantPast

    func start() {
        engine.onUpdate = { [weak self] state in
            self?.osc.send(state: state)
            guard Date().timeIntervalSince(self?.lastVisualGeneration ?? .distantPast) > 45 else { return }
            self?.lastVisualGeneration = Date()
            self?.visual.generate(for: state)
        }
        engine.start()
    }
    func stop() { engine.stop() }
}
