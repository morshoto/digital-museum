import Foundation

public struct PaintingVisualBias: Codable, Equatable, Sendable {
    public let palette: String
    public let brush: String
    public let structure: String

    public init(palette: String, brush: String, structure: String) {
        self.palette = palette
        self.brush = brush
        self.structure = structure
    }
}

public struct PaintingReference: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let date: String
    public let resourceFilename: String
    public let sourceInstitution: String
    public let sourceURL: URL
    public let tags: [String]
    public let defaultState: WorldState
    public let visualBias: PaintingVisualBias
    public let promptBias: [String]

    public init(
        id: String,
        title: String,
        artist: String,
        date: String,
        resourceFilename: String,
        sourceInstitution: String,
        sourceURL: URL,
        tags: [String] = [],
        defaultState: WorldState = WorldState(),
        visualBias: PaintingVisualBias = .init(palette: "broken color", brush: "visible strokes", structure: "reference composition"),
        promptBias: [String] = []
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.date = date
        self.resourceFilename = resourceFilename
        self.sourceInstitution = sourceInstitution
        self.sourceURL = sourceURL
        self.tags = tags
        self.defaultState = defaultState
        self.visualBias = visualBias
        self.promptBias = promptBias
    }
}

public struct PaintingRotationConfiguration: Codable, Equatable, Sendable {
    public let minimumDwellGenerations: Int
    public let maximumDwellGenerations: Int
    public let transitionGenerations: Int
    public let stateBias: Double

    public init(
        minimumDwellGenerations: Int = 24,
        maximumDwellGenerations: Int = 96,
        transitionGenerations: Int = 6,
        stateBias: Double = 0.12
    ) {
        self.minimumDwellGenerations = minimumDwellGenerations
        self.maximumDwellGenerations = maximumDwellGenerations
        self.transitionGenerations = transitionGenerations
        self.stateBias = stateBias
    }
}

public struct PaintingCatalog: Codable, Equatable, Sendable {
    public let version: Int
    public let paintings: [PaintingReference]
    public let defaultPaintingID: PaintingReference.ID
    public let rotation: PaintingRotationConfiguration

    public init(
        paintings: [PaintingReference],
        defaultPaintingID: PaintingReference.ID,
        version: Int = 1,
        rotation: PaintingRotationConfiguration = .init()
    ) {
        self.version = version
        self.paintings = paintings
        self.defaultPaintingID = defaultPaintingID
        self.rotation = rotation
    }

    public var defaultPainting: PaintingReference? {
        paintings.first { $0.id == defaultPaintingID }
    }

    public static var bundled: PaintingCatalog { try! loadBundled() }

    public static func loadBundled() throws -> PaintingCatalog {
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json", subdirectory: "Paintings") else {
            throw OriginalImageResolutionError.missingBundledCatalog
        }
        do {
            return try JSONDecoder().decode(PaintingCatalog.self, from: Data(contentsOf: url))
        } catch {
            throw OriginalImageResolutionError.invalidBundledCatalog(error.localizedDescription)
        }
    }
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
    case missingBundledCatalog
    case invalidBundledCatalog(String)
    case missingDefaultPainting(String)
    case missingBundledResource(String)

    public var errorDescription: String? {
        switch self {
        case .invalidOverride(let path):
            "EVOLVING_ORIGINAL_IMAGE must point to a readable image file, but none exists at '\(path)'. Correct the path or unset the variable to use the bundled painting catalog."
        case .missingBundledCatalog:
            "The bundled painting catalog is missing from the SwiftPM resource bundle. Rebuild or reinstall EvolvingImpressionist."
        case .invalidBundledCatalog(let detail):
            "The bundled painting catalog could not be decoded: \(detail)"
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
        catalog: PaintingCatalog? = nil
    ) throws -> OriginalImageResolution {
        if let overridePath = environment["EVOLVING_ORIGINAL_IMAGE"] {
            return try resolveOverride(path: overridePath)
        }
        let selectedCatalog = try catalog ?? PaintingCatalog.loadBundled()
        guard let painting = selectedCatalog.defaultPainting else {
            throw OriginalImageResolutionError.missingDefaultPainting(selectedCatalog.defaultPaintingID)
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
