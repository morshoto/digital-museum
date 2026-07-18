import AppKit
import Foundation

public struct VisualFrame {
    public let currentImage: NSImage?
    public let previousImage: NSImage?
    public let transitionID: Int

    public init(currentImage: NSImage? = nil, previousImage: NSImage? = nil, transitionID: Int = 0) {
        self.currentImage = currentImage
        self.previousImage = previousImage
        self.transitionID = transitionID
    }
}

@MainActor
public final class VisualService: ObservableObject {
    @Published public private(set) var frame = VisualFrame()
    @Published public private(set) var lastPrompt = ""
    @Published public private(set) var isGenerating = false
    @Published public private(set) var status: TransportStatus = .idle
    @Published public private(set) var lastError: String?
    @Published public private(set) var backend = "unknown"
    @Published public private(set) var generationSuccessCount = 0
    @Published public private(set) var generationFailureCount = 0
    public private(set) var previousGenerationID: String?

    private let client: any VisualAPIProviding
    private let originalImagePath: String?
    private let referenceConfigurationError: String?

    public var currentImage: NSImage? { frame.currentImage }
    public var previousImage: NSImage? { frame.previousImage }
    public var transitionID: Int { frame.transitionID }

    public convenience init(
        baseURL: URL = URL(string: ProcessInfo.processInfo.environment["EVOLVING_VISUAL_URL"] ?? "http://127.0.0.1:8000")!
    ) {
        do {
            let resolution = try OriginalImageResolver.resolve()
            self.init(client: VisualAPIClient(baseURL: baseURL), originalImagePath: resolution.fileURL.path)
        } catch {
            self.init(
                client: VisualAPIClient(baseURL: baseURL),
                originalImagePath: nil,
                referenceConfigurationError: error.localizedDescription
            )
        }
    }

    public init(
        client: any VisualAPIProviding,
        originalImagePath: String?,
        referenceConfigurationError: String? = nil
    ) {
        self.client = client
        self.originalImagePath = originalImagePath
        self.referenceConfigurationError = referenceConfigurationError
        if let referenceConfigurationError {
            status = .failed(referenceConfigurationError)
            lastError = referenceConfigurationError
        }
    }

    public func checkHealth() async {
        status = .connecting
        do {
            let health = try await client.health()
            backend = health.backend
            if let referenceConfigurationError {
                status = .failed(referenceConfigurationError)
                lastError = referenceConfigurationError
            } else {
                status = health.ok ? .ready : .failed("Service reported unhealthy")
                lastError = nil
            }
        } catch {
            status = .failed(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    public func generate(for state: WorldState) async {
        guard !isGenerating else { return }
        if let referenceConfigurationError {
            status = .failed(referenceConfigurationError)
            lastError = referenceConfigurationError
            generationFailureCount += 1
            return
        }
        isGenerating = true
        defer { isGenerating = false }
        let reference = VisualReference(originalImagePath: originalImagePath, previousGenerationID: previousGenerationID)
        do {
            let response = try await client.generate(.init(state: state, reference: reference))
            guard let data = response.imageData, let image = NSImage(data: data) else {
                throw VisualAPIError.invalidImageData
            }
            let nextFrame = VisualFrame(
                currentImage: image,
                previousImage: frame.currentImage,
                transitionID: frame.transitionID + 1
            )
            previousGenerationID = response.generationID
            lastPrompt = response.prompt
            backend = response.backend
            lastError = nil
            status = .ready
            generationSuccessCount += 1
            // Publish image data and identity together so SwiftUI cannot render
            // a new image using the outgoing frame's transition identity.
            frame = nextFrame
        } catch {
            // Retain the last valid frame and retry on the controller's next cycle.
            status = .failed(error.localizedDescription)
            lastError = error.localizedDescription
            generationFailureCount += 1
        }
    }
}
