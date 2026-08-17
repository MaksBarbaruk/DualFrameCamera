import Foundation

enum FileCaptureRepositoryError: LocalizedError, Equatable, Sendable {
    case captureAlreadyExists
    case invalidCaptureMetadata

    var errorDescription: String? {
        switch self {
        case .captureAlreadyExists:
            "A capture with this identifier already exists."
        case .invalidCaptureMetadata:
            "The saved capture metadata is invalid."
        }
    }
}

actor FileCaptureRepository: CaptureRepository {
    private enum Storage {
        static let schemaVersion = 1
        static let capturesDirectory = "Captures"
        static let stagingPrefix = ".staging-"
        static let metadataFile = "metadata.json"
        static let rearFile = "rear.heic"
        static let frontFile = "front.heic"
    }

    private struct AssetMetadata: Codable, Sendable {
        let pixelWidth: Int
        let pixelHeight: Int
        let capturedAt: Date
        let captureUptimeNanoseconds: UInt64
    }

    private struct CaptureManifest: Codable, Sendable {
        let schemaVersion: Int
        let id: UUID
        let createdAt: Date
        let rear: AssetMetadata
        let front: AssetMetadata
    }

    private let fileManager: FileManager
    private let rootDirectory: URL
    private var didPrepareStorage = false

    init(
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.rootDirectory = rootDirectory ?? fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Storage.capturesDirectory, isDirectory: true)
    }

    func captures() throws -> [CapturePair] {
        try prepareStorageIfNeeded()
        let directories = try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        return directories.compactMap { directory in
            guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            return try? loadCapture(from: directory)
        }
    }

    func capture(id: UUID) throws -> CapturePair? {
        try prepareStorageIfNeeded()
        let directory = captureDirectory(id: id)
        guard fileManager.fileExists(atPath: directory.path) else { return nil }
        return try loadCapture(from: directory)
    }

    func save(_ payload: CapturedPairPayload) throws -> CapturePair {
        try prepareStorageIfNeeded()

        let destination = captureDirectory(id: payload.id)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw FileCaptureRepositoryError.captureAlreadyExists
        }

        let stagingDirectory = rootDirectory.appendingPathComponent(
            Storage.stagingPrefix + UUID().uuidString,
            isDirectory: true
        )

        do {
            try fileManager.createDirectory(
                at: stagingDirectory,
                withIntermediateDirectories: false
            )
            try payload.rear.data.write(
                to: stagingDirectory.appendingPathComponent(Storage.rearFile),
                options: .atomic
            )
            try payload.front.data.write(
                to: stagingDirectory.appendingPathComponent(Storage.frontFile),
                options: .atomic
            )

            let manifest = CaptureManifest(
                schemaVersion: Storage.schemaVersion,
                id: payload.id,
                createdAt: payload.createdAt,
                rear: metadata(from: payload.rear),
                front: metadata(from: payload.front)
            )
            let metadata = try makeEncoder().encode(manifest)
            try metadata.write(
                to: stagingDirectory.appendingPathComponent(Storage.metadataFile),
                options: .atomic
            )

            try fileManager.moveItem(at: stagingDirectory, to: destination)
            return makeCapture(from: manifest, directory: destination)
        } catch {
            if fileManager.fileExists(atPath: stagingDirectory.path) {
                try? fileManager.removeItem(at: stagingDirectory)
            }
            throw error
        }
    }

    func delete(id: UUID) throws {
        try prepareStorageIfNeeded()
        let directory = captureDirectory(id: id)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }
}

private extension FileCaptureRepository {
    func prepareStorageIfNeeded() throws {
        guard !didPrepareStorage else { return }
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )

        let contents = try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil,
            options: []
        )
        for url in contents where url.lastPathComponent.hasPrefix(Storage.stagingPrefix) {
            try? fileManager.removeItem(at: url)
        }
        didPrepareStorage = true
    }

    func captureDirectory(id: UUID) -> URL {
        rootDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func loadCapture(from directory: URL) throws -> CapturePair {
        let data = try Data(
            contentsOf: directory.appendingPathComponent(Storage.metadataFile),
            options: [.mappedIfSafe]
        )
        let manifest = try makeDecoder().decode(CaptureManifest.self, from: data)
        guard manifest.schemaVersion == Storage.schemaVersion,
              directory.lastPathComponent == manifest.id.uuidString,
              fileManager.fileExists(
                atPath: directory.appendingPathComponent(Storage.rearFile).path
              ),
              fileManager.fileExists(
                atPath: directory.appendingPathComponent(Storage.frontFile).path
              ) else {
            throw FileCaptureRepositoryError.invalidCaptureMetadata
        }
        return makeCapture(from: manifest, directory: directory)
    }

    private func makeCapture(from manifest: CaptureManifest, directory: URL) -> CapturePair {
        CapturePair(
            id: manifest.id,
            createdAt: manifest.createdAt,
            rear: makeAsset(
                position: .rear,
                fileName: Storage.rearFile,
                metadata: manifest.rear,
                directory: directory
            ),
            front: makeAsset(
                position: .front,
                fileName: Storage.frontFile,
                metadata: manifest.front,
                directory: directory
            )
        )
    }

    private func makeAsset(
        position: CaptureAsset.Position,
        fileName: String,
        metadata: AssetMetadata,
        directory: URL
    ) -> CaptureAsset {
        CaptureAsset(
            position: position,
            fileURL: directory.appendingPathComponent(fileName),
            pixelWidth: metadata.pixelWidth,
            pixelHeight: metadata.pixelHeight,
            capturedAt: metadata.capturedAt,
            captureUptimeNanoseconds: metadata.captureUptimeNanoseconds
        )
    }

    private func metadata(from payload: CapturedImagePayload) -> AssetMetadata {
        AssetMetadata(
            pixelWidth: payload.pixelWidth,
            pixelHeight: payload.pixelHeight,
            capturedAt: payload.capturedAt,
            captureUptimeNanoseconds: payload.captureUptimeNanoseconds
        )
    }

    func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
