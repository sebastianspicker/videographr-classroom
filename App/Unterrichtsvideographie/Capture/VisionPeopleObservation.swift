import Foundation
import Vision
import ExperimentalResearch
import GuidanceEngine

struct PeopleObservation {
    var rects: [ImageNormalizedRect] = []
    var count = 0
    var coverage = 0.0
    var faceCount = 0
    var jointPoints: [(x: Double, y: Double)] = []
    var poseConfidences: [Double] = []

    init(requests: VisionRequests, requestCoverage: VisionRequestCoverage) {
        rects = (requests.humans.results ?? []).map { visionTopLeft($0.boundingBox) }
        count = rects.count
        coverage = min(1, rects.reduce(0) { $0 + $1.area })
        faceCount = requests.faces.results?.count ?? 0
        useFacesWhenNeeded(requests.faces.results ?? [])
        let poses = requestCoverage.includesSaliencyAndPose ? (requests.pose.results ?? []) : []
        collectPose(poses)
        usePoseWhenNeeded(poses.count)
    }

    var midBand: Double {
        let rectangles = CVFeatureFusion.midBandOccupancy(personRects: rects)
        guard !jointPoints.isEmpty else { return rectangles }
        let joints = CVFeatureFusion.midBandOccupancy(jointPoints: jointPoints)
        return rects.isEmpty ? joints : max(rectangles, 0.55 * rectangles + 0.45 * joints)
    }

    var centroid: (x: Double, y: Double)? {
        let rectangles = CVFeatureFusion.peopleCentroid(personRects: rects)
        guard let joints = CVFeatureFusion.peopleCentroid(jointPoints: jointPoints) else { return rectangles }
        guard let rectangles else { return joints }
        return (0.55 * rectangles.x + 0.45 * joints.x, 0.55 * rectangles.y + 0.45 * joints.y)
    }

    var poseConfidenceMean: Double {
        guard !poseConfidences.isEmpty else { return 0 }
        return poseConfidences.reduce(0, +) / Double(poseConfidences.count)
    }

    func layout() -> ClassroomLayoutMetrics {
        let initial = ClassroomLayoutAnalyzer.analyze(layoutInput())
        guard jointPoints.count >= 3, rects.count < max(2, jointPoints.count / 4) else { return initial }
        return blend(initial, with: jointLayout())
    }

    func saliencyOverlap(_ observation: VNObservation?) -> Double {
        guard !rects.isEmpty, let saliency = observation as? VNSaliencyImageObservation else { return 0 }
        let best = (saliency.salientObjects ?? []).flatMap { object in
            rects.map { $0.iou(with: visionTopLeft(object.boundingBox)) }
        }.max() ?? 0
        return min(1, 0.2 + 0.75 * best)
    }

    private mutating func useFacesWhenNeeded(_ faces: [VNFaceObservation]) {
        guard count == 0, faceCount > 0 else { return }
        rects = faces.map { visionTopLeft($0.boundingBox) }
        count = faceCount
        coverage = min(0.25, Double(faceCount) * 0.04)
    }

    private mutating func usePoseWhenNeeded(_ poseCount: Int) {
        guard count == 0, !jointPoints.isEmpty else { return }
        count = poseCount
        coverage = max(coverage, min(0.22, Double(count) * 0.05))
    }

    private func layoutInput() -> ClassroomLayoutAnalysisInput {
        var input = ClassroomLayoutAnalysisInput(personRects: rects)
        input.faceCount = faceCount
        input.personCount = count
        return input
    }

    private func jointLayout() -> ClassroomLayoutMetrics {
        let syntheticRects = jointPoints.map {
            ImageNormalizedRect(x: max(0, $0.x - 0.03), y: max(0, $0.y - 0.04), width: 0.06, height: 0.08)
        }
        var input = ClassroomLayoutAnalysisInput(personRects: syntheticRects)
        input.faceCount = faceCount
        input.personCount = max(count, poseConfidences.count)
        return ClassroomLayoutAnalyzer.analyze(input)
    }

    private mutating func collectPose(_ poses: [VNHumanBodyPoseObservation]) {
        let names: [VNHumanBodyPoseObservation.JointName] = [
            .nose, .neck, .root, .leftShoulder, .rightShoulder, .leftElbow, .rightElbow,
            .leftWrist, .rightWrist, .leftHip, .rightHip, .leftKnee, .rightKnee
        ]
        for pose in poses { appendPosePoints(names.compactMap { try? pose.recognizedPoint($0) }) }
    }

    private mutating func appendPosePoints(_ candidates: [VNRecognizedPoint?]) {
        let points = candidates.compactMap { $0 }.filter { $0.confidence >= 0.22 }
        guard !points.isEmpty else { return }
        jointPoints.append(contentsOf: points.map { (Double($0.location.x), 1 - Double($0.location.y)) })
        poseConfidences.append(points.reduce(0) { $0 + Double($1.confidence) } / Double(points.count))
    }

    private func blend(_ initial: ClassroomLayoutMetrics, with joints: ClassroomLayoutMetrics) -> ClassroomLayoutMetrics {
        makeLayout {
            $0.horizontalSpread = max(initial.horizontalSpread, joints.horizontalSpread)
            $0.verticalSpread = max(initial.verticalSpread, joints.verticalSpread)
            $0.clusteredness = 0.45 * initial.clusteredness + 0.55 * joints.clusteredness
            $0.estimatedClusterCount = max(initial.estimatedClusterCount, joints.estimatedClusterCount)
            $0.faceScaleScore = max(initial.faceScaleScore, joints.faceScaleScore)
        }
    }
}

private func makeLayout(_ configure: (inout ClassroomLayoutMetrics.Values) -> Void) -> ClassroomLayoutMetrics {
    var values = ClassroomLayoutMetrics.Values()
    configure(&values)
    return ClassroomLayoutMetrics(values)
}
