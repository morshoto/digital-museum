import AppKit
import Foundation

@MainActor
public final class VisualService: ObservableObject {
    @Published public private(set) var currentImage: NSImage?
    @Published public private(set) var previousImage: NSImage?
    @Published public private(set) var transitionID = 0
    @Published public private(set) var lastPrompt = ""
    @Published public private(set) var isGenerating = false
    @Published public private(set) var status: TransportStatus = .idle
    @Published public private(set) var lastError: String?
    @Published public private(set) var backend = "unknown"
    public private(set) var previousGenerationID: String?

    private let client: any VisualAPIProviding
    private let originalImagePath: String?

    public convenience init(
        baseURL: URL = URL(string: ProcessInfo.processInfo.environment["EVOLVING_VISUAL_URL"] ?? "http://127.0.0.1:8000")!,
        originalImagePath: String? = ProcessInfo.processInfo.environment["EVOLVING_ORIGINAL_IMAGE"]
    ) {
        self.init(client: VisualAPIClient(baseURL: baseURL), originalImagePath: originalImagePath)
    }

    public init(client: any VisualAPIProviding, originalImagePath: String?) {
        self.client = client
        self.originalImagePath = originalImagePath
    }

    public func checkHealth() async {
        status = .connecting
        do {
            let health = try await client.health()
            backend = health.backend
            status = health.ok ? .ready : .failed("Service reported unhealthy")
            lastError = nil
        } catch {
            status = .failed(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    public func generate(for state: WorldState) async {
        guard !isGenerating else { return }
        isGenerating = true
        defer { isGenerating = false }
        let reference = VisualReference(originalImagePath: originalImagePath, previousGenerationID: previousGenerationID)
        do {
            let response = try await client.generate(.init(state: state, reference: reference))
            guard let data = response.imageData, let image = NSImage(data: data) else {
                throw VisualAPIError.invalidImageData
            }
            previousImage = currentImage
            currentImage = image
            previousGenerationID = response.generationID
            lastPrompt = response.prompt
            backend = response.backend
            lastError = nil
            status = .ready
            transitionID += 1
        } catch {
            // Retain the last valid frame and retry on the controller's next cycle.
            status = .failed(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }
}
