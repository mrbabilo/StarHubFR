import SwiftUI
import Cocoa

extension View {
    // Utility to change cursor to pointing hand on hover (supported on all macOS versions)
    func pointingHandCursor() -> some View {
        self.onHover { inside in
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

struct LocalImageView: View {
    let filename: String
    var height: CGFloat
    
    var body: some View {
        let path = "/Users/cj/works/stardew-thai-translations/banners/\(filename)"
        if let nsImg = NSImage(contentsOfFile: path) {
            Image(nsImage: nsImg)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: height)
                .clipped()
        } else {
            // Fallback gradient if file not found
            LinearGradient(
                colors: [Color(red: 0.15, green: 0.45, blue: 0.25), Color(red: 0.10, green: 0.30, blue: 0.15)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: height)
        }
    }
}
