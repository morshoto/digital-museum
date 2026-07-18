import Foundation

public struct PaintingReference: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let date: String
    public let resourceFilename: String
    public let sourceInstitution: String
    public let sourceURL: URL

    public init(
        id: String,
        title: String,
        artist: String,
        date: String,
        resourceFilename: String,
        sourceInstitution: String,
        sourceURL: URL
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.date = date
        self.resourceFilename = resourceFilename
        self.sourceInstitution = sourceInstitution
        self.sourceURL = sourceURL
    }
}

public struct PaintingCatalog: Equatable, Sendable {
    public let paintings: [PaintingReference]
    public let defaultPaintingID: PaintingReference.ID

    public init(paintings: [PaintingReference], defaultPaintingID: PaintingReference.ID) {
        self.paintings = paintings
        self.defaultPaintingID = defaultPaintingID
    }

    public var defaultPainting: PaintingReference? {
        paintings.first { $0.id == defaultPaintingID }
    }

    public static let bundled = PaintingCatalog(
        paintings: [
            PaintingReference(
                id: "monet-water-lilies-1906",
                title: "Water Lilies",
                artist: "Claude Monet",
                date: "1906",
                resourceFilename: "monet-water-lilies.png",
                sourceInstitution: "Art Institute of Chicago",
                sourceURL: URL(string: "https://www.artic.edu/artworks/16568/water-lilies")!
            ),
            PaintingReference(
                id: "monet-water-lily-pond-1900",
                title: "Water Lily Pond",
                artist: "Claude Monet",
                date: "1900",
                resourceFilename: "monet-water-lily-pond.png",
                sourceInstitution: "Art Institute of Chicago",
                sourceURL: URL(string: "https://www.artic.edu/artworks/87088/water-lily-pond")!
            ),
            PaintingReference(
                id: "monet-stacks-of-wheat-1890",
                title: "Stacks of Wheat (End of Summer)",
                artist: "Claude Monet",
                date: "1890–91",
                resourceFilename: "monet-stacks-of-wheat.png",
                sourceInstitution: "Art Institute of Chicago",
                sourceURL: URL(string: "https://www.artic.edu/artworks/64818/stacks-of-wheat-end-of-summer")!
            ),
            PaintingReference(
                id: "monet-beach-at-sainte-adresse-1867",
                title: "The Beach at Sainte-Adresse",
                artist: "Claude Monet",
                date: "1867",
                resourceFilename: "monet-beach-at-sainte-adresse.png",
                sourceInstitution: "Art Institute of Chicago",
                sourceURL: URL(string: "https://www.artic.edu/artworks/14598/the-beach-at-sainte-adresse")!
            ),
        ],
        defaultPaintingID: "monet-water-lilies-1906"
    )
}

public enum OriginalImageSource: Equatable, Sendable {
    case environmentOverride
    case bundledPainting
}

public struct OriginalImageResolution: Equatable, Sendable {
    public let fileURL: URL
    public let source: OriginalImageSource
    public let painting: PaintingReference?

    public init(fileURL: URL, source: OriginalImageSource, painting: PaintingReference?) {
        self.fileURL = fileURL
        self.source = source
        self.painting = painting
    }
}

public enum OriginalImageResolutionError: LocalizedError, Equatable {
    case invalidOverride(String)
    case missingDefaultPainting(String)
    case missingBundledResource(String)

    public var errorDescription: String? {
        switch self {
        case .invalidOverride(let path):
            "EVOLVING_ORIGINAL_IMAGE must point to a readable image file, but none exists at '\(path)'. Correct the path or unset the variable to use the bundled Monet reference."
        case .missingDefaultPainting(let id):
            "The bundled painting catalog does not contain its configured default '\(id)'."
        case .missingBundledResource(let filename):
            "The bundled default painting '\(filename)' is missing from the SwiftPM resource bundle. Rebuild or reinstall EvolvingImpressionist."
        }
    }
}

public enum OriginalImageResolver {
    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        catalog: PaintingCatalog = .bundled
    ) throws -> OriginalImageResolution {
        if let overridePath = environment["EVOLVING_ORIGINAL_IMAGE"] {
            return try resolveOverride(path: overridePath)
        }
        guard let painting = catalog.defaultPainting else {
            throw OriginalImageResolutionError.missingDefaultPainting(catalog.defaultPaintingID)
        }
        guard let url = Bundle.module.url(
            forResource: painting.resourceFilename,
            withExtension: nil,
            subdirectory: "Paintings"
        ) else {
            throw OriginalImageResolutionError.missingBundledResource(painting.resourceFilename)
        }
        return OriginalImageResolution(fileURL: url, source: .bundledPainting, painting: painting)
    }

    private static func resolveOverride(path: String) throws -> OriginalImageResolution {
        let expandedPath = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath).standardizedFileURL
        var isDirectory = ObjCBool(false)
        guard !path.isEmpty,
              FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              FileManager.default.isReadableFile(atPath: url.path)
        else {
            throw OriginalImageResolutionError.invalidOverride(path)
        }
        return OriginalImageResolution(fileURL: url, source: .environmentOverride, painting: nil)
    }
}
