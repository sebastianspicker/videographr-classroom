import AVFoundation
import CryptoKit
import Foundation
import SessionCore

actor MediaInspector {
    struct Metadata: Sendable {
        var durationMilliseconds: Int64
        var sha256: String
        var codec: String?
        var resolution: String?
        var frameRate: Double?
    }

    func inspect(url: URL) async throws -> Metadata {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let durationMilliseconds = MediaMetadataNormalizer.durationMilliseconds(
            fromSeconds: duration.seconds
        ), let videoTrack = tracks.first else {
            throw corruptMedia("Die ausgewählte Datei enthält keinen endlichen, abspielbaren Videotrack.")
        }
        let size = try await videoTrack.load(.naturalSize)
        let frameRate = try await videoTrack.load(.nominalFrameRate)
        let formats = try await videoTrack.load(.formatDescriptions)
        guard let width = MediaMetadataNormalizer.pixelDimension(from: Double(size.width)),
              let height = MediaMetadataNormalizer.pixelDimension(from: Double(size.height)),
              !formats.isEmpty
        else {
            throw corruptMedia("Der Videotrack enthält keine gültigen Bild- oder Formatdaten.")
        }
        return Metadata(
            durationMilliseconds: durationMilliseconds,
            sha256: try Self.sha256(of: url),
            codec: formats.first.map { Self.fourCC(CMFormatDescriptionGetMediaSubType($0)) },
            resolution: "\(width)×\(height)",
            frameRate: frameRate.isFinite && frameRate > 0 ? Double(frameRate) : nil
        )
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var hasMore = true
        while hasMore {
            hasMore = try autoreleasepool {
                guard let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty else { return false }
                hasher.update(data: chunk)
                return true
            }
        }
        return SessionCoding.hex(hasher.finalize())
    }

    private static func fourCC(_ value: FourCharCode) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: value >> $0) }
        return String(bytes: bytes, encoding: .ascii) ?? String(value)
    }
}

private func corruptMedia(_ message: String) -> CocoaError {
    CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedDescriptionKey: message])
}
