import Foundation

enum WorldParameter: String, CaseIterable, Codable, Hashable, Identifiable {
    case brightness, warmth, abstraction, motion, tension
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct WaveConfiguration: Codable {
    var base: Double
    var amplitude: Double
    var frequency: Double
    var phase: Double
    var noiseAmount: Double

    func value(at time: Double) -> Double {
        let primary = amplitude * sin(2 * .pi * frequency * time + phase)
        let secondary = amplitude * 0.38 * sin(2 * .pi * frequency * 1.618 * time + phase * 0.7)
        let noise = noiseAmount * sin(2 * .pi * frequency * 0.173 * time + phase * 2.3)
        return min(1, max(0, base + primary + secondary + noise))
    }
}

struct WorldState: Codable, Equatable {
    var brightness = 0.58
    var warmth = 0.62
    var abstraction = 0.28
    var motion = 0.42
    var tension = 0.22

    subscript(_ parameter: WorldParameter) -> Double {
        get {
            switch parameter {
            case .brightness: brightness
            case .warmth: warmth
            case .abstraction: abstraction
            case .motion: motion
            case .tension: tension
            }
        }
        set {
            switch parameter {
            case .brightness: brightness = newValue
            case .warmth: warmth = newValue
            case .abstraction: abstraction = newValue
            case .motion: motion = newValue
            case .tension: tension = newValue
            }
        }
    }
}

@MainActor
final class ParameterEngine: ObservableObject {
    @Published private(set) var state = WorldState()
    @Published var configurations: [WorldParameter: WaveConfiguration] = ParameterEngine.defaultConfigurations
    @Published var overrides: [WorldParameter: Double] = [:]
    var onUpdate: ((WorldState) -> Void)?

    private var timer: Timer?
    private let startedAt = ProcessInfo.processInfo.systemUptime

    static let defaultConfigurations: [WorldParameter: WaveConfiguration] = [
        .brightness: .init(base: 0.56, amplitude: 0.17, frequency: 1 / 83, phase: 0.2, noiseAmount: 0.035),
        .warmth: .init(base: 0.60, amplitude: 0.20, frequency: 1 / 137, phase: 2.0, noiseAmount: 0.03),
        .abstraction: .init(base: 0.28, amplitude: 0.22, frequency: 1 / 761, phase: 1.1, noiseAmount: 0.025),
        .motion: .init(base: 0.43, amplitude: 0.19, frequency: 1 / 31, phase: 3.2, noiseAmount: 0.04),
        .tension: .init(base: 0.23, amplitude: 0.18, frequency: 1 / 419, phase: 4.4, noiseAmount: 0.025)
    ]

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        tick()
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func tick() {
        let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
        var next = WorldState()
        for parameter in WorldParameter.allCases {
            next[parameter] = overrides[parameter] ?? configurations[parameter]!.value(at: elapsed)
        }
        state = next
        onUpdate?(next)
    }
}
