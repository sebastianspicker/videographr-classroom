@preconcurrency import AVFoundation
import Foundation

extension SpokenAudioCheckModel {
    func cleanupFile() {
        guard let fileURL else { return }
        if isRegularNonSymlinkFile(fileURL) {
            try? FileManager.default.removeItem(at: fileURL)
        }
        self.fileURL = nil
    }

    func reserveProtectedArtifact() throws {
        let fileManager = FileManager.default
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("Videographr-SpokenCheck-\(UUID().uuidString).m4a", isDirectory: false)
        guard fileManager.createFile(atPath: url.path, contents: Data()) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [
                NSLocalizedDescriptionKey: "Temporäre Audiodatei konnte nicht angelegt werden."
            ])
        }
        do {
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: url.path
            )
        } catch {
            try? fileManager.removeItem(at: url)
            throw error
        }
        guard isRegularNonSymlinkFile(url) else {
            try? fileManager.removeItem(at: url)
            throw CocoaError(.fileWriteUnknown, userInfo: [
                NSLocalizedDescriptionKey: "Temporäre Audiodatei konnte nicht sicher angelegt werden."
            ])
        }
        fileURL = url
    }

    func isRegularNonSymlinkFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else {
            return false
        }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }

    func cleanupAbandonedFiles() {
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
        guard let candidates = try? fileManager.contentsOfDirectory(
            at: temporaryDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        ) else { return }
        for candidate in candidates
            where candidate.lastPathComponent.hasPrefix("Videographr-SpokenCheck-")
                && candidate.pathExtension == "m4a" {
            guard let values = try? candidate.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            ), values.isRegularFile == true, values.isSymbolicLink != true
            else { continue }
            try? fileManager.removeItem(at: candidate)
        }
    }

    func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
