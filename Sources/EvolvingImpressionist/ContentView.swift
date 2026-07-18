import EvolvingImpressionistCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: InstallationController
    @State private var showDeveloperMode = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            artwork
            if showDeveloperMode {
                DeveloperPanel(
                    engine: controller.engine,
                    visual: controller.visual,
                    osc: controller.osc,
                    generateNow: controller.generateNow
                )
                .padding(24)
                .frame(maxWidth: 470)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .onAppear { controller.start() }
        .onDisappear { controller.stop() }
        .onReceive(NotificationCenter.default.publisher(for: .toggleDeveloperMode)) { _ in showDeveloperMode.toggle() }
    }

    private var artwork: some View {
        ZStack {
            Canvas { context, size in
                let gradient = Gradient(colors: [.indigo.opacity(0.8), .orange.opacity(0.6), .black])
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
            }
            if let current = controller.visual.currentImage {
                Image(nsImage: current)
                    .resizable()
                    .scaledToFill()
                    .id(controller.visual.transitionID)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: max(1.2, 5.0 - controller.engine.state.motion * 3.0)), value: controller.visual.transitionID)
        .ignoresSafeArea()
        .clipped()
    }
}

struct DeveloperPanel: View {
    @ObservedObject var engine: ParameterEngine
    @ObservedObject var visual: VisualService
    @ObservedObject var osc: OSCClient
    let generateNow: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("EVOLVING IMPRESSIONIST").font(.caption).tracking(2)
                HStack {
                    Text("Developer mode").font(.title2.bold())
                    Spacer()
                    Button(visual.isGenerating ? "Generating…" : "Generate now", action: generateNow).disabled(visual.isGenerating)
                }
                StatusRow(
                    title: "Visual",
                    status: "\(visual.status.label) · \(visual.generationSuccessCount) ok · \(visual.generationFailureCount) failed",
                    isReady: visual.status == .ready
                )
                StatusRow(title: "OSC", status: "\(osc.status.label) · \(osc.sentMessageCount) sent", isReady: osc.status == .ready)
                if let error = visual.lastError {
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
                ForEach(WorldParameter.allCases) { parameter in
                    ParameterControl(engine: engine, parameter: parameter)
                }
                if !visual.lastPrompt.isEmpty {
                    Text(visual.lastPrompt).font(.caption).foregroundStyle(.secondary).lineLimit(4)
                }
                Text("⌘D hides controls · ⌘F toggles fullscreen").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(18)
        }
        .frame(maxHeight: 760)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .foregroundStyle(.white)
    }
}

private struct StatusRow: View {
    let title: String
    let status: String
    let isReady: Bool
    var body: some View {
        HStack {
            Circle().fill(isReady ? Color.green : Color.orange).frame(width: 8, height: 8)
            Text(title).font(.caption.bold()).frame(width: 48, alignment: .leading)
            Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}

private struct ParameterControl: View {
    @ObservedObject var engine: ParameterEngine
    let parameter: WorldParameter

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(parameter.title).font(.headline)
                Spacer()
                Text(engine.state[parameter], format: .number.precision(.fractionLength(3))).monospacedDigit()
                Toggle("Override", isOn: overrideEnabled).toggleStyle(.checkbox).font(.caption)
            }
            if engine.overrides[parameter] != nil {
                Slider(value: overrideValue, in: 0...1)
            }
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                controlRow("Base", value: configuration(\.base), range: 0...1, format: "%.2f")
                controlRow("Amplitude", value: configuration(\.primaryAmplitude), range: 0...0.45, format: "%.2f")
                controlRow("Period", value: configuration(\.primaryPeriod), range: 5...1800, format: "%.0fs")
                controlRow("Phase", value: configuration(\.primaryPhase), range: 0...(2 * .pi), format: "%.2f")
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 9))
    }

    private func controlRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        GridRow {
            Text(title).font(.caption).frame(width: 64, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: format, value.wrappedValue)).font(.caption.monospacedDigit()).frame(width: 54, alignment: .trailing)
        }
    }

    private var overrideEnabled: Binding<Bool> {
        Binding(
            get: { engine.overrides[parameter] != nil },
            set: { engine.setOverride($0 ? engine.state[parameter] : nil, for: parameter) }
        )
    }

    private var overrideValue: Binding<Double> {
        Binding(
            get: { engine.overrides[parameter] ?? engine.state[parameter] },
            set: { engine.setOverride($0, for: parameter) }
        )
    }

    private func configuration(_ keyPath: WritableKeyPath<WaveConfiguration, Double>) -> Binding<Double> {
        Binding(
            get: { engine.configurations[parameter]?[keyPath: keyPath] ?? 0 },
            set: {
                guard var config = engine.configurations[parameter] else { return }
                config[keyPath: keyPath] = $0
                engine.configurations[parameter] = config
            }
        )
    }
}

extension Notification.Name {
    static let toggleDeveloperMode = Notification.Name("toggleDeveloperMode")
    static let toggleFullscreen = Notification.Name("toggleFullscreen")
}
