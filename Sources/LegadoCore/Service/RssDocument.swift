import Foundation

public enum RssDocument {
    public static func html(content: String, source: RssSource) -> String {
        let body: String
        if content.range(of: "<[/!]?[A-Za-z][^>]*>", options: .regularExpression) != nil { body = content }
        else {
            body = content.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\n", with: "<br>")
        }
        let css: String
        if let custom = source.style, !custom.isEmpty { css = custom }
        else if body.lowercased().contains("<style") { css = "" }
        else { css = "img,video{max-width:100%;height:auto}body{overflow-wrap:anywhere;font:17px -apple-system;padding:12px;}" }
        return "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><style>\(css)</style>" + body
    }
}
