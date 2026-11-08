import AVFoundation
import AVKit
import Foundation
import SessionCore
import SwiftUI

extension ReflectView {
    func refreshMediaAvailability() async {
        let sessionID = appStore.session.id
        let assets = appStore.session.mediaAssets
        isCheckingMedia = true
        mediaAvailability = [:]
        var resolved: [UUID: URL] = [:]
        for asset in assets {
            if let url = await appStore.resolvedMediaURL(for: asset, sessionID: sessionID) {
                resolved[asset.id] = url
            }
            guard !Task.isCancelled else { return }
        }
        guard !Task.isCancelled, appStore.session.id == sessionID else { return }
        mediaAvailability = resolved
        isCheckingMedia = false
        if !assets.contains(where: { $0.id == selectedAssetID }) {
            selectedAssetID = assets.first?.id
        }
    }

    func assetLabel(_ asset: SessionMediaAsset) -> String {
        asset.originalFileName ?? asset.relativePath
    }

    func annotationLabel(_ annotation: EvidenceAnnotation) -> String {
        if annotation.startMilliseconds == 0, annotation.endMilliseconds == 0 {
            return "Ganzes Video"
        }
        if annotation.startMilliseconds == annotation.endMilliseconds {
            return timecode(annotation.startMilliseconds)
        }
        return "\(timecode(annotation.startMilliseconds)) – \(timecode(annotation.endMilliseconds))"
    }

    func timecode(_ milliseconds: Int64) -> String {
        reflectionTimecode(milliseconds)
    }

    /// Quick links use the editor's author and note and pass the same admission as the editor.
    func addAnnotation(for prompt: ReflectionPromptID, wholeAsset: Bool) {
        guard let asset = selectedAsset else { return }
        let end = wholeAsset ? Int64(0) : playback.positionMilliseconds
        let start = wholeAsset ? Int64(0) : (rangeStartMilliseconds ?? end)
        admitAndSaveAnnotation(
            for: asset,
            prompt: prompt,
            start: .success(min(start, end)),
            end: .success(max(start, end))
        )
    }

    func populateAnnotationEditorFromPlayback() {
        guard annotationStartTimecode.isEmpty, annotationEndTimecode.isEmpty else { return }
        usePlaybackPositionForAnnotationInterval()
    }

    func usePlaybackPositionForAnnotationInterval() {
        let start = rangeStartMilliseconds ?? playback.positionMilliseconds
        let end = playback.positionMilliseconds
        annotationStartTimecode = timecode(min(start, end))
        annotationEndTimecode = timecode(max(start, end))
        annotationEditorMessage = nil
    }

    func useWholeVideoForAnnotationInterval() {
        guard selectedAsset?.durationMilliseconds != nil else {
            annotationEditorMessage = "Die Videodauer wird noch geprüft. Bitte warten Sie, bevor Sie einen Zeitbereich sichern."
            return
        }
        annotationStartTimecode = timecode(0)
        annotationEndTimecode = timecode(0)
        annotationEditorMessage = nil
    }

    func saveHumanAnnotation() {
        guard let asset = selectedAsset else {
            annotationEditorMessage = "Für diese Notiz ist kein lokales Video verfügbar."
            return
        }
        admitAndSaveAnnotation(
            for: asset,
            prompt: focusedPrompt,
            start: ReflectionAnnotationTimecode.parse(annotationStartTimecode),
            end: ReflectionAnnotationTimecode.parse(annotationEndTimecode)
        )
    }

    /// The single write path for human annotations; see `ReflectionAnnotationAdmission`.
    private func admitAndSaveAnnotation(
        for asset: SessionMediaAsset,
        prompt: ReflectionPromptID,
        start: Result<Int64, ReflectionAnnotationTimecode.ParseError>,
        end: Result<Int64, ReflectionAnnotationTimecode.ParseError>
    ) {
        let sessionID = appStore.session.id
        let assetID = asset.id
        let admission = ReflectionAnnotationAdmission.admit(ReflectionAnnotationAdmission.Request(
            prompt: prompt,
            mediaAssetID: asset.id,
            authorizesLocalReflection: appStore.session.authorizes(.localReflection),
            durationMilliseconds: asset.durationMilliseconds,
            author: annotationAuthor,
            note: appStore.session.reflection[prompt],
            start: start,
            end: end
        ))
        let values: EvidenceAnnotation.Values
        switch admission {
        case .failure(let rejection):
            annotationEditorMessage = rejection.messageDE
            if let focus = rejection.focus { annotationFocus = focus }
            return
        case .success(let admitted):
            values = admitted
        }
        appStore.edit { $0.evidenceAnnotations.append(EvidenceAnnotation(values)) }
        rangeStartMilliseconds = nil
        annotationEditorMessage = nil
        annotationFocus = nil
        isSavingAnnotation = true

        Task { @MainActor in
            let persisted = await appStore.flushPendingChanges()
            isSavingAnnotation = false
            guard appStore.session.id == sessionID, selectedAsset?.id == assetID else { return }
            if persisted, appStore.saveState == .saved {
                annotationEditorMessage = "Notiz lokal gesichert."
            } else {
                annotationEditorMessage = appStore.lastStoreError ?? "Notiz konnte nicht lokal gesichert werden."
            }
        }
    }

    func clearAnnotationEditorMessage() {
        annotationEditorMessage = nil
    }

    func reflectionIsComplete(index: ReflectionAnnotationIndex) -> Bool {
        appStore.session.reflection.isComplete
            && index.linkedPromptCount == ReflectionPromptID.allCases.count
    }

    /// Two-way binding into session-backed reflection text without copying the session.
    func binding(for prompt: ReflectionPromptID) -> Binding<String> {
        Binding(
            get: { appStore.session.reflection[prompt] },
            set: { newValue in
                appStore.edit { $0.reflection[prompt] = newValue }
                clearAnnotationEditorMessage()
            }
        )
    }
}
