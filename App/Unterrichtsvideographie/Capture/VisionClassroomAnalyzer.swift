import Foundation
import QuartzCore
import Vision
import CoreVideo
import ExperimentalResearch
import GuidanceEngine
import SessionCore

/// On-device Vision adapter. It only publishes measured structure; unsuccessful analysis is
/// explicitly marked rather than inferred from a previous frame.
final class VisionClassroomAnalyzer {
    struct Analysis {
        var features: CVFeatures
        var wasRefreshed: Bool
    }

    private var lastRun: CFTimeInterval = 0
    private var minInterval: CFTimeInterval = 0.55
    /// A callback normally refreshes well before this bound; exceeding it makes cached CV
    /// explicitly unavailable instead of presenting an old observation as current.
    private let maximumCachedAge: CFTimeInterval = 1.0
    private var lastCompletedRun: CFTimeInterval?
    private var lastFeatures = CVFeatures.empty
    private var smoother = CVObservationSmoother(alpha: 0.35)
    private let requests = VisionRequests()
    var teachingSituation: TeachingSituationID = .frontalBoardInstruction

    func configure(for situation: TeachingSituationID) {
        teachingSituation = situation
        minInterval = visionCadence(for: TeachingSituationCatalogue.preset(for: situation))
    }

    func analyze(pixelBuffer: CVPixelBuffer) -> Analysis {
        let now = CACurrentMediaTime()
        guard shouldAnalyze(at: now) else {
            let withinBound = lastCompletedRun.map { now - $0 <= maximumCachedAge } ?? false
            return Analysis(features: withinBound ? lastFeatures : .empty, wasRefreshed: false)
        }
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        guard let coverage = performRequests(requests, with: handler) else {
            let failed = failedFeatures()
            lastCompletedRun = now
            return Analysis(features: failed, wasRefreshed: true)
        }

        let board = BoardObservation(requests: requests, coverage: coverage)
        let people = PeopleObservation(requests: requests, requestCoverage: coverage)
        let layout = people.layout()
        let saliency = coverage.includesSaliencyAndPose ? requests.saliency.results?.first : nil
        let raw = makeFeatures(board: board, people: people, layout: layout, saliency: saliency)
        let features = smoother.push(raw)
        lastFeatures = features
        lastCompletedRun = now
        return Analysis(features: features, wasRefreshed: true)
    }

    func resetTemporalState() {
        smoother = CVObservationSmoother(alpha: 0.35)
        lastFeatures = .empty
        lastRun = 0
        lastCompletedRun = nil
        configure(for: teachingSituation)
    }

    private func shouldAnalyze(at now: CFTimeInterval) -> Bool {
        guard now - lastRun >= minInterval else { return false }
        lastRun = now
        return true
    }

    private func performRequests(
        _ requests: VisionRequests,
        with handler: VNImageRequestHandler
    ) -> VisionRequestCoverage? {
        let candidates: [(VisionRequestCoverage, [VNRequest])] = [
            (.full, requests.full),
            (.mid, requests.mid),
            (.core, requests.core)
        ]
        for (coverage, requestSet) in candidates where (try? handler.perform(requestSet)) != nil {
            return coverage
        }
        return nil
    }

    private func failedFeatures() -> CVFeatures {
        // This is the `analysisSucceeded: false` fail-closed outcome of the Vision adapter.
        let failed = CVFeatures.make {
            $0.source = .vision
            $0.observationStability = lastFeatures.observationStability
            $0.analysisSucceeded = false
        }
        lastFeatures = failed
        return failed
    }

    private func makeFeatures(
        board: BoardObservation,
        people: PeopleObservation,
        layout: ClassroomLayoutMetrics,
        saliency: VNObservation?
    ) -> CVFeatures {
        let (midBand, centroid) = (people.midBand, people.centroid)
        let saliencyPeopleOverlap = people.saliencyOverlap(saliency)
        let secondaryBoardSupport = board.secondarySupport
        let coPresence = min(1, CVFeatureFusion.coPresence(
            board: board.rect,
            boardConfidence: board.confidence,
            personRects: people.rects,
            personCoverage: people.coverage
        ) + 0.08 * saliencyPeopleOverlap)
        let features = CVFeatures.make {
            $0.source = .vision
            $0.boardConfidence = board.confidence
            $0.boardRect = board.rect
            $0.boardAspectQuality = board.aspectQuality
            $0.boardGeometryQuality = board.geometryQuality
            $0.boardEdgeSupport = board.edgeSupport
            $0.personCount = people.count
            $0.personCoverage = people.coverage
            $0.faceCount = people.faceCount
            $0.personMidBandOccupancy = midBand
            $0.personCentroidY = centroid?.y
            $0.personCentroidX = centroid?.x
            $0.personBoardCoPresence = coPresence
            $0.personHorizontalSpread = layout.horizontalSpread
            $0.personVerticalSpread = layout.verticalSpread
            $0.personClusteredness = layout.clusteredness
            $0.estimatedClusterCount = layout.estimatedClusterCount
            $0.faceScaleScore = layout.faceScaleScore
            $0.boardTextDensity = board.textSupport
            $0.secondaryWritingSurfaceSupport = secondaryBoardSupport
            $0.actorScaleVariance = CVFeatureFusion.actorScaleVariance(personRects: people.rects)
            $0.poseConfidenceMean = people.poseConfidenceMean
        }
        return features
    }
}

private func visionCadence(for preset: TeachingSituationPreset) -> CFTimeInterval {
    if preset.prefersMultiPerson { return 0.45 }
    if preset.minPeople >= 3 { return 0.45 }
    if preset.requiresBoard { return 0.55 }
    return 0.50
}

enum VisionRequestCoverage: Equatable {
    case core
    case mid
    case full

    var includesDocumentsAndText: Bool { self == .mid || self == .full }
    var includesSaliencyAndPose: Bool { self == .full }
}

final class VisionRequests {
    let rectangles = VNDetectRectanglesRequest()
    let humans = VNDetectHumanRectanglesRequest()
    let faces = VNDetectFaceRectanglesRequest()
    let documents = VNDetectDocumentSegmentationRequest()
    let saliency = VNGenerateAttentionBasedSaliencyImageRequest()
    let text = VNRecognizeTextRequest()
    let pose = VNDetectHumanBodyPoseRequest()

    init() {
        rectangles.maximumObservations = 12
        rectangles.minimumConfidence = 0.35
        rectangles.minimumAspectRatio = 0.35
        rectangles.maximumAspectRatio = 4.0
        rectangles.minimumSize = 0.10
        text.recognitionLevel = .fast
        text.usesLanguageCorrection = false
        text.minimumTextHeight = 0.015
    }

    lazy var core: [VNRequest] = [rectangles, humans, faces]
    lazy var mid: [VNRequest] = core + [documents, text]
    lazy var full: [VNRequest] = mid + [saliency, pose]
}

private struct BoardObservation {
    var rect: ImageNormalizedRect?
    var confidence = 0.0
    var aspectQuality = 0.0
    var geometryQuality = 0.0
    var textSupport = 0.0
    var secondarySupport = 0.0
    var edgeSupport = 0.0

    init(requests: VisionRequests, coverage: VisionRequestCoverage) {
        let candidates = (requests.rectangles.results ?? []).map { observation in
            let rect = visionTopLeft(observation.boundingBox)
            let aspect = CVFeatureFusion.boardAspectQuality(for: rect)
            let geometry = CVFeatureFusion.boardGeometryQuality(for: rect)
            return VisionRectangleCandidate(
                rect: rect,
                confidence: Double(observation.confidence),
                aspectQuality: aspect,
                geometryQuality: geometry
            )
        }.sorted { lhs, rhs in lhs.confidence * lhs.rect.area > rhs.confidence * rhs.rect.area }
        applyRectangleCandidate(candidates.first, candidates: candidates)
        let document = coverage.includesDocumentsAndText ? requests.documents.results?.first : nil
        incorporateDocument(document)
        let textResults = coverage.includesDocumentsAndText ? (requests.text.results ?? []) : []
        let textRects = textResults.compactMap { observation -> ImageNormalizedRect? in
            observation.confidence >= 0.25 ? visionTopLeft(observation.boundingBox) : nil
        }
        textSupport = CVFeatureFusion.boardTextSupport(board: rect, textRects: textRects)
        if rect == nil, let cluster = visionTextCluster(textRects), textSupport >= 0.45 {
            rect = cluster
            aspectQuality = CVFeatureFusion.boardAspectQuality(for: cluster)
            geometryQuality = CVFeatureFusion.boardGeometryQuality(for: cluster)
            confidence = min(0.62, 0.35 + 0.4 * textSupport)
        } else if textSupport > 0.35 {
            confidence = min(1, confidence + 0.06 * textSupport)
        }
        edgeSupport = CVFeatureFusion.fuseBoardEdgeSupport(
            documentOverlap: documentOverlap(document),
            saliencyOverlap: saliencyOverlap(
                coverage.includesSaliencyAndPose ? requests.saliency.results?.first : nil
            ),
            textSupport: textSupport,
            geometryFallback: 0.15 * geometryQuality + 0.1 * aspectQuality + 0.12 * secondarySupport
        )
    }

    private mutating func applyRectangleCandidate(
        _ candidate: VisionRectangleCandidate?,
        candidates: [VisionRectangleCandidate]
    ) {
        guard let candidate else { return }
        rect = candidate.rect
        aspectQuality = candidate.aspectQuality
        geometryQuality = candidate.geometryQuality
        confidence = min(1, candidate.confidence * 0.65 + candidate.aspectQuality * 0.2 + candidate.geometryQuality * 0.15)
        secondarySupport = candidates.dropFirst().prefix(3).reduce(0) { best, next in
            max(best, visionSecondarySupport(candidate: candidate, next: next))
        }
    }

    private mutating func incorporateDocument(_ observation: VNObservation?) {
        guard let observation, let document = visionDocumentRect(observation) else { return }
        let documentConfidence = (observation as? VNDetectedObjectObservation).map { Double($0.confidence) }
            ?? (observation as? VNRectangleObservation).map { Double($0.confidence) } ?? 0
        guard rect == nil, documentConfidence >= 0.30 else { return }
        rect = document
        aspectQuality = CVFeatureFusion.boardAspectQuality(for: document)
        geometryQuality = CVFeatureFusion.boardGeometryQuality(for: document)
        confidence = min(1, documentConfidence * 0.7 + aspectQuality * 0.15 + geometryQuality * 0.15)
    }

    private func documentOverlap(_ observation: VNObservation?) -> Double {
        guard let rect, let observation, let document = visionDocumentRect(observation) else { return 0 }
        return min(1, 0.35 + 0.55 * rect.iou(with: document))
    }

    private func saliencyOverlap(_ observation: VNObservation?) -> Double {
        guard let rect, let saliency = observation as? VNSaliencyImageObservation else { return 0 }
        let best = (saliency.salientObjects ?? []).map { rect.iou(with: visionTopLeft($0.boundingBox)) }.max() ?? 0
        return min(1, 0.25 + 0.7 * best)
    }
}

private struct VisionRectangleCandidate {
    let rect: ImageNormalizedRect
    let confidence: Double
    let aspectQuality: Double
    let geometryQuality: Double
}

func visionTopLeft(_ boundingBox: CGRect) -> ImageNormalizedRect {
    ImageNormalizedRect(
        x: Double(boundingBox.origin.x),
        y: 1 - Double(boundingBox.origin.y + boundingBox.height),
        width: Double(boundingBox.width),
        height: Double(boundingBox.height)
    )
}

private func visionDocumentRect(_ observation: VNObservation) -> ImageNormalizedRect? {
    if let rectangle = observation as? VNRectangleObservation { return visionTopLeft(rectangle.boundingBox) }
    if let detected = observation as? VNDetectedObjectObservation { return visionTopLeft(detected.boundingBox) }
    return nil
}

private func visionSecondarySupport(
    candidate: VisionRectangleCandidate,
    next: VisionRectangleCandidate
) -> Double {
    guard next.rect.iou(with: candidate.rect) < 0.35 else { return 0 }
    return min(0.45, next.confidence * next.rect.area)
}

private func visionTextCluster(_ rects: [ImageNormalizedRect]) -> ImageNormalizedRect? {
    guard rects.count >= 2 else { return nil }
    let minX = rects.map(\.x).min() ?? 0
    let minY = rects.map(\.y).min() ?? 0
    let maxX = rects.map { $0.x + $0.width }.max() ?? 0
    let maxY = rects.map { $0.y + $0.height }.max() ?? 0
    guard maxX - minX > 0.08, maxY - minY > 0.04, (maxX - minX) * (maxY - minY) <= 0.65 else { return nil }
    return ImageNormalizedRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
}
