import Foundation

extension SessionStore {
    private struct JournalAppendContext {
        let encoder: JSONEncoder
        let handle: FileHandle
        let invalidError: SessionStoreError
    }
    func mergedWithJournals(_ session: CaptureSession) throws -> CaptureSession {
        var merged = session
        merged.captureObservations = try mergedObservations(
            inline: session.captureObservations,
            sessionID: session.id
        )
        merged.codingSnapshots = try mergedCodingSnapshots(
            inline: session.codingSnapshots,
            sessionID: session.id
        )
        if !merged.codingSnapshots.isEmpty {
            var timeline = CodingSegmentTimeline(minSegmentSeconds: merged.codingTimeline.minSegmentSeconds)
            for snapshot in merged.codingSnapshots {
                timeline.observe(snapshot: snapshot, at: snapshot.createdAt)
            }
            merged.codingTimeline = timeline
            merged.latestCodingSnapshot = merged.codingSnapshots.last
        }
        return merged
    }

    func mergedObservations(
        inline: [CaptureObservation],
        sessionID: UUID
    ) throws -> [CaptureObservation] {
        try Self.mergedByID(inline + readObservationJournal(sessionID: sessionID), id: \.id, date: \.observedAt)
    }

    func mergedCodingSnapshots(
        inline: [ResearchCodingSnapshot],
        sessionID: UUID
    ) throws -> [ResearchCodingSnapshot] {
        try Self.mergedByID(inline + readCodingSnapshotJournal(sessionID: sessionID), id: \.id, date: \.createdAt)
    }

    /// Later entries replace earlier ones with the same ID (journal values win: they are the durable
    /// append path). Stored dates have whole-second precision, so equal dates keep file order.
    private static func mergedByID<Entry>(
        _ entries: [Entry], id: (Entry) -> UUID, date: (Entry) -> Date
    ) -> [Entry] {
        var positions: [UUID: Int] = [:]
        var merged: [Entry] = []
        for entry in entries {
            if let position = positions[id(entry)] {
                merged[position] = entry
            } else {
                positions[id(entry)] = merged.count
                merged.append(entry)
            }
        }
        return merged.enumerated().sorted {
            date($0.element) == date($1.element) ? $0.offset < $1.offset : date($0.element) < date($1.element)
        }.map(\.element)
    }

    func appendObservationsToJournal(
        _ candidates: [CaptureObservation],
        sessionID: UUID
    ) throws {
        guard !candidates.isEmpty else { return }
        try prepareRootDirectory()
        _ = try prepareObservationsDirectory()
        let url = try validatedObservationJournalURL(for: sessionID)
        if try isSymbolicLink(url) { throw SessionStoreError.observationJournalIsSymbolicLink }
        let existingIDs = try observationJournalIDs(for: sessionID)
        let unique = candidates
            .filter { !existingIDs.contains($0.id) }
            .reduce(into: [UUID: CaptureObservation]()) { partial, observation in
                partial[observation.id] = observation
            }
            .values
            .sorted {
                $0.observedAt == $1.observedAt
                    ? $0.id.uuidString < $1.id.uuidString
                    : $0.observedAt < $1.observedAt
            }
        guard !unique.isEmpty else { return }

        try appendJournalEntries(
            unique,
            to: url,
            invalidError: .observationJournalInvalid
        )
        observationIDsBySession[sessionID, default: existingIDs]
            .formUnion(unique.map(\.id))
        try validateStoreDirectories()
    }

    private func observationJournalIDs(for sessionID: UUID) throws -> Set<UUID> {
        if let cached = observationIDsBySession[sessionID] { return cached }
        let persisted = Set(try readObservationJournal(sessionID: sessionID).map(\.id))
        observationIDsBySession[sessionID] = persisted
        return persisted
    }

    func readObservationJournal(sessionID: UUID) throws -> [CaptureObservation] {
        let url = try validatedObservationJournalURL(for: sessionID)
        if try isSymbolicLink(url) { throw SessionStoreError.observationJournalIsSymbolicLink }
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try readJournalEntries(from: url, invalidError: .observationJournalInvalid)
    }

    func appendCodingSnapshotsToJournal(
        _ candidates: [ResearchCodingSnapshot],
        sessionID: UUID
    ) throws {
        guard !candidates.isEmpty else { return }
        try prepareRootDirectory()
        _ = try prepareCodingSnapshotDirectory()
        let url = try validatedCodingSnapshotJournalURL(for: sessionID)
        if try isSymbolicLink(url) { throw SessionStoreError.codingSnapshotJournalIsSymbolicLink }
        let existingIDs = try codingSnapshotJournalIDs(for: sessionID)
        let unique = candidates
            .filter { !existingIDs.contains($0.id) }
            .reduce(into: [UUID: ResearchCodingSnapshot]()) { partial, snapshot in
                partial[snapshot.id] = snapshot
            }
            .values
            .sorted {
                $0.createdAt == $1.createdAt
                    ? $0.id.uuidString < $1.id.uuidString
                    : $0.createdAt < $1.createdAt
            }
        guard !unique.isEmpty else { return }

        try appendJournalEntries(
            unique,
            to: url,
            invalidError: .codingSnapshotJournalInvalid
        )
        codingSnapshotIDsBySession[sessionID, default: existingIDs].formUnion(unique.map(\.id))
        try validateStoreDirectories()
    }

    private func codingSnapshotJournalIDs(for sessionID: UUID) throws -> Set<UUID> {
        if let cached = codingSnapshotIDsBySession[sessionID] { return cached }
        let persisted = Set(try readCodingSnapshotJournal(sessionID: sessionID).map(\.id))
        codingSnapshotIDsBySession[sessionID] = persisted
        return persisted
    }

    func readCodingSnapshotJournal(sessionID: UUID) throws -> [ResearchCodingSnapshot] {
        let url = try validatedCodingSnapshotJournalURL(for: sessionID)
        if try isSymbolicLink(url) { throw SessionStoreError.codingSnapshotJournalIsSymbolicLink }
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try readJournalEntries(from: url, invalidError: .codingSnapshotJournalInvalid)
    }

    func removeOrphanJournals(
        in directory: URL,
        existingSessionIDs: Set<UUID>,
        removedFileNames: inout [String],
        diagnostics: inout [RecordingArtifactDiagnostic]
    ) throws {
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            guard url.pathExtension == "jsonl",
                  let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                  !existingSessionIDs.contains(id)
            else { continue }
            let isSymbolicLink = try isSymbolicLink(url)
            let isRegularFile = try fileType(at: url) == .typeRegular
            if isSymbolicLink || !isRegularFile {
                diagnostics.append(.init(fileName: url.lastPathComponent, reason: .artifactIsSymbolicLink))
            } else {
                try FileManager.default.removeItem(at: url)
                removedFileNames.append(url.lastPathComponent)
            }
        }
    }

    func appendJournalEntries<Entry: Encodable>(
        _ entries: [Entry],
        to url: URL,
        invalidError: SessionStoreError
    ) throws {
        let journalEncoder = SessionCoding.journalLineEncoder()
        try createJournalIfNeeded(at: url)
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        var resultingSize = try regularFileSize(at: url)
        if resultingSize > 0 {
            try handle.seek(toOffset: UInt64(resultingSize - 1))
            if try handle.read(upToCount: 1) != Data([0x0A]) {
                // An interrupted write left a torn last line; drop it so the next line stays decodable.
                let data = try validJournalData(at: url, invalidError: invalidError)
                let kept = data.lastIndex(of: 0x0A).map { $0 - data.startIndex + 1 } ?? 0
                try handle.truncate(atOffset: UInt64(kept))
                resultingSize = Int64(kept)
            }
        }
        try handle.seekToEnd()
        for entry in entries {
            let context = JournalAppendContext(encoder: journalEncoder, handle: handle, invalidError: invalidError)
            resultingSize = try appendJournalEntry(entry, context: context, currentSize: resultingSize)
        }
        try handle.synchronize()
        try applyAndVerifyLocalArtifactPolicy(to: url, fileProtection: .completeUnlessOpen)
    }

    private func createJournalIfNeeded(at url: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try applyAndVerifyLocalArtifactPolicy(to: url, fileProtection: .completeUnlessOpen)
    }

    private func appendJournalEntry<Entry: Encodable>(_ entry: Entry, context: JournalAppendContext, currentSize: Int64) throws -> Int64 {
        var line = try context.encoder.encode(entry)
        line.append(0x0A)
        guard line.count - 1 <= Self.maximumObservationLineBytes else { throw context.invalidError }
        let resultingSize = currentSize + Int64(line.count)
        guard resultingSize <= Int64(Self.maximumObservationJournalBytes) else { throw context.invalidError }
        try context.handle.write(contentsOf: line)
        return resultingSize
    }

    func readJournalEntries<Entry: Decodable>(
        from url: URL,
        invalidError: SessionStoreError
    ) throws -> [Entry] {
        let data = try validJournalData(at: url, invalidError: invalidError)
        guard !data.isEmpty else { return [] }
        let newline = UInt8(ascii: "\n")
        let completeLineCount = completeJournalLineCount(in: data, newline: newline)
        let journalDecoder = SessionCoding.decoder()
        return try data.split(separator: newline, omittingEmptySubsequences: true)
            .prefix(completeLineCount)
            .map { try decodeJournalEntry($0, decoder: journalDecoder, invalidError: invalidError) }
    }

    private func validJournalData(at url: URL, invalidError: SessionStoreError) throws -> Data {
        guard try fileType(at: url) == .typeRegular,
              try regularFileSize(at: url) <= Int64(Self.maximumObservationJournalBytes)
        else { throw invalidError }
        return try Data(contentsOf: url)
    }

    private func completeJournalLineCount(in data: Data, newline: UInt8) -> Int {
        data.last == newline
            ? data.split(separator: newline, omittingEmptySubsequences: true).count
            : max(0, data.split(separator: newline, omittingEmptySubsequences: false).count - 1)
    }

    private func decodeJournalEntry<Entry: Decodable>(
        _ line: Data.SubSequence, decoder: JSONDecoder, invalidError: SessionStoreError
    ) throws -> Entry {
        guard line.count <= Self.maximumObservationLineBytes else { throw invalidError }
        do {
            return try decoder.decode(Entry.self, from: Data(line))
        } catch {
            throw invalidError
        }
    }

    /// Gets the length of a regular file without following it through a second path lookup.
    func regularFileSize(of handle: FileHandle) throws -> Int64 {
        #if canImport(Darwin) || canImport(Glibc)
        var status = stat()
        guard fstat(handle.fileDescriptor, &status) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard (status.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else {
            throw SessionStoreError.importedMediaSourceIsNotRegularFile
        }
        return Int64(status.st_size)
        #else
        // Foundation has no descriptor-level type query on this platform. This branch is
        // intentionally fail-closed rather than returning to a path-based copy.
        throw SessionStoreError.importedMediaSourceIsNotRegularFile
        #endif
    }

    func regularFileSize(at url: URL) throws -> Int64 {
        guard try fileType(at: url) == .typeRegular else {
            throw SessionStoreError.importedMediaSourceIsNotRegularFile
        }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize else {
            throw SessionStoreError.importedMediaSourceIsNotRegularFile
        }
        return Int64(size)
    }

    /// Streams a source descriptor to a fresh staging path without exceeding the byte count
    /// that passed capacity admission. Reading continues through EOF so growth is rejected,
    /// rather than silently truncating the imported file at the admitted boundary.
    func streamCopy(source: FileHandle, to staging: URL, admittedSize: Int64) throws {
        guard admittedSize > 0, admittedSize <= Self.maximumImportedMediaBytes else {
            throw SessionStoreError.importedMediaSourceTooLarge
        }
        guard FileManager.default.createFile(atPath: staging.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let destination = try FileHandle(forWritingTo: staging)
        defer { try? destination.close() }
        var copied: Int64 = 0
        while true {
            try Task.checkCancellation()
            let chunk = try source.read(upToCount: Self.importCopyBufferBytes) ?? Data()
            guard !chunk.isEmpty else { break }
            let chunkSize = Int64(chunk.count)
            guard chunkSize <= admittedSize - copied else {
                throw SessionStoreError.importedMediaSourceIsNotRegularFile
            }
            copied += chunkSize
            try destination.write(contentsOf: chunk)
        }
        try destination.synchronize()
    }

}
