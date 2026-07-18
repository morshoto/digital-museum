import AppKit
import Darwin
import EvolvingImpressionistCore
import Foundation

private struct VerificationFailure: Error, CustomStringConvertible {
    let description: String
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

    private static func requireValue<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw VerificationFailure(description: message) }
        return value
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
        let originalImagePath = environment["EVOLVING_ORIGINAL_IMAGE"]
        let client = VisualAPIClient(baseURL: url)
        let health = try await client.health()
        try require(health.ok && health.backend == expectedBackend, "\(expectedBackend) health response was invalid")
        let first = try await client.generate(.init(
            state: .init(brightness: 0.3, warmth: 0.4, abstraction: 0.2, motion: 0.5, tension: 0.1),
            reference: .init(originalImagePath: originalImagePath)
        ))
        let second = try await client.generate(.init(
            state: .init(brightness: 0.8, warmth: 0.7, abstraction: 0.6, motion: 0.9, tension: 0.5),
            reference: .init(originalImagePath: originalImagePath, previousGenerationID: first.generationID)
        ))
        try require(
            first.referenceUsage == VisualReferenceUsage(originalImage: originalImagePath != nil, previousImage: false),
            "first generation reference usage did not match the request"
        )
        try require(
            second.referenceUsage == VisualReferenceUsage(originalImage: originalImagePath != nil, previousImage: true),
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
        print("PASS: two Swift → HTTP → \(expectedBackend) image → AppKit decode cycles plus repeated retained-frame transitions and recovery")
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
        let client = SequencedVisualClient(backend: first.backend, steps: [
            .response(first),
            .response(second),
            .failure(.cannotConnectToHost),
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

        for expectedFailures in 1...2 {
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
        try require(visual.generationSuccessCount == 3 && visual.generationFailureCount == 2, "generation counters did not reflect repeated success/failure")
        try require(visual.status == .ready && visual.lastError == nil && !visual.isGenerating, "successful recovery did not clear the failed/stalled state")

        let references = await client.receivedReferences()
        try require(references.map(\.previousGenerationID) == [nil, first.generationID, second.generationID, second.generationID, second.generationID], "failed attempts corrupted the previous-generation reference")
    }
}
