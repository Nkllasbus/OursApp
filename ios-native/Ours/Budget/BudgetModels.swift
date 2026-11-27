import Foundation
import SwiftUI

/// Konto (fin/accounts/<id>)
struct BankAccount: Identifiable, Hashable {
    let id: String
    var name: String
    var bank: String?
    var src: String?
    var kind: String?
    var balance: Int?
    var syncAt: Double
    var session: String?
    var ebUid: String?
    var iban: String?

    var subtitle: String { bank ?? (kind == "depot" ? "Depot" : src == "csv" ? "CSV-Import" : "Manuell") }
    var isPayPal: Bool { "\(bank ?? "") \(name)".lowercased().contains("paypal") }

    static func parse(_ id: String, _ raw: Any?) -> BankAccount? {
        let v = DB.dict(raw)
        guard !v.isEmpty else { return nil }
        return BankAccount(id: id, name: v["name"] as? String ?? "Konto", bank: v["bank"] as? String, src: v["src"] as? String,
                           kind: v["kind"] as? String, balance: v["balance"] == nil ? nil : Int(DB.num(v["balance"])),
                           syncAt: DB.num(v["syncAt"]), session: v["session"] as? String, ebUid: v["ebUid"] as? String,
                           iban: v["iban"] as? String)
    }
}

/// Umsatz (fin/tx/<id>) oder manuelle Ausgabe (spaces/<budget>/expenses)
struct Transaction: Identifiable, Hashable {
    let id: String
    var acc: String?
    var date: String
    var amount: Int          // Cent, negativ = Ausgabe
    var name: String
    var text: String
    var cat: String?
    var catSrc: String?
    var ex: Bool
    var pending: Bool
    var src: String?         // eb, csv, manual

    static func parse(_ id: String, _ raw: Any?) -> Transaction? {
        let v = DB.dict(raw)
        guard let date = v["date"] as? String, let a = v["amount"] as? NSNumber else { return nil }
        return Transaction(id: id, acc: v["acc"] as? String, date: date, amount: a.intValue, name: v["name"] as? String ?? "",
                           text: v["text"] as? String ?? "", cat: v["cat"] as? String, catSrc: v["catSrc"] as? String,
                           ex: (v["ex"] as? Bool) ?? false, pending: (v["pending"] as? Bool) ?? false, src: v["src"] as? String)
    }
}

/// Korrektur je Kategorie (fin/adj/<id>): a > 0 Geld zurück, a < 0 Ausgabe dazu
struct BudgetAdjustment: Identifiable, Hashable {
    let id: String
    var cat: String
    var a: Int
    var n: String?
    var d: String
    var tx: String?

    static func parse(_ id: String, _ raw: Any?) -> BudgetAdjustment? {
        let v = DB.dict(raw)
        guard let cat = v["cat"] as? String, let d = v["d"] as? String, v["a"] != nil else { return nil }
        return BudgetAdjustment(id: id, cat: cat, a: Int(DB.num(v["a"])), n: v["n"] as? String, d: d, tx: v["tx"] as? String)
    }
}

struct ExtraIncome: Identifiable, Hashable {
    let id: String
    var n: String
    var a: Int
    var monthly: Bool
    var period: String?
}

/// Erkannter Vertrag (wiederkehrende Abbuchung)
struct Contract: Identifiable, Hashable {
    var id: String { key }
    let key: String
    let name: String
    let cat: String
    let rhythm: String
    let rhythmLabel: String
    let avg: Int
    let perMonth: Int
    let last: Date
    let next: Date
    let txs: [Transaction]
    let raise: (from: Int, to: Int)?
    let isNew: Bool
    let manualID: String?

    static func == (a: Contract, b: Contract) -> Bool { a.key == b.key && a.avg == b.avg && a.next == b.next }
    func hash(into h: inout Hasher) { h.combine(key) }
}

struct SalaryInfo {
    let start: String
    let end: String
    let amount: Int
    let fromSalary: Bool
    let manual: Bool
    let daysLeft: Int
}

struct MonthTotals {
    var inc = 0, out = 0, back = 0
    var byCat: [String: Int] = [:]
    var txByCat: [String: [Transaction]] = [:]
    var left: Int { inc + back - out }
}

enum Money {
    static let fmt: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "de_DE")
        f.currencyCode = "EUR"
        return f
    }()
    static func text(_ cents: Int) -> String { fmt.string(from: NSNumber(value: Double(cents) / 100)) ?? "\(cents / 100) €" }
    static func signed(_ cents: Int) -> String { (cents > 0 ? "+" : "") + text(cents) }
    static func parse(_ s: String) -> Int? {
        var t = s.replacingOccurrences(of: "€", with: "").replacingOccurrences(of: " ", with: "")
        if t.contains(",") { t = t.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
        guard let d = Double(t), d.isFinite, d > 0 else { return nil }
        return Int((d * 100).rounded())
    }
}

enum BudgetCats {
    static let base = ["Lebensmittel", "Essen gehen", "Wohnen", "Mobilität", "Shopping", "Freizeit", "Medien & Abos", "Versicherung",
                       "Gesundheit", "Bildung", "Bargeld", "Sparen & Investieren", "Gebühren & Zinsen", "Umbuchung", "Gehalt",
                       "Sonstige Einnahmen", "Rückzahlung", "Sonstiges"]
    static let noSpend: Set<String> = ["Umbuchung"]
    static let save = "Sparen & Investieren"
    static let back = "Rückzahlung"
    static let income: Set<String> = ["Gehalt", "Sonstige Einnahmen", "Rückzahlung"]
    static let palette: [UInt32] = [0x3F70B8, 0x3F9A5E, 0xD08440, 0x8A63B5, 0x3A93A3, 0xC7514A, 0xC09A35, 0xC25A86,
                                    0x5A5FB0, 0x2F9488, 0x7A9A3E, 0x8A67B8, 0xC0703C, 0x3D82B3, 0x98A1AD, 0xA07C3E]
    /// Apple-Systemfarben und SF Symbols je Kategorie
    /// ruhige, gedeckte Farben (Apple-ähnlich, nicht grell) und SF Symbols je Kategorie
    static let style: [String: (color: Color, symbol: String)] = [
        "Lebensmittel": (Color(hex: 0x4E9A6F), "cart.fill"),
        "Essen gehen": (Color(hex: 0xC98B4E), "fork.knife"),
        "Wohnen": (Color(hex: 0x9A8068), "house.fill"),
        "Mobilität": (Color(hex: 0x5A82BF), "car.fill"),
        "Shopping": (Color(hex: 0xB86F86), "bag.fill"),
        "Freizeit": (Color(hex: 0x8A72B8), "ticket.fill"),
        "Medien & Abos": (Color(hex: 0xBF6A60), "play.tv.fill"),
        "Versicherung": (Color(hex: 0x5B9AA3), "shield.fill"),
        "Gesundheit": (Color(hex: 0x5FA394), "cross.case.fill"),
        "Bildung": (Color(hex: 0x6B70B5), "book.fill"),
        "Bargeld": (Color(hex: 0xB89B52), "banknote.fill"),
        "Sparen & Investieren": (Color(hex: 0x4F93B3), "chart.line.uptrend.xyaxis"),
        "Gebühren & Zinsen": (Color(hex: 0x8E8E93), "percent"),
        "Umbuchung": (Color(hex: 0xA3A3A8), "arrow.left.arrow.right"),
        "Gehalt": (Color(hex: 0x4E9A6F), "briefcase.fill"),
        "Sonstige Einnahmen": (Color(hex: 0x5B9AA3), "arrow.down.circle.fill"),
        "Rückzahlung": (Color(hex: 0x5A82BF), "arrow.uturn.backward"),
        "Sonstiges": (Color(hex: 0x98989D), "ellipsis"),
    ]
    static let extraColors: [Color] = [Color(hex: 0x6B70B5), Color(hex: 0xC98B4E), Color(hex: 0x5B9AA3), Color(hex: 0xB86F86), Color(hex: 0x8A72B8), Color(hex: 0x5A82BF)]
    static let green = Color(hex: 0x3F9467)
    static let red = Color(hex: 0xC4625A)
    static let months = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"]
}
