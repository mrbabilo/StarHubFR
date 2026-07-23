import SwiftUI

struct AppChangelogView: View {
    @ObservedObject var vm: StarHubTHViewModel
    @State private var changelogText: String = "Loading..."
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(vm.L(L10n.Main.appChangelog))
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            ScrollView {
                SimpleMarkdownView(text: changelogText)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
        .onAppear {
            loadChangelog()
        }
    }
    
    private func loadChangelog() {
        if let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md") {
            do {
                changelogText = try String(contentsOf: url, encoding: .utf8)
            } catch {
                changelogText = "Failed to read CHANGELOG.md: \(error.localizedDescription)"
            }
        } else {
            changelogText = "CHANGELOG.md not found in app bundle."
        }
    }
}

struct SimpleMarkdownView: View {
    let text: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let lines = text.components(separatedBy: .newlines)
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                if line.hasPrefix("### ") {
                    Text(String(line.dropFirst(4)))
                        .font(.headline)
                        .padding(.top, 8)
                } else if line.hasPrefix("## ") {
                    Text(String(line.dropFirst(3)))
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.top, 16)
                        .padding(.bottom, 4)
                } else if line.hasPrefix("# ") {
                    Text(String(line.dropFirst(2)))
                        .font(.title)
                        .fontWeight(.bold)
                        .padding(.top, 16)
                } else if line.trimmingCharacters(in: .whitespaces).hasPrefix("- ") {
                    let indent = line.prefix(while: { $0 == " " }).count
                    let content = line.trimmingCharacters(in: .whitespaces).dropFirst(2)
                    HStack(alignment: .top, spacing: 6) {
                        Text(indent > 0 ? "◦" : "•")
                        if let attr = try? AttributedString(markdown: String(content), options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                            Text(attr)
                        } else {
                            Text(String(content))
                        }
                    }
                    .padding(.leading, CGFloat(indent * 6 + 4))
                } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    // skip empty lines
                } else {
                    if let attr = try? AttributedString(markdown: line, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                        Text(attr)
                    } else {
                        Text(line)
                    }
                }
            }
        }
        .textSelection(.enabled)
    }
}

