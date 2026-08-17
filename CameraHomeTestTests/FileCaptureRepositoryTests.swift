import Foundation
import Testing
@testable import CameraHomeTest

struct FileCaptureRepositoryTests {
    @Test
    func savePublishesTwoIndependentAssetsAndMetadata() async throws {
        let testDirectory = makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDirectory) }

        let repository = FileCaptureRepository(rootDirectory: testDirectory)
        let payload = makePayload()

        let capture = try await repository.save(payload)
        let loaded = try #require(try await repository.capture(id: payload.id))
        let feed = try await repository.captures()

        #expect(capture == loaded)
        #expect(feed == [loaded])
        #expect(try Data(contentsOf: loaded.rear.fileURL) == payload.rear.data)
        #expect(try Data(contentsOf: loaded.front.fileURL) == payload.front.data)
        #expect(loaded.rear.fileURL != loaded.front.fileURL)

        let publishedFiles = try FileManager.default.contentsOfDirectory(
            at: loaded.rear.fileURL.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        )
        #expect(Set(publishedFiles.map(\.lastPathComponent)) == [
            "rear.heic",
            "front.heic",
            "metadata.json"
        ])
    }

    @Test
    func startupRemovesAbandonedStagingDirectories() async throws {
        let testDirectory = makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDirectory) }

        let orphan = testDirectory.appendingPathComponent(".staging-orphan", isDirectory: true)
        try FileManager.default.createDirectory(
            at: orphan,
            withIntermediateDirectories: true
        )
        try Data("partial".utf8).write(to: orphan.appendingPathComponent("rear.heic"))

        let repository = FileCaptureRepository(rootDirectory: testDirectory)
        let captures = try await repository.captures()

        #expect(captures.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
    }

    @Test
    func deleteRemovesTheWholePublishedPair() async throws {
        let testDirectory = makeTestDirectory()
        defer { try? FileManager.default.removeItem(at: testDirectory) }

        let repository = FileCaptureRepository(rootDirectory: testDirectory)
        let payload = makePayload()
        let capture = try await repository.save(payload)

        try await repository.delete(id: capture.id)

        #expect(try await repository.capture(id: capture.id) == nil)
        #expect(!FileManager.default.fileExists(
            atPath: capture.rear.fileURL.deletingLastPathComponent().path
        ))
    }
}

private extension FileCaptureRepositoryTests {
    func makeTestDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CameraHomeTest-\(UUID().uuidString)", isDirectory: true)
    }

    func makePayload() -> CapturedPairPayload {
        let rearDate = Date(timeIntervalSince1970: 1_700_000_000)
        let frontDate = rearDate.addingTimeInterval(1.5)
        return CapturedPairPayload(
            id: UUID(),
            createdAt: rearDate,
            rear: CapturedImagePayload(
                data: Data("rear-image".utf8),
                pixelWidth: 1_920,
                pixelHeight: 1_080,
                capturedAt: rearDate,
                captureUptimeNanoseconds: 10_000_000_000
            ),
            front: CapturedImagePayload(
                data: Data("front-image".utf8),
                pixelWidth: 1_920,
                pixelHeight: 1_080,
                capturedAt: frontDate,
                captureUptimeNanoseconds: 11_500_000_000
            )
        )
    }
}
