import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

extension SessionStore {
    func fileType(at url: URL) throws -> FileAttributeType? {
        do {
            return try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
        } catch {
            let error = error as NSError
            if error.domain == NSCocoaErrorDomain,
               [CocoaError.fileNoSuchFile.rawValue, CocoaError.fileReadNoSuchFile.rawValue].contains(error.code) {
                return nil
            }
            if error.domain == NSPOSIXErrorDomain,
               error.code == Int(POSIXErrorCode.ENOENT.rawValue) {
                return nil
            }
            throw error
        }
    }

    func isSymbolicLink(_ url: URL) throws -> Bool {
        if try fileType(at: url) == .typeSymbolicLink { return true }
        // `attributesOfItem` follows a dangling link on some Foundation platforms.
        // The link API does not, so use it as a second, fail-closed check.
        do {
            _ = try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
            return true
        } catch {
            let error = error as NSError
            if error.domain == NSCocoaErrorDomain || error.domain == NSPOSIXErrorDomain { return false }
            throw error
        }
    }

    func safeErrorDescription(_ error: Error) -> String {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain {
            return "Session file could not be read or decoded (Cocoa error \(error.code))."
        }
        return "Session file could not be decoded."
    }

    /// Commits metadata content and its local policy as one observable operation.
    /// If policy application or read-back verification fails after the atomic write,
    /// the prior bytes are restored (or a newly-created file is removed) before returning.
    func transactionallyWriteMetadata(
        _ data: Data,
        replacing previousData: Data?,
        at url: URL,
        verify: () throws -> Void
    ) throws {
        try data.write(to: url, options: [.atomic])
        do {
            try applyAndVerifyLocalArtifactPolicy(to: url)
            try verify()
            try validateStoreDirectories()
        } catch {
            let originalError = error
            do {
                try rollbackMetadataWrite(previousData: previousData, at: url)
            } catch {
                throw SessionStoreError.sessionMetadataRollbackFailed
            }
            throw originalError
        }
    }

    private func rollbackMetadataWrite(previousData: Data?, at url: URL) throws {
        try validateStoreDirectories()
        if try isSymbolicLink(url) { throw SessionStoreError.sessionMetadataIsSymbolicLink }
        try restoreMetadata(previousData: previousData, at: url)
        try validateStoreDirectories()
    }

    private func restoreMetadata(previousData: Data?, at url: URL) throws {
        if let previousData {
            try previousData.write(to: url, options: [.atomic])
            try applyAndVerifyLocalArtifactPolicy(to: url)
            guard try Data(contentsOf: url) == previousData else {
                throw SessionStoreError.sessionMetadataRollbackFailed
            }
            return
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard try fileType(at: url) == .typeRegular else {
            throw SessionStoreError.sessionMetadataRollbackFailed
        }
        try FileManager.default.removeItem(at: url)
    }

    func persistReconciledSession(
        _ session: CaptureSession,
        replacing previousData: Data,
        at url: URL
    ) throws {
        let updatedData = try encoder.encode(session)
        try transactionallyWriteMetadata(updatedData, replacing: previousData, at: url) {
            let persisted = try self.validatedPersistedSession(at: url, expectedID: session.id)
            guard persisted.recordingRelativePath == session.recordingRelativePath else {
                throw SessionStoreError.recordingFileNameMismatch
            }
        }
    }

    func validatedPersistedSession(at url: URL, expectedID: UUID) throws -> CaptureSession {
        if try isSymbolicLink(url) { throw SessionStoreError.sessionMetadataIsSymbolicLink }
        let persisted = try decoder.decode(CaptureSession.self, from: Data(contentsOf: url))
        try validateSessionOwnership(persisted, expectedID: expectedID)
        return persisted
    }

    /// Excludes local session artifacts from backups. Closed metadata and media require an
    /// unlocked device; only actively-written staging/journal files opt into the weaker
    /// `completeUnlessOpen` class so an in-progress capture can finish safely.
    func applyLocalArtifactPolicy(
        to url: URL,
        fileProtection: FileProtectionType = .complete
    ) throws {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
#if os(iOS)
        try FileManager.default.setAttributes(
            [.protectionKey: fileProtection],
            ofItemAtPath: url.path
        )
#endif
    }

    func applyAndVerifyLocalArtifactPolicy(
        to url: URL,
        fileProtection: FileProtectionType = .complete
    ) throws {
        try applyLocalArtifactPolicy(to: url, fileProtection: fileProtection)
        try verifyLocalArtifactPolicy(on: url, fileProtection: fileProtection)
        try policyVerificationHook?(url)
    }

    func verifyLocalArtifactPolicy(
        on url: URL,
        fileProtection: FileProtectionType = .complete
    ) throws {
        let values = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
#if os(macOS)
        // On non-backup volumes (including XCTest temporary directories), Foundation can
        // report `false` even though the exclusion marker was persisted. Verify that marker
        // directly so the post-write check remains deterministic on macOS.
        guard values.isExcludedFromBackup == true || hasBackupExclusionMarker(on: url) else {
            throw SessionStoreError.localArtifactPolicyMismatch
        }
#else
        guard values.isExcludedFromBackup == true else {
            throw SessionStoreError.localArtifactPolicyMismatch
        }
#endif
#if os(iOS) && !targetEnvironment(simulator)
        // Simulator applies the protection attribute but does not report it through the
        // filesystem read-back API. Physical-device builds still verify the exact class.
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.protectionKey] as? FileProtectionType
            == fileProtection
        else {
            throw SessionStoreError.localArtifactPolicyMismatch
        }
#endif
    }

#if os(macOS)
    func hasBackupExclusionMarker(on url: URL) -> Bool {
        let markerName = "com.apple.metadata:com_apple_backup_excludeItem"
        return url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return markerName.withCString { name in
                getxattr(path, name, nil, 0, 0, 0) > 0
            }
        }
    }
#endif
}
