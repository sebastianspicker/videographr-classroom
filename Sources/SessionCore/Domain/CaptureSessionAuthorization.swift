import Foundation

extension CaptureSession {
    /// Revalidates the frozen grant identities; replacement grants cannot authorize an already
    /// prepared transaction retroactively.
    public func authorizes(_ snapshot: CaptureAuthorizationSnapshot, at date: Date = Date()) -> Bool {
        let requirements = [
            hasValidSnapshotStructure(snapshot, at: date),
            hasValidResearchProtocol(snapshot, at: date)
        ]
        guard requirements.allSatisfy({ $0 }) else { return false }
        return frozenGrantsAuthorize(snapshot, at: date)
    }

    private func hasValidSnapshotStructure(_ snapshot: CaptureAuthorizationSnapshot, at date: Date) -> Bool {
        let expectedScopes = expectedCaptureAuthorizationScopes
        let checks = [
            snapshot.preparedAt <= date,
            snapshot.requiredScopes == expectedScopes,
            !snapshot.grantIDs.isEmpty,
            snapshot.grantIDs.count == Set(snapshot.grantIDs).count,
            Set(snapshot.grantIDs) == Set(snapshot.grantIDByScope.values),
            Set(snapshot.grantIDByScope.keys) == snapshot.requiredScopes,
            snapshot.effectiveExpiresAt.map({ $0 > date }) ?? true
        ]
        return checks.allSatisfy({ $0 })
    }

    private var expectedCaptureAuthorizationScopes: Set<ConsentScope> {
        var scopes: Set<ConsentScope> = [.collection, .localReflection]
        if operatingMode == .experimentalResearch { scopes.insert(.researchProcessing) }
        return scopes
    }

    private func hasValidResearchProtocol(_ snapshot: CaptureAuthorizationSnapshot, at date: Date) -> Bool {
        guard operatingMode == .experimentalResearch else {
            return snapshot.researchProtocolIdentifier == nil
        }
        guard let protocolIdentifier = snapshot.researchProtocolIdentifier else { return false }
        let checks = [
            !protocolIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            experimentalProtocol?.protocolIdentifier == protocolIdentifier,
            experimentalProtocol?.isUsable(at: date) == true
        ]
        return checks.allSatisfy({ $0 })
    }

    private func frozenGrantsAuthorize(_ snapshot: CaptureAuthorizationSnapshot, at date: Date) -> Bool {
        snapshot.requiredScopes.allSatisfy { scope in
            guard let grantID = snapshot.grantIDByScope[scope],
                  consentGrants.filter({ $0.id == grantID }).count == 1,
                  let grant = consentGrants.first(where: { $0.id == grantID })
            else { return false }
            return grant.authorizes(scope, at: date)
        }
    }

    /// Closes prepared, recording, or completion-unknown manifests that have no surviving canonical media after startup
    /// artifact reconciliation. Capture decisions are intentionally retained for auditability.
    @discardableResult
    /// `preservedTakeIDs` are takes whose interrupted staged media was kept for an operator
    /// decision; they stay `completionUnknown` instead of failing.
    public mutating func failAbandonedTakes(
        canonicalMediaAssetIDs: Set<UUID>,
        preservedTakeIDs: Set<UUID> = [],
        at date: Date = Date(),
        reason: String = "App-Neustart: vorbereiteter Take besitzt keine finalisierte Mediendatei."
    ) -> Int {
        var failedAssetIDs = Set<UUID>()
        for index in takeManifests.indices {
            guard !preservedTakeIDs.contains(takeManifests[index].id),
                  shouldFail(takeManifests[index], absentFrom: canonicalMediaAssetIDs)
            else { continue }
            failTake(at: index, reason: reason, date: date, failedAssetIDs: &failedAssetIDs)
        }
        guard !failedAssetIDs.isEmpty else { return 0 }
        removeAbandonedMedia(assetIDs: failedAssetIDs)
        closeCaptureTimeline(at: date)
        return failedAssetIDs.count
    }

    private func shouldFail(_ manifest: CaptureTakeManifest, absentFrom canonicalMediaAssetIDs: Set<UUID>) -> Bool {
        let recoverableStates: Set<CaptureTakeLifecycleState> = [.prepared, .recording, .completionUnknown]
        return recoverableStates.contains(manifest.effectiveLifecycleState)
            && !canonicalMediaAssetIDs.contains(manifest.mediaAssetID)
    }

    private mutating func failTake(at index: Int, reason: String, date: Date, failedAssetIDs: inout Set<UUID>) {
        takeManifests[index].lifecycleState = .failed
        takeManifests[index].failureReason = reason
        takeManifests[index].endedAt = date
        failedAssetIDs.insert(takeManifests[index].mediaAssetID)
    }

    private mutating func removeAbandonedMedia(assetIDs: Set<UUID>) {
        let removedPaths = Set(mediaAssets.filter { assetIDs.contains($0.id) }.map(\.relativePath))
        mediaAssets.removeAll { assetIDs.contains($0.id) }
        if let recordingRelativePath, removedPaths.contains(recordingRelativePath) {
            self.recordingRelativePath = nil
        }
    }
}
