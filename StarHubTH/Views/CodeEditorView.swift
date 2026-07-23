import SwiftUI
import AppKit

struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        scrollView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        scrollView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.allowsUndo = true
        textView.textColor = NSColor.textColor
        
        let ruler = LineNumberRulerView(textView: textView)
        scrollView.verticalRulerView = ruler
        
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        let textView = nsView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorView

        init(_ parent: CodeEditorView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            self.parent.text = textView.string
            
            if let scrollView = textView.enclosingScrollView,
               let ruler = scrollView.verticalRulerView as? LineNumberRulerView {
                ruler.needsDisplay = true
            }
        }
    }
}

class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView!, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 45
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = self.textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let textString = textView.string as NSString
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: textView.visibleRect, in: textContainer)
        let visibleCharacterRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange, actualGlyphRange: nil)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        // Draw background and separator line
        NSColor.windowBackgroundColor.setFill()
        self.bounds.fill()
        
        let path = NSBezierPath()
        path.move(to: NSPoint(x: ruleThickness - 0.5, y: self.bounds.minY))
        path.line(to: NSPoint(x: ruleThickness - 0.5, y: self.bounds.maxY))
        NSColor.separatorColor.setStroke()
        path.stroke()
        
        // Redraw numbers over background
        var index = visibleCharacterRange.location
        var lineNumber = 1
        var tempIndex = 0
        while tempIndex < visibleCharacterRange.location {
            let lineRange = textString.lineRange(for: NSRange(location: tempIndex, length: 0))
            tempIndex = NSMaxRange(lineRange)
            lineNumber += 1
        }
        
        while index < NSMaxRange(visibleCharacterRange) {
            let lineRange = textString.lineRange(for: NSRange(location: index, length: 0))
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: index)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            
            let yPos = lineRect.minY - textView.bounds.minY
            let text = NSString(format: "%d", lineNumber)
            let size = text.size(withAttributes: attributes)
            
            let drawPoint = NSPoint(x: ruleThickness - size.width - 8, y: yPos + (lineRect.height - size.height) / 2.0)
            text.draw(at: drawPoint, withAttributes: attributes)
            
            index = NSMaxRange(lineRange)
            lineNumber += 1
        }
    }
}
