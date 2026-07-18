import AppKit
import Foundation

struct VisualRequest: Codable {
    let state: WorldState
    let previousSVG: String?
}

struct VisualResponse: Codable { let svg: String; let prompt: String }

@MainActor
final class VisualService: ObservableObject {
    @Published private(set) var image: NSImage?
    @Published private(set) var lastPrompt = ""
    @Published private(set) var isGenerating = false
    var endpoint = URL(string: "http://127.0.0.1:8000/generate")!
    private var previousSVG: String?

    func generate(for state: WorldState) {
        guard !isGenerating else { return }
        isGenerating = true
        let request = VisualRequest(state: state, previousSVG: previousSVG)
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try? JSONEncoder().encode(request)
        URLSession.shared.dataTask(with: urlRequest) { [weak self] data, _, _ in
            guard let data, let response = try? JSONDecoder().decode(VisualResponse.self, from: data), let imageData = response.svg.data(using: .utf8), let image = NSImage(data: imageData) else {
                Task { @MainActor in self?.isGenerating = false }
                return
            }
            Task { @MainActor in
                self?.previousSVG = response.svg
                self?.lastPrompt = response.prompt
                self?.image = image
                self?.isGenerating = false
            }
        }.resume()
    }
}
