//
//  StepFlow.swift
//  ClearWellNC
//
//  Navigation state for a multi-step flow: the first step plus a NavigationStack path. A value type,
//  so it is saved inside each flow's draft and tested without any views.
//

import Foundation

nonisolated struct StepFlow<Step: Hashable & Codable & Sendable>: Codable, Equatable, Sendable {
    private(set) var root: Step
    /// Steps pushed after the root, bound to NavigationStack(path:).
    var path: [Step] = []

    init(root: Step) {
        self.root = root
    }

    var current: Step { path.last ?? root }
    var canGoBack: Bool { !path.isEmpty }
    /// Every step on screen or behind it, first to current.
    var visited: [Step] { [root] + path }

    mutating func push(_ step: Step) { path.append(step) }

    mutating func back() {
        if !path.isEmpty { path.removeLast() }
    }

    /// Makes `step` the new first step with nothing to go back to (after a safety alert, or once saved).
    mutating func restart(at step: Step) {
        root = step
        path = []
    }

    // MARK: Linear flows

    /// Pushes the step after the current one in `order`. Does nothing on the last step.
    mutating func advance(in order: [Step]) {
        guard let index = order.firstIndex(of: current), index + 1 < order.count else { return }
        push(order[index + 1])
    }

    /// "Step 2 of 7" for the current step, or nil if it isn't in `order`.
    func progress(in order: [Step]) -> StepProgress? {
        guard let index = order.firstIndex(of: current) else { return nil }
        return StepProgress(position: index + 1, total: order.count)
    }

    /// Whether every visited step still exists in `order` (a restored draft might be stale).
    func isValid(in order: [Step]) -> Bool {
        visited.allSatisfy(order.contains)
    }
}

nonisolated struct StepProgress: Equatable, Sendable {
    /// 1-based position, or steps completed for flows that aren't linear.
    let position: Int
    let total: Int
    /// Overrides "Step 2 of 7" (for example "Question 2 of 7").
    var label: String?

    var fraction: Double { total > 0 ? min(1, Double(position) / Double(total)) : 0 }

    var text: String { label ?? String(localized: "Step \(position) of \(total)") }
}
