import SwiftUI

struct ModCoverView: View {
    let name: String
    let size: CGFloat
    
    var initials: String {
        let cleaned = name.replacingOccurrences(of: "[CP]", with: "")
            .replacingOccurrences(of: "[FTM]", with: "")
            .replacingOccurrences(of: "[JA]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            
        let parts = cleaned.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            
        if parts.isEmpty {
            return String(name.prefix(2)).uppercased()
        }
        
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(parts[0].prefix(2)).uppercased()
    }
    
    var gradient: LinearGradient {
        // Cozy Stardew Valley seasonal & farming palettes (Forest, Clay, Autumn Gold, Spring Teal, Lavender)
        let palettes: [[Color]] = [
            [Color(red: 0.15, green: 0.45, blue: 0.25), Color(red: 0.25, green: 0.55, blue: 0.35)], // Forest Green (Spring/Summer)
            [Color(red: 0.80, green: 0.45, blue: 0.20), Color(red: 0.90, green: 0.55, blue: 0.30)], // Pumpkin Orange (Fall)
            [Color(red: 0.85, green: 0.65, blue: 0.15), Color(red: 0.95, green: 0.75, blue: 0.25)], // Harvest Gold (Wheat)
            [Color(red: 0.20, green: 0.50, blue: 0.65), Color(red: 0.30, green: 0.60, blue: 0.75)], // River Blue (Winter)
            [Color(red: 0.60, green: 0.40, blue: 0.70), Color(red: 0.70, green: 0.50, blue: 0.80)], // Sweet Pea Lavender
            [Color(red: 0.45, green: 0.30, blue: 0.20), Color(red: 0.55, green: 0.40, blue: 0.30)], // Clay / Earth
            [Color(red: 0.10, green: 0.35, blue: 0.40), Color(red: 0.20, green: 0.45, blue: 0.50)]  // Deep Teal (Ocean)
        ]
        
        let index = abs(name.hashValue) % palettes.count
        return LinearGradient(
            gradient: Gradient(colors: palettes[index]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    var body: some View {
        ZStack {
            gradient
            
            // Thin elegant inner border
            RoundedRectangle(cornerRadius: size * 0.18)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
            
            Text(initials)
                .font(.system(size: size * 0.38, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
        }
        .frame(width: size, height: size)
        .cornerRadius(size * 0.18)
        .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
    }
}
