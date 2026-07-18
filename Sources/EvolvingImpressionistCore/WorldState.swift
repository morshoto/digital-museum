import Foundation

public enum WorldParameter: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case brightness, warmth, abstraction, motion, tension
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public struct WorldState: Codable, Equatable, Sendable {
    public var brightness: Double
    public var warmth: Double
    public var abstraction: Double
    public var motion: Double
    public var tension: Double

    public init(
        brightness: Double = 0.58,
        warmth: Double = 0.62,
        abstraction: Double = 0.28,
        motion: Double = 0.42,
        tension: Double = 0.22
    ) {
        self.brightness = brightness
        self.warmth = warmth
        self.abstraction = abstraction
        self.motion = motion
        self.tension = tension
    }

    public subscript(_ parameter: WorldParameter) -> Double {
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

/// Higher-level qualities shared by the visual and musical mappings.
///
/// These values are derived only from `WorldState`: they add no transport
/// fields or independent randomness, and every component remains in `0...1`
/// when the raw inputs are normalized.
public struct ArtisticState: Codable, Equatable, Sendable {
    public let luminosity: Double
    public let fluidity: Double
    public let instability: Double
    public let serenity: Double
    public let density: Double

    public init(world: WorldState) {
        luminosity = 0.70 * world.brightness + 0.30 * world.warmth
        fluidity = 0.65 * world.motion + 0.35 * world.abstraction
        instability = 0.65 * world.tension + 0.35 * world.abstraction
        serenity = 1 - (0.55 * world.tension + 0.25 * world.motion + 0.20 * world.abstraction)
        density = 0.60 * world.motion + 0.25 * world.abstraction + 0.15 * world.tension
    }
}

public extension WorldState {
    var artistic: ArtisticState { ArtisticState(world: self) }
}

public struct SineComponent: Codable, Equatable, Sendable {
    public var amplitude: Double
    public var period: Double
    public var phase: Double

    public init(amplitude: Double, period: Double, phase: Double) {
        self.amplitude = amplitude
        self.period = max(0.001, period)
        self.phase = phase
    }

    public func value(at time: TimeInterval) -> Double {
        amplitude * sin((2 * .pi * time / max(0.001, period)) + phase)
    }
}

public struct WaveConfiguration: Codable, Equatable, Sendable {
    public var base: Double
    public var components: [SineComponent]
    public var lowFrequencyModulation: SineComponent?

    public init(base: Double, components: [SineComponent], lowFrequencyModulation: SineComponent? = nil) {
        self.base = base
        self.components = components
        self.lowFrequencyModulation = lowFrequencyModulation
    }

    public var primaryAmplitude: Double {
        get { components.first?.amplitude ?? 0 }
        set { ensurePrimary(); components[0].amplitude = newValue }
    }

    public var primaryPeriod: Double {
        get { components.first?.period ?? 60 }
        set { ensurePrimary(); components[0].period = max(0.001, newValue) }
    }

    public var primaryPhase: Double {
        get { components.first?.phase ?? 0 }
        set { ensurePrimary(); components[0].phase = newValue }
    }

    public func value(at time: TimeInterval) -> Double {
        let waves = components.reduce(0) { $0 + $1.value(at: time) }
        let modulation = lowFrequencyModulation?.value(at: time) ?? 0
        return Self.clamp(base + waves + modulation)
    }

    private mutating func ensurePrimary() {
        if components.isEmpty { components = [.init(amplitude: 0, period: 60, phase: 0)] }
    }

    public static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
}

public struct ParameterModulator: Sendable {
    public var configurations: [WorldParameter: WaveConfiguration]

    public init(configurations: [WorldParameter: WaveConfiguration] = Self.defaultConfigurations) {
        self.configurations = configurations
    }

    public func state(at time: TimeInterval, overrides: [WorldParameter: Double] = [:]) -> WorldState {
        var state = WorldState()
        for parameter in WorldParameter.allCases {
            let generated = configurations[parameter]?.value(at: time) ?? state[parameter]
            state[parameter] = WaveConfiguration.clamp(overrides[parameter] ?? generated)
        }
        return state
    }

    public static let defaultConfigurations: [WorldParameter: WaveConfiguration] = [
        .brightness: .init(base: 0.56, components: [.init(amplitude: 0.14, period: 83, phase: 0.2), .init(amplitude: 0.05, period: 149, phase: 1.7)], lowFrequencyModulation: .init(amplitude: 0.025, period: 997, phase: 2.4)),
        .warmth: .init(base: 0.60, components: [.init(amplitude: 0.16, period: 137, phase: 2.0), .init(amplitude: 0.06, period: 263, phase: 0.8)], lowFrequencyModulation: .init(amplitude: 0.02, period: 1217, phase: 4.0)),
        .abstraction: .init(base: 0.32, components: [.init(amplitude: 0.17, period: 761, phase: 1.1), .init(amplitude: 0.07, period: 1597, phase: 3.5)], lowFrequencyModulation: .init(amplitude: 0.02, period: 2693, phase: 0.4)),
        .motion: .init(base: 0.43, components: [.init(amplitude: 0.15, period: 31, phase: 3.2), .init(amplitude: 0.06, period: 71, phase: 5.1)], lowFrequencyModulation: .init(amplitude: 0.025, period: 607, phase: 1.3)),
        .tension: .init(base: 0.28, components: [.init(amplitude: 0.14, period: 419, phase: 4.4), .init(amplitude: 0.07, period: 941, phase: 2.2)], lowFrequencyModulation: .init(amplitude: 0.02, period: 1877, phase: 5.4))
    ]
}

@MainActor
public final class ParameterEngine: ObservableObject {
    @Published public private(set) var state: WorldState
    @Published public var configurations: [WorldParameter: WaveConfiguration]
    @Published public var overrides: [WorldParameter: Double] = [:]
    public var onUpdate: ((WorldState) -> Void)?

    private var timer: Timer?
    private var startedAt: TimeInterval

    public init(configurations: [WorldParameter: WaveConfiguration] = ParameterModulator.defaultConfigurations) {
        self.configurations = configurations
        self.state = ParameterModulator(configurations: configurations).state(at: 0)
        self.startedAt = ProcessInfo.processInfo.systemUptime
    }

    public func sample(at time: TimeInterval) -> WorldState {
        ParameterModulator(configurations: configurations).state(at: time, overrides: overrides)
    }

    public func setOverride(_ value: Double?, for parameter: WorldParameter) {
        overrides[parameter] = value.map(WaveConfiguration.clamp)
        tick(at: ProcessInfo.processInfo.systemUptime - startedAt)
    }

    public func start() {
        guard timer == nil else { return }
        startedAt = ProcessInfo.processInfo.systemUptime
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick(at: ProcessInfo.processInfo.systemUptime - (self?.startedAt ?? 0)) }
        }
        tick(at: 0)
    }

    public func stop() { timer?.invalidate(); timer = nil }

    private func tick(at time: TimeInterval) {
        state = sample(at: time)
        onUpdate?(state)
    }
}
