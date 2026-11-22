import Foundation

public struct ReadingPreferences: Codable, Equatable, Sendable {
    public enum Appearance: String, Codable, CaseIterable, Sendable { case system, light, dark }
    public var fontSize: Double
    public var appearance: Appearance
    public var followsVoice: Bool
    public var mirrorsText: Bool
    public var chineseCharactersPerMinute: Double
    public var englishWordsPerMinute: Double
    public var localeID: String
    public init(fontSize: Double = 32, appearance: Appearance = .system, followsVoice: Bool = true, localeID: String = "zh-CN", mirrorsText: Bool = false, chineseCharactersPerMinute: Double = 240, englishWordsPerMinute: Double = 140) {
        self.fontSize = fontSize; self.appearance = appearance; self.followsVoice = followsVoice; self.localeID = localeID
        self.mirrorsText = mirrorsText
        self.chineseCharactersPerMinute = chineseCharactersPerMinute
        self.englishWordsPerMinute = englishWordsPerMinute
        normalize()
    }
    public mutating func normalize() {
        fontSize = fontSize.isFinite ? min(48, max(26, fontSize)) : 32
        chineseCharactersPerMinute = chineseCharactersPerMinute.isFinite ? min(320, max(160, chineseCharactersPerMinute)) : 240
        englishWordsPerMinute = englishWordsPerMinute.isFinite ? min(220, max(100, englishWordsPerMinute)) : 140
        if !["zh-CN", "en-US"].contains(localeID) { localeID = "zh-CN" }
    }
    private enum CodingKeys: String, CodingKey {
        case fontSize, appearance, followsVoice, localeID, mirrorsText, chineseCharactersPerMinute, englishWordsPerMinute
    }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(fontSize: try values.decodeIfPresent(Double.self, forKey: .fontSize) ?? 32,
                  appearance: try values.decodeIfPresent(Appearance.self, forKey: .appearance) ?? .system,
                  followsVoice: try values.decodeIfPresent(Bool.self, forKey: .followsVoice) ?? true,
                  localeID: try values.decodeIfPresent(String.self, forKey: .localeID) ?? "zh-CN",
                  mirrorsText: try values.decodeIfPresent(Bool.self, forKey: .mirrorsText) ?? false,
                  chineseCharactersPerMinute: try values.decodeIfPresent(Double.self, forKey: .chineseCharactersPerMinute) ?? 240,
                  englishWordsPerMinute: try values.decodeIfPresent(Double.self, forKey: .englishWordsPerMinute) ?? 140)
    }
}
