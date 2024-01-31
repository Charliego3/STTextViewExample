//
//  ViewController.swift
//  STTextViewExample
//
//  Created by Charlie on 2024/1/31.
//

import Cocoa
import STTextView
import SwiftUI
import NaturalLanguage

class ViewController: NSViewController {
    var textView: STTextView!
    var completions: [Completion.Item] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let scrollView = STTextView.scrollableTextView()
        textView = scrollView.documentView as? STTextView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor.textBackgroundColor

        let paragraph = NSParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
        paragraph.lineHeightMultiple = 1.2
        textView.typingAttributes[.paragraphStyle] = paragraph

        textView.font = NSFont.monospacedSystemFont(ofSize: 0, weight: .regular)
        textView.string = "typing here"
        textView.widthTracksTextView = true // nowrap
        textView.highlightSelectedLine = true
        textView.isIncrementalSearchingEnabled = true
        textView.showsInvisibleCharacters = false
        textView.backgroundColor = .clear
        textView.delegate = self

        // Line numbers
        let rulerView = STLineNumberRulerView(textView: textView)
        rulerView.font = NSFont.monospacedSystemFont(ofSize: 0, weight: .regular)
        rulerView.allowsMarkers = false
        rulerView.highlightSelectedLine = true
        rulerView.backgroundColor = .clear
        scrollView.verticalRulerView = rulerView
        scrollView.rulersVisible = true

        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        updateCompletionsInBackground()
    }
    
    override func viewDidDisappear() {
        super.viewDidDisappear()
        completionTask?.cancel()
    }

    private var completionTask: Task<(), Never>?

    /// Update completion list with words
    private func updateCompletionsInBackground() {
        completionTask?.cancel()
        completionTask = Task(priority: .background) {
            var arr: Set<String> = []

            for await word in SimpleParser.words(textView.string) where !Task.isCancelled {
                arr.insert(word.string)
            }

            if Task.isCancelled {
                return
            }

            self.completions = arr
                .filter {
                    $0.count > 2
                }
                .sorted { lhs, rhs in
                    lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
                }
                .map { word in
                    let symbol: String
                    if let firstCharacter = word.first, firstCharacter.isASCII, firstCharacter.isLetter {
                        symbol = "\(word.first!.lowercased()).square"
                    } else {
                        symbol = "note.text"
                    }

                    return Completion.Item(id: UUID().uuidString, label: word.localizedCapitalized, symbolName: symbol, insertText: word)
                }
        }
    }
    
}

class SimpleParser {

    struct Word: CustomStringConvertible {
        let string: String

        var description: String {
            string
        }
    }

    static func words(_ string: String, maxCount: Int = 512) -> AsyncStream<Word> {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = string

        return AsyncStream { continuation in
            var count = 0
            tokenizer.enumerateTokens(in: string.startIndex..<string.endIndex) { tokenRange, attributes in
                if !attributes.contains(.numeric) {
                    let token = String(string[tokenRange]).lowercased()
                    continuation.yield(Word(string: token))
                    count += 1
                }

                if count > maxCount {
                    continuation.finish()
                    return false
                }

                return !Task.isCancelled
            }

            continuation.finish()
        }
    }
}

enum Completion {

    struct Item: STCompletionItem {
        let id: String
        let label: String
        let symbolName: String
        let insertText: String

        var view: NSView {
            NSHostingView(rootView: VStack(alignment: .leading) {
                HStack {
                    Image(systemName: symbolName)
                        .frame(width: 24)

                    Text(label)

                    Spacer()
                }
            })
        }
    }

}

extension ViewController: STTextViewDelegate {

    func textView(_ textView: STTextView, didChangeTextIn affectedCharRange: NSTextRange, replacementString: String) {
        // Continous completion update disabled due to bad performance for large strings
         updateCompletionsInBackground()
    }

    // Completion
    func textView(_ textView: STTextView, completionItemsAtLocation location: NSTextLocation) -> [any STCompletionItem]? {
        var word: String?
        textView.textLayoutManager.enumerateSubstrings(from: location, options: [.byWords, .reverse]) { substring, substringRange, enclosingRange, stop in
            word = substring
            stop.pointee = true
        }

        if let word {
            return completions.filter { item in
                item.insertText.hasPrefix(word.localizedLowercase)
            }
        }

        return nil
    }

    func textView(_ textView: STTextView, insertCompletionItem item: any STCompletionItem) {
        guard let completionItem = item as? Completion.Item else {
            fatalError()
        }

        textView.insertText(completionItem.insertText)
    }
}
