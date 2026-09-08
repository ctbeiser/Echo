import AppKit
import Foundation

enum AccountSwipeDirection: Equatable {
    case previous
    case next
}

// Follow one physical gesture; momentum after release belongs to that gesture.
// Lock vertical scrolling before horizontal trackpad drift can move a panel.
struct AccountSwipeRecognizer {
    enum Action: Equatable {
        case pending
        case passThrough
        case consume
        case changed(translation: Double)
        case ended(translation: Double, velocity: Double)
        case cancelled
    }

    private enum Axis {
        case undecided
        case website
        case horizontal
    }

    private var horizontal: Double = 0
    private var vertical: Double = 0
    private var velocity: Double = 0
    private var axis = Axis.undecided
    private var isFinished = false
    private var lastTimestamp: TimeInterval = 0
    private var lastMovementTimestamp: TimeInterval = 0

    mutating func reset() { self = Self() }

    mutating func leaveGestureWithWebsite() { axis = .website }

    mutating func handle(deltaX: Double, deltaY: Double, phase: NSEvent.Phase, momentumPhase: NSEvent.Phase, timestamp: TimeInterval, canSwipePrevious: Bool, canSwipeNext: Bool, hasPreciseScrollingDeltas: Bool = true) -> Action {
        if phase.contains(.began) || phase.contains(.mayBegin) ||
            (phase.isEmpty && momentumPhase.isEmpty && timestamp - lastTimestamp > 0.25) {
            reset()
        }
        let elapsed = timestamp - lastTimestamp
        lastTimestamp = timestamp
        if !momentumPhase.isEmpty {
            if axis == .horizontal && !isFinished { return finish(timestamp: timestamp) }
            let action: Action = axis == .horizontal ? .consume : .passThrough
            if momentumPhase.contains(.ended) || momentumPhase.contains(.cancelled) { reset() }
            return action
        }
        if phase.contains(.cancelled) {
            let action: Action = axis == .horizontal ? .cancelled : .passThrough
            reset()
            return action
        }
        if isFinished { return axis == .horizontal ? .consume : .passThrough }
        horizontal += deltaX
        vertical += abs(deltaY)
        if deltaX != 0 {
            if elapsed > 0 && elapsed < 0.2 {
                velocity = (velocity * 0.3) + (min(max(deltaX / elapsed, -2500), 2500) * 0.7)
            }
            lastMovementTimestamp = timestamp
        }
        if axis == .undecided {
            // Mouse-wheel deltas are lines, not trackpad pixels. A single
            // vertical notch should reach the website immediately.
            let minimumDistance = hasPreciseScrollingDeltas ? 12.0 : 0.0
            if vertical > minimumDistance && vertical > abs(horizontal) * 1.25 {
                axis = .website
            } else if abs(horizontal) > minimumDistance && abs(horizontal) > vertical * 1.4 {
                // An outward pan belongs to the website, including its buffered
                // beginning, any later reversal, and momentum after release.
                let canPage = horizontal < 0 ? canSwipeNext : canSwipePrevious
                axis = canPage ? .horizontal : .website
            }
        }
        if axis == .undecided && !phase.contains(.ended) { return .pending }
        guard axis == .horizontal else { return .passThrough }
        if phase.contains(.ended) { return finish(timestamp: timestamp) }
        return .changed(translation: horizontal)
    }

    mutating func finish(timestamp: TimeInterval) -> Action {
        guard axis == .horizontal else { return .passThrough }
        guard !isFinished else { return .consume }
        isFinished = true
        return .ended(translation: horizontal, velocity: timestamp - lastMovementTimestamp < 0.12 ? velocity : 0)
    }
}
