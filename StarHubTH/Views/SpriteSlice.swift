import SwiftUI

struct SpriteSlice: View {
    let nsImage: NSImage
    let rect: CGRect
    
    var body: some View {
        if let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)?.cropping(to: rect) {
            Image(nsImage: NSImage(cgImage: cgImage, size: rect.size))
                .resizable()
                .interpolation(.none) // Keep it pixelated!
        } else {
            Color.red // Error state
        }
    }
}
