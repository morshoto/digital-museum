import AppKit
import EvolvingImpressionistCore
import Foundation

@MainActor
final class VisualService: ObservableObject {
    @Published private(set) var currentImage: NSImage?
    @Published private(set) var previousImage: NSImage?
    @Published private(set) var transitionID = 0
    @Published private(set) var lastPrompt = ""
    @Published private(set) var isGenerating = false
    @Published private(set) var status: TransportStatus = .idle
    @Published private(set) var lastError: String?
    @Published private(set) var backend = "unknown"
    @Published private(set) var generationSuccessCount = 0
    @Published private(set) var generationFailureCount = 0

    private var client: VisualAPIClient
    private var previousGenerationID: String?
    private let originalImagePath: String?

    init(
        baseURL: URL = URL(string: ProcessInfo.processInfo.environment["EVOLVING_VISUAL_URL"] ?? "http://127.0.0.1:8000")!,
        originalImagePath: String? = ProcessInfo.processInfo.environment["EVOLVING_ORIGINAL_IMAGE"]
    ) {
        self.client = VisualAPIClient(baseURL: baseURL)
        self.originalImagePath = originalImagePath
    }

    func checkHealth() async {
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

    func generate(for state: WorldState) async {
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
            generationSuccessCount += 1
            transitionID += 1
        } catch {
            // Retain the last valid frame and retry on the controller's next cycle.
            status = .failed(error.localizedDescription)
            lastError = error.localizedDescription
            generationFailureCount += 1
        }
    }
}
