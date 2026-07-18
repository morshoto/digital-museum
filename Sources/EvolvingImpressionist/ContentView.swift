import SwiftUI

struct ContentView: View {
    @ObservedObject var controller: InstallationController
    @State private var showDeveloperMode = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image = controller.visual.image {
                Image(nsImage: image).resizable().scaledToFill().ignoresSafeArea().transition(.opacity)
            } else {
                Canvas { context, size in
                    let gradient = Gradient(colors: [.indigo.opacity(0.8), .orange.opacity(0.6), .black])
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
                }.ignoresSafeArea()
            }
            if showDeveloperMode { DeveloperPanel(controller: controller).padding(24).frame(maxWidth: 380).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) }
        }
        .animation(.easeInOut(duration: 2), value: controller.visual.image)
        .onAppear { controller.start() }
        .onDisappear { controller.stop() }
        .onReceive(NotificationCenter.default.publisher(for: .toggleDeveloperMode)) { _ in showDeveloperMode.toggle() }
    }
}

struct DeveloperPanel: View {
    @ObservedObject var controller: InstallationController
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EVOLVING IMPRESSIONIST").font(.caption).tracking(2)
            Text("Developer mode").font(.title2.bold())
            ForEach(WorldParameter.allCases) { parameter in
                HStack { Text(parameter.title).frame(width: 100, alignment: .leading); Slider(value: Binding(get: { controller.engine.overrides[parameter] ?? controller.engine.state[parameter] }, set: { controller.engine.overrides[parameter] = $0 }), in: 0...1); Text(controller.engine.state[parameter], format: .number.precision(.fractionLength(2))).monospacedDigit().frame(width: 38) }
            }
            Text(controller.visual.lastPrompt).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            Text("D toggles this panel • F toggles fullscreen").font(.caption2).foregroundStyle(.secondary)
        }.padding(18).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.white)
    }
}

extension Notification.Name {
    static let toggleDeveloperMode = Notification.Name("toggleDeveloperMode")
    static let toggleFullscreen = Notification.Name("toggleFullscreen")
}
