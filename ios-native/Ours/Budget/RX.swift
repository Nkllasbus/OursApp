import Foundation

/// Kleine Hülle um NSRegularExpression, damit die Regeln wie in JavaScript lesbar bleiben
struct RX {
    let re: NSRegularExpression

    init(_ pattern: String, ci: Bool = true) {
        re = (try? NSRegularExpression(pattern: pattern, options: ci ? [.caseInsensitive] : []))
            ?? (try! NSRegularExpression(pattern: "(?!)"))
    }

    func test(_ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    /// Text der Gruppe `group` des ersten Treffers
    func first(_ s: String, group: Int = 0) -> String? {
        guard let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              m.numberOfRanges > group, let r = Range(m.range(at: group), in: s) else { return nil }
        return String(s[r])
    }

    func replace(_ s: String, with t: String) -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: t)
    }
}
