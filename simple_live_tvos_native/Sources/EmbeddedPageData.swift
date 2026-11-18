import Foundation
import SimpleLiveTVOSCore

enum EmbeddedPageData {
    static func initialState(in html: String, marker: String = #"window\.__INITIAL_STATE__\s*=\s*"#) throws -> JSONObject {
        guard let assignment = html.range(of: marker, options: .regularExpression) else {
            throw LiveProviderError.invalidResponse
        }
        let source = html[assignment.upperBound...].drop(while: \.isWhitespace)
        guard source.first == "{" else { throw LiveProviderError.invalidResponse }
        var depth = 0
        var quoted = false
        var escaped = false
        for index in source.indices {
            let character = source[index]
            if quoted {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { quoted = false }
            } else if character == "\"" {
                quoted = true
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    let json = String(source[...index])
                    if let result = try? JSONObject.decode(Data(json.utf8)) { return result }
                    return try JSONObject.decode(Data(replacingUndefined(in: json).utf8))
                }
            }
        }
        throw LiveProviderError.invalidResponse
    }

    private static func replacingUndefined(in json: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #""(?:[^"\\]|\\.)*"|\bundefined\b"#) else { return json }
        var output = json
        for match in re.matches(in: json, range: NSRange(json.startIndex..., in: json)).reversed() {
            guard let source = Range(match.range, in: json), json[source] == "undefined",
                  let destination = Range(match.range, in: output) else { continue }
            output.replaceSubrange(destination, with: "null")
        }
        return output
    }
}

struct MediaVariant {
    let quality: LiveQuality
    let urls: [(URL, StreamProtocol)]

    func resources(headers: [String: String]) -> [PlaybackResource] {
        urls.enumerated().map { index, entry in
            PlaybackResource(url: entry.0, protocolKind: entry.1, headers: headers, quality: quality.name, lineIndex: index)
        }
    }

    static func url(_ value: String, hint: StreamProtocol? = nil) -> (URL, StreamProtocol)? {
        guard let url = URL(string: normalizedImage(value)),
              let scheme = url.scheme?.lowercased(), url.host != nil,
              url.user == nil, url.password == nil else { return nil }
        if ["rtmp", "rtmps"].contains(scheme) { return (url, .rtmp) }
        guard ["http", "https"].contains(scheme) else { return nil }
        switch url.pathExtension.lowercased() {
        case "m3u8": return (url, .hls)
        case "flv": return (url, .flv)
        default: return hint.map { (url, $0) }
        }
    }
}
