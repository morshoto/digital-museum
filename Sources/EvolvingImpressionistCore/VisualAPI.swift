import Foundation

public struct VisualReference: Codable, Equatable, Sendable {
    public let originalImagePath: String?
    public let previousGenerationID: String?

    public init(originalImagePath: String? = nil, previousGenerationID: String? = nil) {
        self.originalImagePath = originalImagePath
        self.previousGenerationID = previousGenerationID
    }
}

public struct VisualGenerationRequest: Codable, Equatable, Sendable {
    public let state: WorldState
    public let reference: VisualReference

    public init(state: WorldState, reference: VisualReference) {
        self.state = state
        self.reference = reference
    }
}

public struct VisualGenerationResponse: Codable, Equatable, Sendable {
    public let imageBase64: String
    public let mediaType: String
    public let generationID: String
    public let prompt: String
    public let backend: String
    public let referenceUsage: VisualReferenceUsage?

    public init(
        imageBase64: String,
        mediaType: String,
        generationID: String,
        prompt: String,
        backend: String,
        referenceUsage: VisualReferenceUsage? = nil
    ) {
        self.imageBase64 = imageBase64
        self.mediaType = mediaType
        self.generationID = generationID
        self.prompt = prompt
        self.backend = backend
        self.referenceUsage = referenceUsage
    }

    public var imageData: Data? { Data(base64Encoded: imageBase64) }
}

public struct VisualReferenceUsage: Codable, Equatable, Sendable {
    public let originalImage: Bool
    public let previousImage: Bool

    public init(originalImage: Bool, previousImage: Bool) {
        self.originalImage = originalImage
        self.previousImage = previousImage
    }
}

public struct VisualHealthResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let backend: String

    public init(ok: Bool, backend: String) {
        self.ok = ok
        self.backend = backend
    }
}

public protocol VisualAPIProviding: Sendable {
    func health() async throws -> VisualHealthResponse
    func generate(_ request: VisualGenerationRequest) async throws -> VisualGenerationResponse
}

public enum VisualAPIError: LocalizedError {
    case invalidResponse
    case httpStatus(Int, String)
    case invalidImageData

    public var errorDescription: String? {
        switch self {
        case .invalidResponse: "The visual service returned an invalid response."
        case .httpStatus(let status, let message): "Visual service HTTP \(status): \(message)"
        case .invalidImageData: "The visual service returned invalid image data."
        }
    }
}

public final class VisualAPIClient: VisualAPIProviding, @unchecked Sendable {
    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = URL(string: "http://127.0.0.1:8000")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func health() async throws -> VisualHealthResponse {
        let (data, response) = try await session.data(from: baseURL.appendingPathComponent("health"))
        try Self.validate(response: response, data: data)
        return try JSONDecoder().decode(VisualHealthResponse.self, from: data)
    }

    public func generate(_ request: VisualGenerationRequest) async throws -> VisualGenerationResponse {
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("generate"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 180
        urlRequest.httpBody = try JSONEncoder().encode(request)
        let (data, response) = try await session.data(for: urlRequest)
        try Self.validate(response: response, data: data)
        let generation = try JSONDecoder().decode(VisualGenerationResponse.self, from: data)
        guard generation.imageData?.isEmpty == false else { throw VisualAPIError.invalidImageData }
        return generation
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw VisualAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown error"
            throw VisualAPIError.httpStatus(http.statusCode, body)
        }
    }
}
