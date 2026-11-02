import Foundation
import GuidanceEngine
import SessionCore

/// Multi-observation teaching-scene smoother (Derry continuous takes).
/// Stabilizes scene type / preset match without inventing structure when CV fails.
public struct TeachingSceneWindow: Equatable, Sendable {
    public var capacity: Int
    public private(set) var samples: [TeachingSceneAssessment]

    public init(capacity: Int = 6) {
        self.capacity = max(2, capacity)
        self.samples = []
    }

    public mutating func push(_ assessment: TeachingSceneAssessment) {
        // Do not smooth over hard unusable failures when confidence is zero (CV fail path).
        samples.append(assessment)
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }

    public mutating func reset() {
        samples.removeAll()
    }

    /// Majority scene type + averaged scores; nil if empty.
    public func aggregate() -> TeachingSceneAssessment? {
        guard let last = samples.last else { return nil }
        guard samples.count >= 2 else { return last }
        return aggregate(samples, last: last)
    }

    private func aggregate(_ samples: [TeachingSceneAssessment], last: TeachingSceneAssessment) -> TeachingSceneAssessment {
        let dominantType = dominantScene(in: samples, fallback: last.sceneType)
        let pool = scenePool(samples, matching: dominantType)

        var totals = AggregateTotals()
        var layoutCounts: [ClassroomLayoutPattern: Int] = [:]
        for sample in pool {
            totals.confidence += sample.confidence
            totals.match += sample.presetMatchScore
            totals.board += sample.boardSignal
            totals.people += sample.peopleSignal
            totals.coPresence += sample.coPresenceSignal
            totals.multiPerson += sample.multiPersonSignal
            totals.layout += sample.layoutSignal
            layoutCounts[sample.layoutPattern, default: 0] += 1
        }
        let divisor = Double(pool.count)
        let conf = totals.confidence / divisor
        let match = totals.match / divisor
        let board = totals.board / divisor
        let people = totals.people / divisor
        let co = totals.coPresence / divisor
        let multi = totals.multiPerson / divisor
        let layoutSig = totals.layout / divisor
        let layout = mostRecentFrequentValue(
            in: pool.lazy.map(\.layoutPattern),
            counts: layoutCounts
        ) ?? last.layoutPattern

        let matches = matchesPreset(in: samples, last: last, match: match)

        var summaryInput = SummaryInput()
        summaryInput.matches = matches
        summaryInput.sampleCount = samples.count
        summaryInput.scene = dominantType
        summaryInput.layout = layout
        summaryInput.match = match
        let summary = aggregateSummary(summaryInput)

        var values = AggregateValues()
        values.scene = dominantType
        values.confidence = conf
        values.match = match
        values.matches = matches
        values.summary = summary
        values.people = people
        values.coPresence = co
        values.multiPerson = multi
        values.board = board
        values.layoutSignal = layoutSig
        values.layout = layout
        return assessment(values)
    }

    private struct AggregateValues {
        var scene: TeachingSceneType = .emptyOrUnusable
        var confidence = 0.0
        var match = 0.0
        var matches = false
        var summary = ""
        var people = 0.0
        var coPresence = 0.0
        var multiPerson = 0.0
        var board = 0.0
        var layoutSignal = 0.0
        var layout: ClassroomLayoutPattern = .unknown
    }

    private struct AggregateTotals {
        var confidence = 0.0
        var match = 0.0
        var people = 0.0
        var coPresence = 0.0
        var multiPerson = 0.0
        var board = 0.0
        var layout = 0.0
    }

    private func assessment(_ values: AggregateValues) -> TeachingSceneAssessment {
        let classification = TeachingSceneAssessment.Classification(
            sceneType: values.scene, confidence: values.confidence,
            presetMatchScore: values.match, matchesPreset: values.matches
        )
        let peopleSignals = TeachingSceneAssessment.PeopleSignals(
            peopleSignal: values.people, coPresenceSignal: values.coPresence,
            multiPersonSignal: values.multiPerson
        )
        let structureSignals = TeachingSceneAssessment.StructureSignals(
            boardSignal: values.board, layoutSignal: values.layoutSignal, layoutPattern: values.layout
        )
        return TeachingSceneAssessment(.init(
            classification: classification,
            summaryDE: values.summary,
            peopleSignals: peopleSignals,
            structureSignals: structureSignals
        ))
    }

    private struct SummaryInput {
        var matches = false
        var sampleCount = 0
        var scene: TeachingSceneType = .emptyOrUnusable
        var layout: ClassroomLayoutPattern = .unknown
        var match = 0.0
    }

    private func dominantScene(
        in samples: [TeachingSceneAssessment],
        fallback: TeachingSceneType
    ) -> TeachingSceneType {
        var counts: [TeachingSceneType: Int] = [:]
        for sample in samples { counts[sample.sceneType, default: 0] += 1 }
        return mostRecentFrequentValue(in: samples.lazy.map(\.sceneType), counts: counts) ?? fallback
    }

    private func scenePool(
        _ samples: [TeachingSceneAssessment],
        matching scene: TeachingSceneType
    ) -> [TeachingSceneAssessment] {
        let matchingSamples = samples.filter { $0.sceneType == scene }
        return matchingSamples.isEmpty ? samples : matchingSamples
    }

    private func matchesPreset(
        in samples: [TeachingSceneAssessment],
        last: TeachingSceneAssessment,
        match: Double
    ) -> Bool {
        let votes = samples.reduce(into: 0) { count, sample in
            if sample.matchesPreset { count += 1 }
        }
        let hasMajority = votes * 2 > samples.count
        let tieFavorsLatest = votes * 2 == samples.count && last.matchesPreset
        return (hasMajority || tieFavorsLatest) && match >= 0.40
    }

    private func aggregateSummary(_ input: SummaryInput) -> String {
        if input.matches {
            return "Zeitfenster (\(input.sampleCount)): Szene „\(input.scene.titleDE)“ stabil · Layout \(input.layout.titleDE) · Match \(percentText(input.match))."
        }
        return "Zeitfenster (\(input.sampleCount)): Szene „\(input.scene.titleDE)“ · Match \(percentText(input.match)) - Preset noch nicht stabil erfüllt."
    }

    /// Most frequent value, with the latest occurrence resolving an equal vote count.
}

func mostRecentFrequentValue<Values: BidirectionalCollection>(
    in values: Values,
    counts: [Values.Element: Int]
) -> Values.Element? where Values.Element: Hashable {
    var best: Values.Element?
    var highestCount = -1
    for value in values.reversed() {
        let count = counts[value] ?? 0
        if count > highestCount {
            best = value
            highestCount = count
        }
    }
    return best
}
