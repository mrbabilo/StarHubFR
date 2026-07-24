import SwiftUI
import Cocoa

extension View {
    // Utility to change cursor to pointing hand on hover.
    func pointingHandCursor() -> some View {
        // onContinuousHover (not onHover): a single enter event (.onHover) loses
        // to AppKit's cursor-rect machinery — e.g. `.textSelection(.enabled)`
        // hosts an NSTextView that re-asserts the I-beam cursor on every mouse
        // move, overwriting the one-shot .set(). Re-setting the hand on *each*
        // move wins that race, so links inside selectable description text show
        // the pointing hand instead of the editing caret.
        //
        // .set() (not .push()/.pop()) — push/pop is a stack, and a view that's
        // removed while hovered (list re-sort, filter, scroll recycling) never
        // gets to pop, leaving the pointing-hand cursor stuck permanently.
        self.onContinuousHover { phase in
            switch phase {
            case .active:
                NSCursor.pointingHand.set()
            case .ended:
                NSCursor.arrow.set()
            @unknown default:
                NSCursor.arrow.set()
            }
        }
    }
}
