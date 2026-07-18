import EvolvingImpressionistCore
import Foundation

@MainActor
final class InstallationController: ObservableObject {
    let engine = ParameterEngine()
    let visual = VisualService()
    let osc: OSCClient
    private var lastVisualGeneration = Date.distantPast
    private var lastOSCSend = Date.distantPast
    private let generationInterval: TimeInterval

    init(generationInterval: TimeInterval = Double(ProcessInfo.processInfo.environment["EVOLVING_GENERATION_INTERVAL"] ?? "45") ?? 45) {
        self.generationInterval = max(1, generationInterval)
        let environment = ProcessInfo.processInfo.environment
        let host = environment["EVOLVING_OSC_HOST"] ?? "127.0.0.1"
        let port = UInt16(environment["EVOLVING_OSC_PORT"] ?? "57120") ?? 57120
        self.osc = OSCClient(host: host, port: port)
    }

    func start() {
        Task { await visual.checkHealth() }
        engine.onUpdate = { [weak self] state in
            guard let self else { return }
            let now = Date()
            if now.timeIntervalSince(lastOSCSend) >= 0.1 {
                lastOSCSend = now
                osc.send(state: state)
            }
            guard now.timeIntervalSince(lastVisualGeneration) > generationInterval else { return }
            lastVisualGeneration = now
            Task { await self.visual.generate(for: state) }
        }
        engine.start()
    }
    func stop() { engine.stop() }

    func generateNow() { Task { await visual.generate(for: engine.state) } }
}
