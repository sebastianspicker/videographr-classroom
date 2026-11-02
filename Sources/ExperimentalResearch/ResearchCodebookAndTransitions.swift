import Foundation
import GuidanceEngine
import SessionCore

// MARK: - Scene transition detector

/// Detects teaching-scene / layout / TIMSS-primary changes for continuous-take research logs.
public struct SceneTransitionEvent: Equatable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var at: Date
    public var fromScene: String
    public var toScene: String
    public var fromLayout: String
    public var toLayout: String
    public var fromTIMSS: String?
    public var toTIMSS: String?
    public var noteDE: String

    public struct Values: Sendable {
        public var id = UUID()
        public var at = Date()
        public var fromScene = ""
        public var toScene = ""
        public var fromLayout = ""
        public var toLayout = ""
        public var fromTIMSS: String?
        public var toTIMSS: String?
        public var noteDE = ""

        public init() {}
    }

    public init(_ values: Values) {
        id = values.id
        at = values.at
        fromScene = values.fromScene
        toScene = values.toScene
        fromLayout = values.fromLayout
        toLayout = values.toLayout
        fromTIMSS = values.fromTIMSS
        toTIMSS = values.toTIMSS
        noteDE = values.noteDE
    }
}

public struct SceneTransitionDetector: Equatable, Sendable {
    public private(set) var lastScene: TeachingSceneType?
    public private(set) var lastLayout: ClassroomLayoutPattern?
    public private(set) var lastTIMSS: TIMSSActivityCode?
    public private(set) var events: [SceneTransitionEvent]
    public var maxEvents: Int

    public init(maxEvents: Int = 32) {
        self.lastScene = nil
        self.lastLayout = nil
        self.lastTIMSS = nil
        self.events = []
        self.maxEvents = max(4, maxEvents)
    }

    public mutating func reset() {
        lastScene = nil
        lastLayout = nil
        lastTIMSS = nil
        events.removeAll()
    }

    /// Observe scene (+ optional coding); returns a transition event if structure changed.
    @discardableResult
    public mutating func observe(
        scene: TeachingSceneAssessment,
        coding: PedagogicalCodingResult? = nil,
        at date: Date = Date()
    ) -> SceneTransitionEvent? {
        let sceneType = scene.sceneType
        let layout = scene.layoutPattern
        let timss = coding?.primaryTIMSS

        defer {
            lastScene = sceneType
            lastLayout = layout
            if let timss { lastTIMSS = timss }
        }

        guard let prevScene = lastScene, let prevLayout = lastLayout else {
            return nil
        }

        let input = TransitionInput(
            fromScene: prevScene,
            toScene: sceneType,
            fromLayout: prevLayout,
            toLayout: layout,
            fromTIMSS: lastTIMSS,
            toTIMSS: timss
        )
        let transition = transitionDetails(input)
        guard transition.changed else { return nil }
        var values = SceneTransitionEvent.Values()
        values.at = date
        values.fromScene = prevScene.rawValue
        values.toScene = sceneType.rawValue
        values.fromLayout = prevLayout.rawValue
        values.toLayout = layout.rawValue
        values.fromTIMSS = lastTIMSS?.rawValue
        values.toTIMSS = timss?.rawValue
        values.noteDE = transition.noteDE
        let event = SceneTransitionEvent(values)
        events.append(event)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
        return event
    }

    private struct TransitionInput {
        let fromScene: TeachingSceneType
        let toScene: TeachingSceneType
        let fromLayout: ClassroomLayoutPattern
        let toLayout: ClassroomLayoutPattern
        let fromTIMSS: TIMSSActivityCode?
        let toTIMSS: TIMSSActivityCode?
    }

    private func transitionDetails(_ input: TransitionInput) -> (changed: Bool, noteDE: String) {
        let sceneChanged = input.fromScene != input.toScene
        let layoutChanged = input.fromLayout != input.toLayout
        let timssChanged = input.fromTIMSS != nil && input.toTIMSS != nil && input.fromTIMSS != input.toTIMSS
        let changed = sceneChanged || layoutChanged || timssChanged
        return (changed, transitionNote(
            sceneChanged: sceneChanged,
            layoutChanged: layoutChanged,
            timssChanged: timssChanged,
            input: input
        ))
    }

    private func transitionNote(
        sceneChanged: Bool,
        layoutChanged: Bool,
        timssChanged: Bool,
        input: TransitionInput
    ) -> String {
        var parts: [String] = []
        if sceneChanged { parts.append("Szene \(input.fromScene.titleDE) → \(input.toScene.titleDE)") }
        if layoutChanged { parts.append("Layout \(input.fromLayout.titleDE) → \(input.toLayout.titleDE)") }
        if timssChanged, let fromTIMSS = input.fromTIMSS, let toTIMSS = input.toTIMSS {
            parts.append("TIMSS \(fromTIMSS.titleDE) → \(toTIMSS.titleDE)")
        }
        return parts.joined(separator: "; ")
    }
}
