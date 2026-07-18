import AppKit
import Foundation

public struct VisualTransitionConfiguration: Equatable, Sendable {
    public var duration: TimeInterval
    public var minimumScale: Double
    public var maximumScale: Double
    public var minimumOffsetAmplitude: Double
    public var maximumOffsetAmplitude: Double

    public init(
        duration: TimeInterval = 1.2,
        minimumScale: Double = 1.004,
        maximumScale: Double = 1.005,
        minimumOffsetAmplitude: Double = 0.35,
        maximumOffsetAmplitude: Double = 2
    ) {
        self.duration = max(0.001, duration)
        self.minimumScale = min(1.005, max(1, minimumScale))
        self.maximumScale = min(1.005, max(self.minimumScale, maximumScale))
        self.minimumOffsetAmplitude = min(2, max(0, minimumOffsetAmplitude))
        self.maximumOffsetAmplitude = min(2, max(self.minimumOffsetAmplitude, maximumOffsetAmplitude))
    }

    public static let installation = VisualTransitionConfiguration()
}

public struct VisualPresentationTransform: Equatable, Sendable {
    public let scale: Double
    public let offsetX: Double
    public let offsetY: Double

    public init(scale: Double, offsetX: Double, offsetY: Double) {
        self.scale = scale
        self.offsetX = offsetX
        self.offsetY = offsetY
    }
}

public struct VisualPresentationLayer: Identifiable {
    public let id: Int
    public let image: NSImage
    public let opacity: Double

    public init(id: Int, image: NSImage, opacity: Double) {
        self.id = id
        self.image = image
        self.opacity = opacity
    }
}

public struct VisualTransitionTimeline {
    private struct Keyframe {
        let id: Int
        let image: NSImage
        var opacity: Double
    }

    public let configuration: VisualTransitionConfiguration
    public private(set) var transitionStartTime: TimeInterval?
    public private(set) var transitionDuration: TimeInterval
    public private(set) var latestTransitionID = 0

    private var previousKeyframes: [Keyframe] = []
    private var targetKeyframe: Keyframe?
    private var lastKeyframeArrivalTime: TimeInterval?

    public init(configuration: VisualTransitionConfiguration = .installation) {
        self.configuration = configuration
        self.transitionDuration = configuration.duration
    }

    public var hasValidImage: Bool {
        targetKeyframe != nil || !previousKeyframes.isEmpty
    }

    public var targetImage: NSImage? {
        targetKeyframe?.image ?? previousKeyframes.max(by: { $0.opacity < $1.opacity })?.image
    }

    public func normalizedProgress(at time: TimeInterval) -> Double {
        guard targetKeyframe != nil, let transitionStartTime else { return hasValidImage ? 1 : 0 }
        return min(1, max(0, (time - transitionStartTime) / transitionDuration))
    }

    public mutating func receive(_ frame: VisualFrame, at time: TimeInterval) {
        guard frame.transitionID > latestTransitionID, let image = frame.currentImage else { return }

        let visibleLayers = presentation(at: time).filter { $0.opacity > 0.000_001 }
        latestTransitionID = frame.transitionID

        if visibleLayers.isEmpty {
            previousKeyframes = [Keyframe(id: frame.transitionID, image: image, opacity: 1)]
            targetKeyframe = nil
            transitionStartTime = nil
            lastKeyframeArrivalTime = time
            return
        }

        previousKeyframes = visibleLayers.map {
            Keyframe(id: $0.id, image: $0.image, opacity: $0.opacity)
        }
        targetKeyframe = Keyframe(id: frame.transitionID, image: image, opacity: 1)
        transitionStartTime = time
        if let lastKeyframeArrivalTime {
            let arrivalInterval = max(0, time - lastKeyframeArrivalTime)
            transitionDuration = min(configuration.duration, max(1.2, arrivalInterval * 0.9))
        } else {
            transitionDuration = configuration.duration
        }
        lastKeyframeArrivalTime = time
    }

    public func presentation(at time: TimeInterval) -> [VisualPresentationLayer] {
        guard let targetKeyframe else {
            return previousKeyframes.map {
                VisualPresentationLayer(id: $0.id, image: $0.image, opacity: $0.opacity)
            }
        }

        let blend = Self.smootherstep(normalizedProgress(at: time))
        let outgoing = previousKeyframes.map {
            VisualPresentationLayer(id: $0.id, image: $0.image, opacity: $0.opacity * (1 - blend))
        }
        return outgoing + [VisualPresentationLayer(id: targetKeyframe.id, image: targetKeyframe.image, opacity: blend)]
    }

    public func presentationTransform(at time: TimeInterval, worldState: WorldState) -> VisualPresentationTransform {
        Self.presentationTransform(at: time, worldState: worldState, configuration: configuration)
    }

    public static func presentationTransform(
        at time: TimeInterval,
        worldState: WorldState,
        configuration: VisualTransitionConfiguration = .installation
    ) -> VisualPresentationTransform {
        let motion = min(1, max(0, worldState.motion))
        let tension = min(1, max(0, worldState.tension))
        let scaleCeiling = interpolate(
            min(configuration.maximumScale, configuration.minimumScale + 0.003),
            configuration.maximumScale,
            motion
        )
        let offsetAmplitude = interpolate(configuration.minimumOffsetAmplitude, configuration.maximumOffsetAmplitude, motion)

        // A slow orbit guarantees continuous direction changes without jitter.
        // Tension only adds a bounded, lower-amplitude second harmonic.
        let period = interpolate(32, 24, motion)
        let phase = (time / period) * 2 * Double.pi
        let secondaryWeight = 0.08 * tension
        let primaryWeight = 1 - secondaryWeight
        let xWave = primaryWeight * sin(phase) + secondaryWeight * sin(phase * 1.7 + 0.8)
        let yWave = primaryWeight * cos(phase) + secondaryWeight * cos(phase * 1.7 + 0.8)
        let scaleWave = 0.5 + 0.5 * sin(phase * 0.61 + 1.2)

        return VisualPresentationTransform(
            scale: interpolate(configuration.minimumScale, scaleCeiling, scaleWave),
            offsetX: offsetAmplitude * xWave,
            offsetY: offsetAmplitude * yWave
        )
    }

    private static func smootherstep(_ value: Double) -> Double {
        let x = min(1, max(0, value))
        return x * x * x * (x * (x * 6 - 15) + 10)
    }

    private static func interpolate(_ low: Double, _ high: Double, _ amount: Double) -> Double {
        low + (high - low) * amount
    }
}
