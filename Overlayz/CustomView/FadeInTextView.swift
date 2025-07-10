import SwiftUI
import Combine
import AppKit
import Down

// MARK: - Final User-Facing SwiftUI View

/// A view that displays markdown text with a word-by-word fade-in animation.
/// It automatically adjusts its height to fit the content.
struct FadeInTextView: View {
    // Public API properties
    @Binding var text: String
    var wordDelay: TimeInterval = 0.05
    var fadeInDuration: TimeInterval = 0.4
    var font: NSFont = .systemFont(ofSize: 18)
    var foregroundColor: NSColor = .labelColor

    @State private var isHovering = false
    // Internal state to manage the dynamic height.
    @State private var calculatedHeight: CGFloat = 0

    var body: some View {
        // Use the underlying NSViewRepresentable
        VStack(spacing: 0){
            FadeInTextView_Rep(
                text: $text,
                height: $calculatedHeight, // Pass the internal state as a binding
                wordDelay: wordDelay,
                fadeInDuration: fadeInDuration,
                font: font,
                foregroundColor: foregroundColor
            )
            // Apply the calculated height to the frame.
            .frame(height: calculatedHeight)
            // Copy button underneath
            if isHovering && !text.isEmpty {
                HStack {
                    Button(action: copyTextToClipboard) {
                        Image("copy")
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
                .padding(.leading, 8)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovering = hovering
            }
        }
    }
    
    func copyTextToClipboard(){
#if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
#endif
    }
}


// MARK: - NSViewRepresentable Implementation Detail

/// The underlying NSViewRepresentable that does the heavy lifting.
/// This is an internal implementation detail of FadeInTextView.
fileprivate struct FadeInTextView_Rep: NSViewRepresentable {
    
    @Binding var text: String
    @Binding var height: CGFloat
    
    var wordDelay: TimeInterval
    var fadeInDuration: TimeInterval
    var font: NSFont
    var foregroundColor: NSColor

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> IntrinsicSizingTextView {
        let textView = IntrinsicSizingTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 5, height: 10)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = .width
        context.coordinator.textView = textView
        
        return textView
    }

    func updateNSView(_ nsView: IntrinsicSizingTextView, context: Context) {
        let coordinator = context.coordinator
        if text.hasPrefix(coordinator.currentText) && text.count > coordinator.currentText.count {
            coordinator.continueAnimation(with: text, font: font, textColor: foregroundColor, fadeInDuration: fadeInDuration, wordDelay: wordDelay)
        } else if text != coordinator.currentText {
            coordinator.startAnimation(text: text, font: font, textColor: foregroundColor, fadeInDuration: fadeInDuration, wordDelay: wordDelay)
        }
        
        context.coordinator.updateHeight()
    }

    // MARK: - Coordinator
    
    class Coordinator: NSObject {
        var parent: FadeInTextView_Rep // Reference the representable struct
        weak var textView: IntrinsicSizingTextView?
        
        var currentText: String = ""
        private var finalAttributedString: NSAttributedString?
        private var animationTimer: Timer?
        private var animationStartTime: TimeInterval = 0
        private var wordRanges: [NSRange] = []
        private var completedWordIndices: Set<Int> = []
        
        private var fadeInDuration: TimeInterval
        private var wordDelay: TimeInterval
        private var baseColor: NSColor
        private var baseFont: NSFont

        init(_ parent: FadeInTextView_Rep) {
            self.parent = parent
            self.fadeInDuration = parent.fadeInDuration
            self.wordDelay = parent.wordDelay
            self.baseColor = parent.foregroundColor
            self.baseFont = parent.font
        }

        deinit {
            animationTimer?.invalidate()
        }
        
        func updateHeight() {
            guard let textView = textView else { return }
            let newHeight = textView.intrinsicContentSize.height
            
            if abs(parent.height - newHeight) > 1 {
                DispatchQueue.main.async {
                    self.parent.height = newHeight
                }
            }
        }

        private func createAttributedString(from markdown: String) -> NSAttributedString? {
            let styler = MarkdownStyler(baseFont: self.baseFont, baseColor: self.baseColor)
            return try? Down(markdownString: markdown).toAttributedString(styler: styler)
        }
        
        private func findAnimationRanges(in text: String, offset: Int = 0) -> [NSRange] {
            var finalRanges: [NSRange] = []
            var rawWordRanges: [NSRange] = []
            text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { _, substringRange, _, _ in
                rawWordRanges.append(NSRange(substringRange, in: text))
            }
            if rawWordRanges.isEmpty { return !text.isEmpty ? [NSRange(location: offset, length: (text as NSString).length)] : [] }
            
            for (index, currentRange) in rawWordRanges.enumerated() {
                let startLocation = currentRange.location
                let endLocation = (index < rawWordRanges.count - 1) ? rawWordRanges[index + 1].location : (text as NSString).length
                finalRanges.append(NSRange(location: startLocation + offset, length: endLocation - startLocation))
            }
            return finalRanges
        }
        
        func startAnimation(text: String, font: NSFont, textColor: NSColor, fadeInDuration: TimeInterval, wordDelay: TimeInterval) {
            animationTimer?.invalidate()
            self.currentText = text
            self.fadeInDuration = fadeInDuration
            self.wordDelay = wordDelay
            self.baseColor = textColor
            self.baseFont = font
            self.completedWordIndices = []

            guard let attributedString = createAttributedString(from: text) else {
                textView?.string = ""
                updateHeight()
                return
            }
            
            self.finalAttributedString = attributedString
            self.wordRanges = findAnimationRanges(in: attributedString.string)

            let initialAttributedString = NSMutableAttributedString(attributedString: attributedString)
            initialAttributedString.addAttribute(.foregroundColor, value: NSColor.clear, range: initialAttributedString.entireRange)
            textView?.textStorage?.setAttributedString(initialAttributedString)
            updateHeight()
            
            self.animationStartTime = CACurrentMediaTime()
            if !wordRanges.isEmpty { startTimer() }
        }
        
        func continueAnimation(with newText: String, font: NSFont, textColor: NSColor, fadeInDuration: TimeInterval, wordDelay: TimeInterval) {
            // Stop any existing animation timer.
            animationTimer?.invalidate()
            animationTimer = nil

            guard let textView = textView, let textStorage = textView.textStorage else { return }

            let oldText = self.currentText
            
            // Update properties with the latest values.
            self.currentText = newText
            self.fadeInDuration = fadeInDuration
            self.wordDelay = wordDelay
            self.baseColor = textColor
            self.baseFont = font

            // 1. Re-parse the entire updated text to correctly apply markdown styles.
            guard let newFinalAttributedString = createAttributedString(from: newText) else { return }
            self.finalAttributedString = newFinalAttributedString
            
            // Calculate the word count of the old text to determine which words are new.
            let oldWordCount = findAnimationRanges(in: oldText).count
            
            // Update word ranges based on the new, fully parsed text.
            self.wordRanges = findAnimationRanges(in: newFinalAttributedString.string)

            // 2. Prepare the attributed string for immediate display.
            let displayString = NSMutableAttributedString(attributedString: newFinalAttributedString)

            // 3. Make newly added words transparent.
            //    Existing words will be displayed immediately with their new styles (e.g., bold).
            displayString.beginEditing()
            for (index, range) in wordRanges.enumerated() {
                // Words with an index >= oldWordCount are considered new.
                if index >= oldWordCount {
                    newFinalAttributedString.enumerateAttributes(in: range, options: []) { attributes, subRange, _ in
                        var newAttributes = attributes
                        let originalColor = (attributes[.foregroundColor] as? NSColor ?? self.baseColor)
                        // Set the alpha of the new word to 0 (transparent).
                        newAttributes[.foregroundColor] = originalColor.withAlphaComponent(0)
                        displayString.setAttributes(newAttributes, range: subRange)
                    }
                }
            }
            displayString.endEditing()
            
            // Update the text view with the new string.
            textStorage.beginEditing()
            textStorage.setAttributedString(displayString)
            textStorage.endEditing()
            updateHeight()

            // 4. Update the animation state.
            // Treat previously displayed words as "completed".
            self.completedWordIndices = Set(0..<oldWordCount)
            
            // Reset the animation start time based on the elapsed time for old words
            // to ensure a seamless continuation.
            let timeElapsedForOldWords = TimeInterval(oldWordCount) * self.wordDelay
            self.animationStartTime = CACurrentMediaTime() - timeElapsedForOldWords
            
            // Restart the animation timer if there are new words to animate.
            if !wordRanges.isEmpty && self.completedWordIndices.count < self.wordRanges.count {
                startTimer()
            }
        }
        
        private func startTimer() {
            animationTimer?.invalidate()
            let timer = Timer(timeInterval: 1.0 / 60.0, target: self, selector: #selector(updateFrame), userInfo: nil, repeats: true)
            animationTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        
        @objc private func updateFrame() {
            guard let textView = textView, let finalAttributedString = self.finalAttributedString else {
                animationTimer?.invalidate()
                return
            }
            updateHeight()

            let currentTime = CACurrentMediaTime()
            let elapsedTime = currentTime - animationStartTime
            var allWordsAreNowComplete = true
            
            textView.textStorage?.beginEditing()
            for (index, range) in wordRanges.enumerated() {
                if completedWordIndices.contains(index) { continue }
                allWordsAreNowComplete = false
                let wordStartTime = TimeInterval(index) * self.wordDelay
                var progress = max(0.0, min(1.0, (elapsedTime - wordStartTime) / self.fadeInDuration))
                if elapsedTime < wordStartTime { progress = 0.0 }
                if progress == 1.0 { completedWordIndices.insert(index) }
                
                finalAttributedString.enumerateAttributes(in: range, options: []) { attributes, subRange, _ in
                    var newAttributes = attributes
                    let originalColor = (attributes[.foregroundColor] as? NSColor ?? self.baseColor).usingColorSpace(.sRGB) ?? self.baseColor
                    newAttributes[.foregroundColor] = originalColor.withAlphaComponent(progress)
                    textView.textStorage?.setAttributes(newAttributes, range: subRange)
                }
            }
            textView.textStorage?.endEditing()

            if allWordsAreNowComplete && wordRanges.count == completedWordIndices.count {
                animationTimer?.invalidate()
                animationTimer = nil
            }
        }
    }
}

// MARK: - Helper Classes

fileprivate class IntrinsicSizingTextView: NSTextView {
    override var intrinsicContentSize: NSSize {
        guard let layoutManager = layoutManager, let textContainer = textContainer else { return super.intrinsicContentSize }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(usedRect.height + textContainerInset.height * 2))
    }
    
    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }
}

fileprivate class MarkdownStyler: DownStyler {
    init(baseFont: NSFont, baseColor: NSColor) {
        var config = DownStylerConfiguration()
        config.fonts = CustomFontCollection(baseFont: baseFont)
        config.colors = CustomColorCollection(baseColor: baseColor)
        super.init(configuration: config)
    }
    
    override func style(strong str: NSMutableAttributedString) {
        self.apply(symbolicTrait: .bold, to: str)
    }

    override func style(emphasis str: NSMutableAttributedString) {
        self.apply(symbolicTrait: .italic, to: str)
    }

    private func apply(symbolicTrait: NSFontDescriptor.SymbolicTraits, to str: NSMutableAttributedString) {
        str.enumerateAttribute(.font, in: str.entireRange, options: []) { value, range, _ in
            guard let font = value as? NSFont else { return }

            let currentDescriptor = font.fontDescriptor
            let newTraits = currentDescriptor.symbolicTraits.union(symbolicTrait)

            guard let basicFamilyName = font.familyName else { return }

            let attributes: [NSFontDescriptor.AttributeName: Any] = [
                .family: basicFamilyName,
                .traits: [NSFontDescriptor.TraitKey.symbolic: newTraits.rawValue]
            ]
            
            let newDescriptor = NSFontDescriptor(fontAttributes: attributes)
            
            if let newFont = NSFont(descriptor: newDescriptor, size: font.pointSize) {
                str.addAttribute(.font, value: newFont, range: range)
            } else {
                let convertedFont = NSFontManager.shared.convert(font, toHaveTrait: symbolicTrait == .bold ? .boldFontMask : .italicFontMask)
                str.addAttribute(.font, value: convertedFont, range: range)
            }
        }
    }

    
    override func style(listItemPrefix str: NSMutableAttributedString) {
        if str.string.contains("*") {
            str.replaceCharacters(in: str.entireRange, with: "•\t")
        }
        super.style(listItemPrefix: str)
    }
}

private struct CustomFontCollection: FontCollection {
    var body: NSFont, code: NSFont, heading1: NSFont, heading2: NSFont, heading3: NSFont, heading4: NSFont, heading5: NSFont, heading6: NSFont, listItemPrefix: NSFont
    init(baseFont: NSFont) {
        self.body = baseFont; self.code = NSFont.userFixedPitchFont(ofSize: baseFont.pointSize * 0.9) ?? baseFont
        self.heading1 = .boldSystemFont(ofSize: baseFont.pointSize + 8); self.heading2 = .boldSystemFont(ofSize: baseFont.pointSize + 6)
        self.heading3 = .boldSystemFont(ofSize: baseFont.pointSize + 4); self.heading4 = .boldSystemFont(ofSize: baseFont.pointSize + 2)
        self.heading5 = .boldSystemFont(ofSize: baseFont.pointSize); self.heading6 = .boldSystemFont(ofSize: baseFont.pointSize)
        self.listItemPrefix = baseFont
    }
}

private struct CustomColorCollection: ColorCollection {
    var body: NSColor, code: NSColor, link: NSColor, heading1: NSColor, heading2: NSColor, heading3: NSColor, heading4: NSColor, heading5: NSColor, heading6: NSColor, thematicBreak: NSColor, quote: NSColor, quoteStripe: NSColor, codeBlockBackground: NSColor, listItemPrefix: NSColor
    init(baseColor: NSColor) {
        self.body = baseColor; self.code = baseColor.withAlphaComponent(0.8); self.link = .linkColor
        self.heading1 = baseColor; self.heading2 = baseColor; self.heading3 = baseColor; self.heading4 = baseColor; self.heading5 = baseColor; self.heading6 = baseColor
        self.thematicBreak = .separatorColor; self.quote = baseColor.withAlphaComponent(0.7); self.quoteStripe = .separatorColor
        self.codeBlockBackground = .separatorColor.withAlphaComponent(0.2); self.listItemPrefix = baseColor
    }
}

extension NSMutableAttributedString {
    var entireRange: NSRange { NSRange(location: 0, length: self.length) }
}


// MARK: - Preview and Usage Example

#Preview {
    struct PreviewWrapper: View {
        @State private var demoText = ""
        
        let initialText = """
        # Fade-In TextView Demo
        This text view **_smooth and reliable_** adjusts its height based on the content.
        
        * When new text is added, the view will grow taller.
        * The `height` binding is no longer needed here!
        """
        
        let appendedText = """
        
        ---
        ### More Content Added!
        As you can see, the view has expanded to accommodate this new paragraph. The animation continues seamlessly from where it left off.
        """

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    
                    // --- FINAL, CLEAN USAGE ---
                    // No need to pass a height binding or set a frame.
                    // The view now manages its own height internally.
                    FadeInTextView(
                        text: $demoText,
                        font: .systemFont(ofSize: 16, weight: .light)
                    )
                    .padding()
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
                    .shadow(radius: 2)

                    HStack {
                        Button("Start Animation") {
                            demoText = ""
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                demoText = initialText
                            }
                        }
                        
                        Button("Append Text") {
                            if !demoText.contains("More Content Added!") {
                                demoText += appendedText
                            }
                        }
                        
                        Button("Clear") {
                            demoText = ""
                        }
                    }
                    .padding(.top, 5)

                }
                .padding()
            }
            .onAppear {
                demoText = initialText
            }
        }
    }
    
    return PreviewWrapper()
        .frame(width: 500, height: 400)
}
