import Foundation
import OraloCore

struct PronunciationReference: Sendable {
    let kind: Pronunciation.Kind
    let candidates: [String]
    let source: String
}

/// File parsing happens once on this actor, never on the reading/highlight path.
actor PronunciationLookup {
    static let shared = PronunciationLookup()
    private var english: [String: [String]]?

    func reference(for term: String, kind: Pronunciation.Kind) -> PronunciationReference {
        if kind == .pinyin {
            let value = term.applyingTransform(.mandarinToLatin, reverse: false)
            let candidates = value.map { $0 != term ? [$0] : [] } ?? []
            return PronunciationReference(kind: kind, candidates: candidates, source: "Apple Mandarin transliteration")
        }
        if english == nil {
            var words: [String: [String]] = [:]
            if let url = Bundle.main.url(forResource: "EnglishIPA", withExtension: "txt"),
               let contents = try? String(contentsOf: url, encoding: .utf8) {
                for line in contents.split(separator: "\n") {
                    let parts = line.split(separator: "\t", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    words[String(parts[0])] = parts[1].components(separatedBy: ", ")
                }
            }
            english = words
        }
        let key = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: "’", with: "'")
        return PronunciationReference(kind: kind, candidates: english?[key] ?? [], source: "ipa-dict · en_US")
    }
}

enum PronunciationCopy {
    static var chinese: Bool { MacCopy.chinese }
    static func text(_ zh: String, _ en: String) -> String { MacCopy.text(zh, en) }
    static func kind(for text: String) -> Pronunciation.Kind {
        text.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) || (0x20000...0x323AF).contains($0.value) } ? .pinyin : .ipa
    }
}
