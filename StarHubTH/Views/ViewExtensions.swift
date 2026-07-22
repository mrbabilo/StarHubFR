import SwiftUI
import Cocoa

extension View {
    // Utility to change cursor to pointing hand on hover (supported on all macOS versions)
    func pointingHandCursor() -> some View {
        // .set() (not .push()/.pop()) — push/pop is a stack, and a view that's
        // removed while hovered (list re-sort, filter, scroll recycling) never
        // gets to pop, leaving the pointing-hand cursor stuck permanently.
        self.onHover { inside in
            if inside {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}
