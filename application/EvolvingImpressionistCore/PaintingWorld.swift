import AppKit
import Foundation

public struct PaintingWorldSnapshot: Equatable, Sendable {
    public let revision: Int
    public let currentIndex: Int
    public let nextIndex: Int?
    public let anchorProgress: Double
    public let generationInWorld: Int
    public let dwellGenerations: Int
}

public struct PaintingWorldTimeline: Sendable {
    public let catalog: PaintingCatalog
    public private(set) var currentIndex: Int
    public private(set) var generationInWorld = 0
    public private(set) var completedWorlds = 0
    public private(set) var revision = 0
    public private(set) var dwellGenerations: Int

    public init(catalog: PaintingCatalog, startingPaintingID: String? = nil) {
        self.catalog = catalog
        self.currentIndex = catalog.paintings.firstIndex {
            $0.id == (startingPaintingID ?? catalog.defaultPaintingID)
        } ?? 0
        self.dwellGenerations = Self.dwellLength(
            for: catalog.paintings[self.currentIndex].id,
            completedWorlds: 0,
            configuration: catalog.rotation
        )
    }

    public func prepare() -> PaintingWorldSnapshot {
        let transitionStep = max(0, generationInWorld - dwellGenerations + 1)
        let transitioning = transitionStep > 0
        let nextIndex = transitioning ? selectedNextIndex() : nil
        let linearProgress = transitioning
            ? min(1, Double(transitionStep) / Double(max(1, catalog.rotation.transitionGenerations)))
            : 0
        return PaintingWorldSnapshot(
            revision: revision,
            currentIndex: currentIndex,
            nextIndex: nextIndex,
            anchorProgress: Self.smootherstep(linearProgress),
            generationInWorld: generationInWorld,
            dwellGenerations: dwellGenerations
        )
    }

    public mutating func commit(_ snapshot: PaintingWorldSnapshot) {
        guard snapshot.revision == revision, snapshot.currentIndex == currentIndex else { return }
        generationInWorld += 1
        revision += 1
        let transitionCount = max(1, catalog.rotation.transitionGenerations)
        guard generationInWorld >= dwellGenerations + transitionCount else { return }
        currentIndex = selectedNextIndex()
        generationInWorld = 0
        completedWorlds += 1
        dwellGenerations = Self.dwellLength(
            for: catalog.paintings[currentIndex].id,
            completedWorlds: completedWorlds,
            configuration: catalog.rotation
        )
    }

    private func selectedNextIndex() -> Int {
        guard catalog.paintings.count > 1 else { return currentIndex }
        let artist = catalog.paintings[currentIndex].artist
        for distance in 1..<catalog.paintings.count {
            let candidate = (currentIndex + distance) % catalog.paintings.count
            if catalog.paintings[candidate].artist != artist { return candidate }
        }
        return (currentIndex + 1) % catalog.paintings.count
    }

    private static func dwellLength(
        for paintingID: String,
        completedWorlds: Int,
        configuration: PaintingRotationConfiguration
    ) -> Int {
        let low = max(1, configuration.minimumDwellGenerations)
        let high = max(low, configuration.maximumDwellGenerations)
        guard high > low else { return low }
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in "\(paintingID):\(completedWorlds)".utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return low + Int(hash % UInt64(high - low + 1))
    }

    private static func smootherstep(_ value: Double) -> Double {
        let x = min(1, max(0, value))
        return x * x * x * (x * (x * 6 - 15) + 10)
    }
}

public struct PreparedPaintingAnchor: Sendable {
    public let snapshot: PaintingWorldSnapshot
    public let fileURL: URL
}

@MainActor
public final class PaintingWorldController {
    public private(set) var timeline: PaintingWorldTimeline
    private let outputSize: NSSize
    private let outputDirectory: URL

    public init(
        catalog: PaintingCatalog,
        outputSize: NSSize = NSSize(width: 1024, height: 576),
        outputDirectory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("evolving-impressionist-anchors", isDirectory: true)
    ) {
        self.timeline = PaintingWorldTimeline(catalog: catalog)
        self.outputSize = outputSize
        self.outputDirectory = outputDirectory
    }

    public func prepare() throws -> PreparedPaintingAnchor {
        let snapshot = timeline.prepare()
        let currentURL = try resourceURL(at: snapshot.currentIndex)
        guard let nextIndex = snapshot.nextIndex else {
            return PreparedPaintingAnchor(snapshot: snapshot, fileURL: currentURL)
        }
        if snapshot.anchorProgress >= 0.999_999 {
            return PreparedPaintingAnchor(snapshot: snapshot, fileURL: try resourceURL(at: nextIndex))
        }

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try copyCatalogBesideBridgeAnchors()
        let progress = Int((snapshot.anchorProgress * 1_000).rounded())
        let filename = "world-anchor__\(snapshot.currentIndex)__\(nextIndex)__\(progress).png"
        let outputURL = outputDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            return PreparedPaintingAnchor(snapshot: snapshot, fileURL: outputURL)
        }

        let current = try decodedImage(at: currentURL)
        let next = try decodedImage(at: resourceURL(at: nextIndex))
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(outputSize.width),
            pixelsHigh: Int(outputSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw OriginalImageResolutionError.invalidBundledCatalog("could not allocate an anchor raster")
        }
        representation.size = outputSize
        guard let context = NSGraphicsContext(bitmapImageRep: representation) else {
            throw OriginalImageResolutionError.invalidBundledCatalog("could not create an anchor drawing context")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.black.setFill()
        NSRect(origin: .zero, size: outputSize).fill()
        drawAspectFill(current, fraction: 1)
        drawAspectFill(next, fraction: snapshot.anchorProgress)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw OriginalImageResolutionError.invalidBundledCatalog("could not encode an anchor raster")
        }
        try data.write(to: outputURL, options: .atomic)
        return PreparedPaintingAnchor(snapshot: snapshot, fileURL: outputURL)
    }

    public func commit(_ prepared: PreparedPaintingAnchor) {
        timeline.commit(prepared.snapshot)
    }

    private func resourceURL(at index: Int) throws -> URL {
        let painting = timeline.catalog.paintings[index]
        guard let url = Bundle.module.url(
            forResource: painting.resourceFilename,
            withExtension: nil,
            subdirectory: "Paintings"
        ) else {
            throw OriginalImageResolutionError.missingBundledResource(painting.resourceFilename)
        }
        return url
    }

    private func copyCatalogBesideBridgeAnchors() throws {
        guard let source = Bundle.module.url(
            forResource: "catalog",
            withExtension: "json",
            subdirectory: "Paintings"
        ) else {
            throw OriginalImageResolutionError.missingBundledCatalog
        }
        try Data(contentsOf: source).write(
            to: outputDirectory.appendingPathComponent("catalog.json"),
            options: .atomic
        )
    }

    private func decodedImage(at url: URL) throws -> NSImage {
        guard let image = NSImage(contentsOf: url) else {
            throw OriginalImageResolutionError.missingBundledResource(url.lastPathComponent)
        }
        return image
    }

    private func drawAspectFill(_ image: NSImage, fraction: Double) {
        let sourceRatio = image.size.width / image.size.height
        let targetRatio = outputSize.width / outputSize.height
        let drawSize = sourceRatio > targetRatio
            ? NSSize(width: outputSize.height * sourceRatio, height: outputSize.height)
            : NSSize(width: outputSize.width, height: outputSize.width / sourceRatio)
        let rect = NSRect(
            x: (outputSize.width - drawSize.width) / 2,
            y: (outputSize.height - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: fraction)
    }
}
