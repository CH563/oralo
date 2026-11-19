import Foundation

public enum PlainTextImport {
    public static let maximumBytes = 2 * 1024 * 1024

    public static func decode(_ data: Data, filename: String) throws -> String {
        guard ["txt", "md"].contains(URL(fileURLWithPath: filename).pathExtension.lowercased()) else {
            throw ScriptLibraryError.unsupportedFile
        }
        guard data.count <= maximumBytes else { throw ScriptLibraryError.fileTooLarge }
        let text: String?
        if data.starts(with: [0xFF, 0xFE]) { text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) }
        else if data.starts(with: [0xFE, 0xFF]) { text = String(data: data.dropFirst(2), encoding: .utf16BigEndian) }
        else {
            let payload = data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data[...]
            text = String(data: payload, encoding: .utf8)
        }
        guard let text, !text.unicodeScalars.contains(where: { $0.value == 0 || ($0.value < 32 && ![9, 10, 13].contains($0.value)) }) else {
            throw ScriptLibraryError.unsupportedText
        }
        return text // Do not normalize Markdown, whitespace, line endings or punctuation.
    }

    public static func read(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while data.count <= maximumBytes {
            let chunk = try handle.read(upToCount: min(64 * 1024, maximumBytes + 1 - data.count)) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        return try decode(data, filename: url.lastPathComponent)
    }
}
