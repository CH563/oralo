import Foundation

/// Matching forms retain the original grapheme ranges used by the reading highlight.
enum SpeechText {
    private static let digits: [Character: Int] = ["零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3,
        "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
    private static let units: [Character: Int] = ["十": 10, "百": 100, "千": 1_000, "万": 10_000, "亿": 100_000_000]

    static func tokenize(_ text: String) -> [CueMatcher.TextToken] {
        let original = Array(text)
        // Mandarin recognition may return Simplified text for a Traditional script.
        // Canonicalize matching only; retain the original grapheme coordinates used
        // by highlighting. If a transform changes length, do not guess an alignment.
        let matching: [Character]
        if text.unicodeScalars.contains(where: isHan),
           let simplified = text.applyingTransform(StringTransform("Hant-Hans"), reverse: false),
           simplified.count == original.count {
            matching = Array(simplified)
        } else { matching = original }
        let chars = matching.map { String($0).folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
        var result: [CueMatcher.TextToken] = []
        var index = 0
        while index < chars.count {
            let start = index
            let percentPrefix = index + 3 < chars.count && chars[index..<(index + 3)].joined() == "百分之"
            if percentPrefix || isNumeric(chars[index]) {
                var end = percentPrefix ? index + 3 : index
                while end < chars.count, isNumeric(chars[end]) || ((chars[end] == "." || chars[end] == "点") && end + 1 < chars.count && isNumeric(chars[end + 1])) { end += 1 }
                let numberStart = percentPrefix ? index + 3 : index
                if let number = canonicalNumber(chars[numberStart..<end].joined()) {
                    var percent = percentPrefix
                    if end < chars.count, chars[end] == "%" { percent = true; end += 1 }
                    result.append(.init(value: "#" + number + (percent ? "%" : ""), characters: start..<end))
                    index = end
                    continue
                }
            }
            if original[index].unicodeScalars.contains(where: isHan) {
                result.append(.init(value: chars[index], characters: index..<(index + 1)))
                index += 1
            } else if original[index].isLetter || original[index].isNumber {
                index += 1
                while index < chars.count, (original[index].isLetter || original[index].isNumber), !original[index].unicodeScalars.contains(where: isHan) { index += 1 }
                result.append(.init(value: chars[start..<index].joined(), characters: start..<index))
            } else { index += 1 }
        }
        return result
    }

    static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        (0x3400...0x9FFF).contains(scalar.value) || (0x20000...0x3134F).contains(scalar.value)
    }

    private static func isNumeric(_ text: String) -> Bool {
        text.count == 1 && text.first.map { ("0"..."9").contains($0) || digits[$0] != nil || units[$0] != nil } == true
    }

    private static func canonicalNumber(_ text: String) -> String? {
        let pieces = text.replacingOccurrences(of: "点", with: ".").split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count <= 2, let integer = pieces.first, !integer.isEmpty, integer.count <= 16 else { return nil }
        var whole: String
        if integer.allSatisfy({ ("0"..."9").contains($0) }) {
            whole = String(integer.drop(while: { $0 == "0" }))
            if whole.isEmpty { whole = "0" }
        } else if !integer.contains(where: { units[$0] != nil }) {
            let values = integer.compactMap { digits[$0] }
            guard values.count == integer.count else { return nil }
            whole = values.map(String.init).joined()
        } else {
            var total = 0, section = 0, digit = 0
            for character in integer {
                if let value = digits[character] { digit = value }
                else if let unit = units[character] {
                    if unit < 10_000 { section += max(1, digit) * unit }
                    else {
                        let product = (section + digit).multipliedReportingOverflow(by: unit)
                        guard !product.overflow else { return nil }
                        let sum = total.addingReportingOverflow(product.partialValue)
                        guard !sum.overflow else { return nil }
                        total = sum.partialValue; section = 0
                    }
                    digit = 0
                } else { return nil }
            }
            let sum = total.addingReportingOverflow(section + digit)
            guard !sum.overflow else { return nil }
            whole = String(sum.partialValue)
        }
        if pieces.count == 2 {
            var fraction = ""
            for character in pieces[1] {
                if ("0"..."9").contains(character) { fraction.append(character) }
                else if let value = digits[character] { fraction.append(String(value)) }
                else { return nil }
            }
            while fraction.last == "0" { fraction.removeLast() }
            if !fraction.isEmpty { whole += "." + fraction }
        }
        return whole
    }
}
