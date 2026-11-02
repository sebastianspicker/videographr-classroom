import Foundation
import GuidanceEngine
import SessionCore

public struct PedagogicalCodingWindow: Equatable, Sendable {
    public let capacity: Int
    public private(set) var samples: [PedagogicalCodingResult]

    public init(capacity: Int = 8) {
        self.capacity = max(1, capacity)
        samples = []
    }

    public mutating func push(_ result: PedagogicalCodingResult) {
        samples.append(result)
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
    }

    public mutating func reset() { samples.removeAll() }

    public func aggregate() -> PedagogicalCodingResult? {
        guard let last = samples.last else { return nil }
        guard samples.count > 1 else { return last }
        let ipnIndex = assignmentIndex(for: .ipnProcessQuality)
        let timssIndex = assignmentIndex(for: .timssActivityScript)
        let gtiIndex = assignmentIndex(for: .gtiQuality)
        let ipn = aggregateAssignments(
            IPNDimensionCode.allCases.map(\.rawValue),
            family: .ipnProcessQuality,
            index: ipnIndex
        )
        let timss = aggregateAssignments(
            timssIndex.codesInObservationOrder,
            family: .timssActivityScript,
            index: timssIndex
        )
        let gti = aggregateAssignments(
            GTIQualityCode.allCases.map(\.rawValue),
            family: .gtiQuality,
            index: gtiIndex
        )
        return aggregateResult(ipn: ipn, timss: timss, gti: gti, last: last)
    }

    private struct AssignmentIndex {
        var byCode: [String: [PedagogicalCodeAssignment]] = [:]
        var lastSampleIndexByCode: [String: Int] = [:]
        var codesInObservationOrder: [String] = []
    }

    private func assignmentIndex(for family: PedagogicalCodeFamily) -> AssignmentIndex {
        var index = AssignmentIndex()
        var seen = Set<String>()
        for (sampleIndex, sample) in samples.enumerated() {
            for assignment in assignments(sample, family: family) {
                index.byCode[assignment.code, default: []].append(assignment)
                index.lastSampleIndexByCode[assignment.code] = sampleIndex
                if seen.insert(assignment.code).inserted {
                    index.codesInObservationOrder.append(assignment.code)
                }
            }
        }
        return index
    }

    private func aggregateAssignments(
        _ codes: [String],
        family: PedagogicalCodeFamily,
        index: AssignmentIndex
    ) -> [PedagogicalCodeAssignment] {
        codes.compactMap {
            aggregateAssignment(code: $0, family: family, values: index.byCode[$0] ?? [])
        }.sorted {
            rankedBefore($0, $1, lastSampleIndexByCode: index.lastSampleIndexByCode)
        }
    }

    private func aggregateAssignment(
        code: String,
        family: PedagogicalCodeFamily,
        values: [PedagogicalCodeAssignment]
    ) -> PedagogicalCodeAssignment? {
        guard let recent = values.last else { return nil }
        var level = 0.0
        var confidence = 0.0
        for value in values {
            level += value.level
            confidence += value.confidence
        }
        // Frames without the code count as 0, so rare strong codes do not outrank steady ones.
        level /= Double(samples.count)
        confidence /= Double(samples.count)
        let identity = PedagogicalCodeAssignment.Identity(id: "\(family.rawValue)-\(code)", family: family)
        let descriptor = PedagogicalCodeAssignment.Descriptor(code: code, labelDE: recent.labelDE)
        let measurement = PedagogicalCodeAssignment.Measurement(level: level, confidence: confidence)
        let assignmentValues = PedagogicalCodeAssignment.Values(identity: identity, descriptor: descriptor, measurement: measurement, rationaleDE: "Fenster-Aggregation (\(samples.count) Beobachtungen). \(recent.rationaleDE)")
        return PedagogicalCodeAssignment(assignmentValues)
    }

    private func aggregateResult(ipn: [PedagogicalCodeAssignment], timss: [PedagogicalCodeAssignment], gti: [PedagogicalCodeAssignment], last: PedagogicalCodingResult) -> PedagogicalCodingResult {
        let primary = timss.first.flatMap { TIMSSActivityCode(rawValue: $0.code) } ?? last.primaryTIMSS
        let primaryGTI = gti.first.flatMap { GTIQualityCode(rawValue: $0.code) } ?? last.primaryGTI
        let confidence = samples.map(\.overallConfidence).reduce(0, +) / Double(samples.count)
        let scene = mostRecentMode(samples.map(\.sceneType)) ?? last.sceneType
        let layout = mostRecentMode(samples.map(\.layoutPattern)) ?? last.layoutPattern
        let assignments = PedagogicalCodingResult.Assignments(ipnDimensions: ipn, timssActivities: timss, gtiDimensions: gti)
        let primaryCodes = PedagogicalCodingResult.PrimaryCodes(timss: primary, gti: primaryGTI)
        let content = PedagogicalCodingResult.Content(assignments: assignments, primaryCodes: primaryCodes, overallConfidence: confidence, summaryDE: "Zeitfenster (\(samples.count)): TIMSS \(primary.titleDE); GTI \(primaryGTI.titleDE); Szene \(scene.titleDE); Layout \(layout.titleDE).")
        let context = PedagogicalCodingResult.Context(sceneType: scene, teachingSituation: last.teachingSituation, layoutPattern: layout, analysisFocus: last.analysisFocus)
        return PedagogicalCodingResult(.init(content: content, context: context))
    }

    private func rankedBefore(
        _ lhs: PedagogicalCodeAssignment,
        _ rhs: PedagogicalCodeAssignment,
        lastSampleIndexByCode: [String: Int]
    ) -> Bool {
        if lhs.level != rhs.level { return lhs.level > rhs.level }
        let left = lastSampleIndexByCode[lhs.code] ?? -1
        let right = lastSampleIndexByCode[rhs.code] ?? -1
        return left == right ? lhs.code < rhs.code : left > right
    }

    private func assignments(_ sample: PedagogicalCodingResult, family: PedagogicalCodeFamily) -> [PedagogicalCodeAssignment] {
        switch family {
        case .ipnProcessQuality: return sample.ipnDimensions
        case .timssActivityScript: return sample.timssActivities
        case .gtiQuality: return sample.gtiDimensions
        }
    }

    private func mostRecentMode<Value: Hashable>(_ values: [Value]) -> Value? {
        let counts = values.reduce(into: [Value: Int]()) { $0[$1, default: 0] += 1 }
        return values.reversed().max { (counts[$0] ?? 0) < (counts[$1] ?? 0) }
    }
}
