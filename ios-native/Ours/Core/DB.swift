import Foundation
import FirebaseDatabase

extension DatabaseReference {
    /// Speichern ohne auf die Antwort zu warten (offline landet es in der Warteschlange)
    func put(_ value: Any?) {
        setValue(value) { _, _ in }
    }
    /// Felder ergänzen ohne zu warten
    func merge(_ values: [String: Any]) {
        updateChildValues(values) { _, _ in }
    }
    /// Löschen ohne zu warten
    func drop() {
        removeValue { _, _ in }
    }
}

enum DB {
    static var root: DatabaseReference { Database.database().reference() }
    static var nowMs: Double { (Date().timeIntervalSince1970 * 1000).rounded() }

    /// Zufällige ID wie auf der Webseite (Buchstaben und Ziffern)
    static func randomID(_ n: Int = 20) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<n).map { _ in chars.randomElement()! })
    }

    /// Gut lesbarer Einladungscode ohne verwechselbare Zeichen
    static func inviteCode() -> String {
        let chars = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String((0..<8).map { _ in chars.randomElement()! })
    }

    static func num(_ v: Any?) -> Double {
        if let n = v as? NSNumber { return n.doubleValue }
        if let d = v as? Double { return d }
        if let s = v as? String, let d = Double(s) { return d }
        return 0
    }

    static func dict(_ v: Any?) -> [String: Any] { v as? [String: Any] ?? [:] }
}
