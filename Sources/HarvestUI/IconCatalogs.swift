import Foundation

/// Every SF Symbol on this Mac, with the words Apple's SF Symbols app finds
/// them by, read from the system's own symbol lists. Where those aren't
/// readable (iOS), it falls back to the curated set.
enum SymbolCatalog {
    struct Symbol: Sendable {
        let name: String
        /// The name's words plus Apple's search keywords, lowercased.
        let words: String
    }

    static let all: [Symbol] = load()

    /// Symbols matching every word typed, best first: names that start with
    /// the query, then names containing it, then keyword matches.
    static func search(_ query: String, limit: Int = 400) -> [String] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return [] }
        let first = terms[0]
        var scored: [(String, Int)] = []
        for symbol in all where terms.allSatisfy({ symbol.words.contains($0) }) {
            let score = symbol.name.hasPrefix(first) ? 0 : symbol.name.contains(first) ? 1 : 2
            scored.append((symbol.name, score))
        }
        return scored
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.count < $1.0.count }
            .prefix(limit).map(\.0)
    }

    private static func load() -> [Symbol] {
        let folder = URL(fileURLWithPath: "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources")
        guard let order = NSArray(contentsOf: folder.appendingPathComponent("symbol_order.plist")) as? [String] else {
            return FavoriteIcon.symbols.map { Symbol(name: $0, words: $0.replacingOccurrences(of: ".", with: " ")) }
        }
        let keywords = NSDictionary(contentsOf: folder.appendingPathComponent("symbol_search.plist")) as? [String: [String]] ?? [:]
        return order.compactMap { name in
            // Skip the per-language variants ("character.ar", "…rtl").
            let last = name.split(separator: ".").last.map(String.init) ?? ""
            if name.contains(".") && (last.count == 2 && last != "up" && last != "2x" || last == "rtl") { return nil }
            let words = ([name.replacingOccurrences(of: ".", with: " ")] + (keywords[name] ?? [])).joined(separator: " ").lowercased()
            return Symbol(name: name, words: words)
        }
    }
}

/// Every standard emoji, with its Unicode name to search by ("grinning
/// face", "rocket"). Single-character emoji only: skin tones and flags
/// still work when typed or pasted into the search box.
enum EmojiCatalog {
    struct Emoji: Sendable {
        let character: String
        let name: String
    }

    static let all: [Emoji] = load()

    static func search(_ query: String) -> [String] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return all.map(\.character) }
        return all.filter { emoji in terms.allSatisfy { emoji.name.contains($0) } }.map(\.character)
    }

    /// Roughly the order the Mac's emoji picker uses: faces and people,
    /// nature, food, travel and places, activities, objects, symbols.
    private static let ranges: [ClosedRange<UInt32>] = [
        0x1F600...0x1F64F, 0x1F910...0x1F92F, 0x1F970...0x1F97F, 0x1F9D0...0x1F9FF, 0x1F440...0x1F4AF,
        0x1F90C...0x1F90F, 0x1F930...0x1F94F, 0x1F400...0x1F43F, 0x1F980...0x1F9AF, 0x1F330...0x1F37F,
        0x1F950...0x1F96F, 0x1FAD0...0x1FADF, 0x1F680...0x1F6FF, 0x1F300...0x1F32F, 0x1F380...0x1F3FF,
        0x1F4B0...0x1F5FF, 0x1FA70...0x1FACF, 0x1FAE0...0x1FAFF, 0x1F9B0...0x1F9CF, 0x2600...0x27BF,
        0x2190...0x21FF, 0x2B00...0x2BFF, 0x231A...0x23FF, 0x1F004...0x1F0CF, 0x1F170...0x1F251,
    ]

    private static func load() -> [Emoji] {
        var seen = Set<UInt32>()
        var out: [Emoji] = []
        for range in ranges {
            for value in range where seen.insert(value).inserted {
                guard let scalar = Unicode.Scalar(value), scalar.properties.isEmoji,
                      !(0x1F3FB...0x1F3FF).contains(value),          // skin tone swatches
                      let name = scalar.properties.name else { continue }
                // Text-style characters (☀, ✏) need the emoji form asked for.
                let character = scalar.properties.isEmojiPresentation
                    ? String(scalar) : String(scalar) + "\u{FE0F}"
                out.append(Emoji(character: character, name: name.lowercased()))
            }
        }
        return out
    }
}
