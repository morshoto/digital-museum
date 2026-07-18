import AppKit
import Darwin
import EvolvingImpressionistCore
import Foundation

private struct VerificationFailure: Error, CustomStringConvertible {
    let description: String
}

private struct ArtisticStateVector: Decodable {
    let name: String
    let input: WorldState
    let expected: ArtisticState
}

private final class OSCCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [(String, Float)] = []
    func append(_ message: (String, Float)) { lock.lock(); messages.append(message); lock.unlock() }
    func snapshot() -> [(String, Float)] { lock.lock(); defer { lock.unlock() }; return messages }
}

private enum VisualClientStep: Sendable {
    case response(VisualGenerationResponse)
    case failure(URLError.Code)
}

private actor SequencedVisualClient: VisualAPIProviding {
    private let backend: String
    private var steps: [VisualClientStep]
    private var references: [VisualReference] = []

    init(backend: String, steps: [VisualClientStep]) {
        self.backend = backend
        self.steps = steps
    }

    func health() async throws -> VisualHealthResponse {
        VisualHealthResponse(ok: true, backend: backend)
    }

    func generate(_ request: VisualGenerationRequest) async throws -> VisualGenerationResponse {
        references.append(request.reference)
        guard !steps.isEmpty else { throw URLError(.badServerResponse) }
        switch steps.removeFirst() {
        case .response(let response): return response
        case .failure(let code): throw URLError(code)
        }
    }

    func receivedReferences() -> [VisualReference] { references }
}

@main
struct VerificationRunner {
    static func main() async {
        do {
            try verifyParameters()
            try verifyArtisticState()
            try verifyPaintingReferences()
            try await verifyOSC()
            try await verifyOSCWithoutReceiver()
            try await verifyVisualIntegration()
            print("PASS: all Swift core and integration checks passed")
        } catch {
            fputs("FAIL: \(error)\n", stderr)
            exit(1)
        }
    }

    @MainActor
    private static func verifyOSCWithoutReceiver() async throws {
        // UDP delivery must remain optional for exhibition survival. Port 9 is
        // deliberately used without opening a receiver in this process.
        let client = OSCClient(port: 9)
        for _ in 0..<40 where client.status != .ready { try await Task.sleep(nanoseconds: 25_000_000) }
        for step in 0..<20 {
            let value = Double(step) / 19
            client.send(state: .init(brightness: value, warmth: 1 - value, abstraction: value, motion: 1 - value, tension: value))
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        client.cancel()
        try require(client.sentMessageCount > 0 || client.status != .ready, "OSC sender neither sent nor reported transport state")
        print("PASS: repeated OSC sends without a receiver did not crash or block")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw VerificationFailure(description: message) }
    }

    @MainActor
    private static func verifyParameters() throws {
        let modulator = ParameterModulator()
        for time in stride(from: 0.0, through: 7200.0, by: 7.3) {
            let state = modulator.state(at: time)
            for parameter in WorldParameter.allCases {
                try require((0...1).contains(state[parameter]), "\(parameter.rawValue) escaped 0...1")
            }
        }
        try require(modulator.state(at: 0) != modulator.state(at: 41), "parameters did not change over time")

        let slow = WaveConfiguration(base: 0.5, components: [.init(amplitude: 0.2, period: 100, phase: 0)])
        let fast = WaveConfiguration(base: 0.5, components: [.init(amplitude: 0.2, period: 11, phase: 0)])
        try require(abs(slow.value(at: 17) - fast.value(at: 17)) > 0.000001, "different configurations matched")

        let zero = SineComponent(amplitude: 0.25, period: 20, phase: 0)
        let quarter = SineComponent(amplitude: 0.25, period: 20, phase: .pi / 2)
        try require(abs(zero.value(at: 0)) < 0.000001 && abs(quarter.value(at: 0) - 0.25) < 0.000001, "phase offset was ignored")

        let duplicate = ParameterModulator()
        for time in [0.0, 1.5, 93.25, 1800.0] {
            try require(modulator.state(at: time) == duplicate.state(at: time), "deterministic configurations diverged")
        }

        let engine = ParameterEngine()
        for parameter in WorldParameter.allCases {
            engine.setOverride(-0.5, for: parameter)
            try require(engine.sample(at: 123)[parameter] == 0, "\(parameter.rawValue) override was not clamped low")
            engine.setOverride(1.5, for: parameter)
            try require(engine.sample(at: 123)[parameter] == 1, "\(parameter.rawValue) override was not clamped high")
            engine.setOverride(0.8125, for: parameter)
            try require(abs(engine.sample(at: 123)[parameter] - 0.8125) < 0.000001, "\(parameter.rawValue) override was not returned")
            engine.setOverride(nil, for: parameter)
            let automatic = ParameterModulator(configurations: engine.configurations).state(at: 123)[parameter]
            try require(abs(engine.sample(at: 123)[parameter] - automatic) < 0.000001, "\(parameter.rawValue) did not return to automatic modulation")
        }
        try require(engine.overrides.isEmpty, "cleared overrides remained in the engine")

        let sampleTime = 17.0
        let beforeConfigurationEdit = engine.sample(at: sampleTime).brightness
        var edited = try requireValue(engine.configurations[.brightness], "brightness configuration was missing")
        edited.base = 0.2
        edited.primaryAmplitude = 0.3
        edited.primaryPeriod = 19
        edited.primaryPhase = 1.4
        engine.configurations[.brightness] = edited
        try require(abs(engine.sample(at: sampleTime).brightness - beforeConfigurationEdit) > 0.000001, "live modulation controls did not affect sampling")
        print("PASS: all five live parameters, modulation controls, bounded overrides, and return to automatic modulation")
    }

    private static func verifyArtisticState() throws {
        let samples = [
            WorldState(brightness: 0, warmth: 0, abstraction: 0, motion: 0, tension: 0),
            WorldState(),
            WorldState(brightness: 1, warmth: 1, abstraction: 1, motion: 1, tension: 1),
            WorldState(brightness: 0.82, warmth: 0.74, abstraction: 0.48, motion: 0.67, tension: 0.31),
        ]
        for world in samples {
            let first = world.artistic
            let second = world.artistic
            try require(first == second, "identical WorldState produced different artistic state")
            for (name, value) in [
                ("luminosity", first.luminosity), ("fluidity", first.fluidity),
                ("instability", first.instability), ("serenity", first.serenity),
                ("density", first.density),
            ] {
                try require((0...1).contains(value), "derived \(name) escaped 0...1")
            }
        }

        let baseline = WorldState(brightness: 0.5, warmth: 0.5, abstraction: 0.5, motion: 0.5, tension: 0.5)
        try require(WorldState(brightness: 1, warmth: 0.5, abstraction: 0.5, motion: 0.5, tension: 0.5).artistic.luminosity > baseline.artistic.luminosity, "brightness did not raise luminosity")
        try require(WorldState(brightness: 0.5, warmth: 0.5, abstraction: 0.5, motion: 1, tension: 0.5).artistic.fluidity > baseline.artistic.fluidity, "motion did not raise fluidity")
        let tense = WorldState(brightness: 0.5, warmth: 0.5, abstraction: 0.5, motion: 0.5, tension: 1).artistic
        try require(tense.instability > baseline.artistic.instability && tense.serenity < baseline.artistic.serenity, "tension did not raise instability and lower serenity")
        let abstract = WorldState(brightness: 0.5, warmth: 0.5, abstraction: 1, motion: 0.5, tension: 0.5).artistic
        try require(abstract.fluidity > baseline.artistic.fluidity && abstract.instability > baseline.artistic.instability && abstract.density > baseline.artistic.density, "abstraction did not affect its intended qualities")

        let sourceFile = URL(fileURLWithPath: #filePath)
        let defaultVectorsURL = sourceFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("verification/artistic_state_vectors.json")
        let vectorsURL = ProcessInfo.processInfo.environment["ARTISTIC_STATE_VECTORS"]
            .map { URL(fileURLWithPath: $0) } ?? defaultVectorsURL
        let vectors = try JSONDecoder().decode(
            [ArtisticStateVector].self,
            from: Data(contentsOf: vectorsURL)
        )
        try require(!vectors.isEmpty, "artistic-state golden vectors were empty")
        for vector in vectors {
            let actual = vector.input.artistic
            for (name, actualValue, expectedValue) in [
                ("luminosity", actual.luminosity, vector.expected.luminosity),
                ("fluidity", actual.fluidity, vector.expected.fluidity),
                ("instability", actual.instability, vector.expected.instability),
                ("serenity", actual.serenity, vector.expected.serenity),
                ("density", actual.density, vector.expected.density),
            ] {
                try require(abs(actualValue - expectedValue) < 0.000000001, "\(vector.name) \(name) drifted from the shared golden vector")
            }
        }
        print("PASS: deterministic bounded artistic state, directional relationships, and \(vectors.count) shared golden vectors")
    }

    private static func requireValue<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw VerificationFailure(description: message) }
        return value
    }

    private static func verifyPaintingReferences() throws {
        let catalog = PaintingCatalog.bundled
        try require(catalog.paintings.count == 4, "bundled painting catalog did not contain four references")
        try require(catalog.defaultPainting?.id == "monet-water-lilies-1906", "Water Lilies was not the default painting")

        let defaultResolution = try OriginalImageResolver.resolve(environment: [:])
        try require(defaultResolution.source == .bundledPainting, "unset environment did not select a bundled painting")
        try require(defaultResolution.painting == catalog.defaultPainting, "resolver selected the wrong bundled painting")
        for painting in catalog.paintings {
            let selectedCatalog = PaintingCatalog(paintings: catalog.paintings, defaultPaintingID: painting.id)
            let resolution = try OriginalImageResolver.resolve(environment: [:], catalog: selectedCatalog)
            let data = try Data(contentsOf: resolution.fileURL)
            try require(data.starts(with: [0x89, 0x50, 0x4e, 0x47]), "\(painting.resourceFilename) was not a PNG")
            try require(NSImage(data: data) != nil, "AppKit could not decode \(painting.resourceFilename)")
        }

        let override = try OriginalImageResolver.resolve(
            environment: ["EVOLVING_ORIGINAL_IMAGE": defaultResolution.fileURL.path]
        )
        try require(override.source == .environmentOverride, "valid EVOLVING_ORIGINAL_IMAGE did not override the catalog")
        try require(override.fileURL == defaultResolution.fileURL, "override path changed during resolution")
        do {
            _ = try OriginalImageResolver.resolve(environment: ["EVOLVING_ORIGINAL_IMAGE": "/definitely/missing/evolving-reference.png"])
            throw VerificationFailure(description: "missing EVOLVING_ORIGINAL_IMAGE silently fell back")
        } catch OriginalImageResolutionError.invalidOverride(let path) {
            try require(path == "/definitely/missing/evolving-reference.png", "invalid override error omitted the actionable path")
        }
        print("PASS: four decodable bundled PNG references, Water Lilies default, environment override, and invalid-override rejection")
    }

    @MainActor
    private static func verifyOSC() async throws {
        let socketFD = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketFD >= 0 else { throw VerificationFailure(description: "could not create UDP receiver") }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(socketFD)
            throw VerificationFailure(description: "could not bind UDP receiver")
        }
        var boundAddress = sockaddr_in()
        var boundLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(socketFD, $0, &boundLength)
            }
        }
        guard nameResult == 0 else {
            close(socketFD)
            throw VerificationFailure(description: "could not inspect UDP receiver port")
        }
        let port = UInt16(bigEndian: boundAddress.sin_port)
        let collector = OSCCollector()
        DispatchQueue.global().async {
            for _ in 0..<5 {
                var buffer = [UInt8](repeating: 0, count: 256)
                let count = recv(socketFD, &buffer, buffer.count, 0)
                if count > 0, let decoded = OSCMessageCodec.decode(Data(buffer.prefix(count))) {
                    collector.append(decoded)
                }
            }
        }
        let client = OSCClient(port: port)
        for _ in 0..<40 where client.status != .ready { try await Task.sleep(nanoseconds: 25_000_000) }
        try require(client.status == .ready, "OSC sender did not become ready")
        client.send(state: .init(brightness: 0.1, warmth: 0.2, abstraction: 0.3, motion: 0.4, tension: 0.5))
        for _ in 0..<60 where collector.snapshot().count < 5 { try await Task.sleep(nanoseconds: 50_000_000) }
        client.cancel(); close(socketFD)

        let messages = collector.snapshot()
        try require(messages.count == 5, "OSC receiver got \(messages.count) of 5 messages")
        let expected = Set(WorldParameter.allCases.map { "/\($0.rawValue)" })
        try require(Set(messages.map(\.0)) == expected, "OSC addresses did not match the five parameters")
        try require(messages.allSatisfy { (0...1).contains($0.1) }, "OSC value escaped 0...1")
        print("PASS: OSC UDP receiver captured all five normalized messages")
    }

    private static func verifyVisualIntegration() async throws {
        guard let rawURL = ProcessInfo.processInfo.environment["VISUAL_SERVICE_URL"], let url = URL(string: rawURL) else {
            throw VerificationFailure(description: "VISUAL_SERVICE_URL must point to the running visual service")
        }
        let environment = ProcessInfo.processInfo.environment
        let expectedBackend = environment["EXPECTED_VISUAL_BACKEND"] ?? "mock"
        let originalImagePath = try OriginalImageResolver.resolve(environment: environment).fileURL.path
        let client = VisualAPIClient(baseURL: url)
        let health = try await client.health()
        try require(health.ok && health.backend == expectedBackend, "\(expectedBackend) health response was invalid")
        do {
            _ = try await client.generate(.init(
                state: .init(brightness: 0.3, warmth: 1.2, abstraction: 0.2, motion: 0.5, tension: 0.1),
                reference: .init(originalImagePath: originalImagePath)
            ))
            throw VerificationFailure(description: "invalid WorldState unexpectedly succeeded")
        } catch VisualAPIError.httpStatus(let status, let detail) {
            try require(status == 400, "invalid WorldState returned HTTP \(status), expected 400")
            try require(detail.contains("warmth must be within 0...1"), "Swift omitted the server validation message")
            try require(detail.contains("Response body:"), "Swift omitted the non-2xx response body from diagnostics")
        }
        let first = try await client.generate(.init(
            state: .init(brightness: 0.3, warmth: 0.4, abstraction: 0.2, motion: 0.5, tension: 0.1),
            reference: .init(originalImagePath: originalImagePath)
        ))
        let second = try await client.generate(.init(
            state: .init(brightness: 0.8, warmth: 0.7, abstraction: 0.6, motion: 0.9, tension: 0.5),
            reference: .init(originalImagePath: originalImagePath, previousGenerationID: first.generationID)
        ))
        try require(
            first.referenceUsage == VisualReferenceUsage(originalImage: true, previousImage: false),
            "first generation reference usage did not match the request"
        )
        try require(
            second.referenceUsage == VisualReferenceUsage(originalImage: true, previousImage: true),
            "second generation did not resolve its predecessor and original as requested"
        )
        guard let firstData = first.imageData, let secondData = second.imageData else {
            throw VerificationFailure(description: "visual response did not contain base64 image data")
        }
        try require(NSImage(data: firstData) != nil && NSImage(data: secondData) != nil, "AppKit could not decode generated images")
        try require(firstData != secondData, "successive visual generations were identical")
        if expectedBackend == "diffusers" {
            try require(first.mediaType == "image/png" && second.mediaType == "image/png", "real backend did not return PNG media types")
            try require(firstData.starts(with: [0x89, 0x50, 0x4e, 0x47]) && secondData.starts(with: [0x89, 0x50, 0x4e, 0x47]), "real backend responses were not PNG rasters")
            do {
                _ = try await client.generate(.init(
                    state: WorldState(),
                    reference: .init(originalImagePath: "/etc/hosts", previousGenerationID: second.generationID)
                ))
                throw VerificationFailure(description: "invalid raster reference unexpectedly succeeded")
            } catch VisualAPIError.httpStatus(let status, _) {
                try require(status == 400, "invalid raster reference returned HTTP \(status), expected 400")
            }
            let afterFailureHealth = try await client.health()
            try require(afterFailureHealth.ok && afterFailureHealth.backend == "diffusers", "real backend crashed after a controlled generation failure")
        }
        try await verifyVisualServiceTransitions(first: first, second: second)
        print("PASS: two Swift → HTTP → \(expectedBackend) image → AppKit decode cycles plus retained frames across network/undecodable failures and recovery")
    }

    @MainActor
    private static func verifyVisualServiceTransitions(
        first: VisualGenerationResponse,
        second: VisualGenerationResponse
    ) async throws {
        let recovered = VisualGenerationResponse(
            imageBase64: first.imageBase64,
            mediaType: first.mediaType,
            generationID: "recovered-\(first.generationID)",
            prompt: first.prompt,
            backend: first.backend
        )
        let undecodable = VisualGenerationResponse(
            imageBase64: Data("not an image".utf8).base64EncodedString(),
            mediaType: first.mediaType,
            generationID: "undecodable-\(first.generationID)",
            prompt: first.prompt,
            backend: first.backend
        )
        let client = SequencedVisualClient(backend: first.backend, steps: [
            .response(first),
            .response(second),
            .failure(.cannotConnectToHost),
            .response(undecodable),
            .failure(.networkConnectionLost),
            .response(recovered),
        ])
        let visual = VisualService(
            client: client,
            originalImagePath: nil
        )

        await visual.generate(for: WorldState())
        guard let firstImage = visual.currentImage else {
            throw VerificationFailure(description: "VisualService did not accept the valid initial frame")
        }
        try require(visual.previousImage == nil && visual.transitionID == 1, "initial valid frame produced an invalid transition state")

        await visual.generate(for: WorldState())
        guard let secondImage = visual.currentImage else {
            throw VerificationFailure(description: "VisualService did not accept the second valid frame")
        }
        try require(visual.previousImage === firstImage, "second valid frame did not retain the outgoing image")
        try require(secondImage !== firstImage && visual.transitionID == 2, "second valid frame did not advance exactly one transition")

        for expectedFailures in 1...3 {
            await visual.generate(for: WorldState())
            try require(visual.currentImage === secondImage, "VisualService replaced the valid image after request failure \(expectedFailures)")
            try require(visual.previousImage === firstImage, "VisualService cleared the outgoing image after request failure \(expectedFailures)")
            try require(visual.previousGenerationID == second.generationID, "VisualService replaced the generation ID after request failure \(expectedFailures)")
            try require(visual.transitionID == 2, "VisualService advanced its transition after request failure \(expectedFailures)")
            try require(!visual.isGenerating, "VisualService remained stalled after request failure \(expectedFailures)")
        }

        await visual.generate(for: WorldState())
        try require(visual.previousImage === secondImage, "recovery did not retain the last valid frame for crossfade")
        try require(visual.currentImage !== secondImage, "recovery did not install a replacement image")
        try require(visual.previousGenerationID == recovered.generationID && visual.transitionID == 3, "recovery did not advance exactly one transition")
        try require(visual.generationSuccessCount == 3 && visual.generationFailureCount == 3, "generation counters did not reflect network and undecodable-response failures")
        try require(visual.status == .ready && visual.lastError == nil && !visual.isGenerating, "successful recovery did not clear the failed/stalled state")

        let references = await client.receivedReferences()
        try require(references.map(\.previousGenerationID) == [nil, first.generationID, second.generationID, second.generationID, second.generationID, second.generationID], "failed attempts corrupted the previous-generation reference")
    }
}
