import Foundation
import Observation
import FirebaseAuth
import FirebaseDatabase
import SwiftUI

/// Privates Budget (users/<uid>/fin) – gleiche Rechenregeln wie budget.html
@MainActor
@Observable
final class BudgetStore {
    // Rohdaten
    var loaded = false
    var accounts: [String: BankAccount] = [:]
    var rawTx: [String: Transaction] = [:]
    var manual: [String: Transaction] = [:]
    var rules: [String: String] = [:]
    var budgets: [String: Int] = [:]
    var contractMeta: [String: [String: Any]] = [:]
    var eb: [String: [String: Any]] = [:]
    var alias: [String: String] = [:]
    var aicat: [String: String] = [:]
    var adj: [String: BudgetAdjustment] = [:]
    var salaryManual = 0
    var periodDay = 1
    var periodSince: String?
    var recurring: [String: [String: Any]] = [:]
    var salaryShift = true
    var ppKeep: Set<String> = []
    var extraIncome: [ExtraIncome] = []
    var customCats: [String] = []
    var lastSyncAt: Double = 0
    var syncing = false
    var message: String?

    // Abgeleitet (nach jeder Änderung neu berechnet)
    private(set) var allTx: [Transaction] = []
    private(set) var cats: [String: String] = [:]
    private(set) var labels: [String: String] = [:]
    private(set) var keys: [String: String] = [:]
    private(set) var ppMap: [String: (with: String?, kind: String)] = [:]
    private var ppFrom: [String: String] = [:]
    private var merchCache: [String: (label: String, cat: String?, proc: Bool)] = [:]

    private(set) var uid = ""
    private(set) var budgetSid: String?
    private var handles: [(DatabaseReference, DatabaseHandle)] = []
    private var db: DatabaseReference { DB.root }
    private var fin: DatabaseReference { db.child("users/\(uid)/fin") }
    static let worker = URL(string: "https://oursapp.niklasbergnerbus.workers.dev")!

    // MARK: Laden

    func start(uid: String) async {
        guard self.uid != uid else { return }
        self.uid = uid
        let f = db.child("users/\(uid)/fin")
        f.keepSynced(true)
        let h = f.observe(.value, with: { [weak self] snap in
            let v = snap.value
            Task { @MainActor in self?.applyFin(v) }
        }, withCancel: { [weak self] _ in Task { @MainActor in self?.loaded = true } })
        handles.append((f, h))
        // manuelle Ausgaben und eigene Kategorien liegen im gemeinsamen Budget-Bereich
        if let sid = (try? await db.child("users/\(uid)/spaces/budget").getData())?.value as? String {
            budgetSid = sid
            let e = db.child("spaces/\(sid)/expenses")
            handles.append((e, e.observe(.value, with: { [weak self] snap in
                let v = snap.value
                Task { @MainActor in self?.applyManual(v) }
            })))
            let rc = db.child("spaces/\(sid)/recurring")
            handles.append((rc, rc.observe(.value, with: { [weak self] snap in
                let v = snap.value
                Task { @MainActor in self?.recurring = DB.dict(v).mapValues { DB.dict($0) } }
            })))
            let c = db.child("spaces/\(sid)/cats")
            handles.append((c, c.observe(.value, with: { [weak self] snap in
                let v = snap.value
                Task { @MainActor in self?.customCats = DB.dict(v).values.compactMap { $0 as? String }; self?.rebuild() }
            })))
        }
    }

    private func applyFin(_ raw: Any?) {
        let v = DB.dict(raw)
        accounts = Dictionary(uniqueKeysWithValues: DB.dict(v["accounts"]).compactMap { k, x in BankAccount.parse(k, x).map { (k, $0) } })
        rawTx = Dictionary(uniqueKeysWithValues: DB.dict(v["tx"]).compactMap { k, x in Transaction.parse(k, x).map { (k, $0) } })
        rules = DB.dict(v["rules"]).compactMapValues { $0 as? String }
        budgets = DB.dict(v["budgets"]).mapValues { Int(DB.num($0)) }.filter { $0.value > 0 }
        contractMeta = DB.dict(v["contracts"]).mapValues { DB.dict($0) }
        eb = DB.dict(v["eb"]).mapValues { DB.dict($0) }
        alias = DB.dict(v["alias"]).compactMapValues { $0 as? String }
        aicat = DB.dict(v["aicat"]).compactMapValues { $0 as? String }
        adj = Dictionary(uniqueKeysWithValues: DB.dict(v["adj"]).compactMap { k, x in BudgetAdjustment.parse(k, x).map { (k, $0) } })
        let meta = DB.dict(v["meta"])
        salaryManual = Int(DB.num(meta["salaryAmt"]))
        periodDay = min(28, max(1, Int(DB.num(meta["periodDay"])) == 0 ? 1 : Int(DB.num(meta["periodDay"]))))
        periodSince = meta["periodSince"] as? String
        // vor dieser Version umgestellt: ersten Zeitraum ab dem 1. des Monats rechnen
        if periodDay > 1 && periodSince == nil {
            let s = Self.periodStart(day: periodDay)
            let first = Gym.iso(Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: s))!)
            periodSince = first
            fin.child("meta/periodSince").put(first)
        }
        salaryShift = (meta["salaryShift"] as? Bool) != false
        ppKeep = Set(DB.dict(meta["ppKeep"]).filter { ($0.value as? Bool) == true }.map(\.key))
        extraIncome = DB.dict(meta["extraInc"]).compactMap { k, x in
            let e = DB.dict(x); let a = Int(DB.num(e["a"]))
            guard a > 0 else { return nil }
            return ExtraIncome(id: k, n: e["n"] as? String ?? "Einnahme", a: a, monthly: (e["m"] as? Bool) ?? false, period: e["p"] as? String)
        }
        lastSyncAt = DB.num(DB.dict(meta["lastSync"])["at"])
        loaded = true
        rebuild()
    }

    private func applyManual(_ raw: Any?) {
        var out: [String: Transaction] = [:]
        for (id, x) in DB.dict(raw) {
            let e = DB.dict(x); let a = Int(DB.num(e["amount"]))
            guard a != 0, let d = e["date"] as? String else { continue }
            let cat = e["cat"] as? String
            out["m_" + id] = Transaction(id: "m_" + id, acc: nil, date: d, amount: -a, name: (e["title"] as? String) ?? cat ?? "Ausgabe",
                                         text: "", cat: cat, catSrc: "me", ex: false, pending: false, src: "manual")
        }
        manual = out
        rebuild()
    }

    /// Ziehen zum Aktualisieren: Stand direkt vom Server holen (nicht aus dem Zwischenspeicher), dann die Bank abfragen
    func refresh() async {
        if let snap = try? await fin.getData() { applyFin(snap.value) }
        if !eb.isEmpty { await sync(manual: true) }
        else { message = "Aktualisiert. Neuester Umsatz: \(newestText)." }
    }

    var newestDate: String? { allTx.map(\.date).max() }
    var newestText: String { newestDate.map { Gym.date($0).formatted(.dateTime.day().month().year()) } ?? "keiner" }

    // MARK: Kategorien (wie budget.html)

    var catList: [String] { BudgetCats.base + customCats.filter { !BudgetCats.base.contains($0) } }

    /// iOS-Systemfarbe je Kategorie
    func tint(_ c: String) -> Color {
        if let s = BudgetCats.style[c] { return s.color }
        let l = customCats, i = l.firstIndex(of: c) ?? 0
        return BudgetCats.extraColors[i % BudgetCats.extraColors.count]
    }

    /// SF-Symbol je Kategorie
    func symbol(_ c: String) -> String { BudgetCats.style[c]?.symbol ?? "tag.fill" }

    private static let star = RX(#"\*\s*(.+)$"#)
    private static let purchase = RX(#"(?:ihr einkauf bei|einkauf bei|purchase at|zahlung an)\s+([^,.;]+)"#)
    private static let ownName = RX(#"^[A-ZÄÖÜ .\-]+$"#, ci: false)
    private static let c1 = RX(#"sagt danke|vielen dank|danke|kartenzahlung|girocard|ec[- ]?karte|kartenumsatz|lastschrift|sepa|folgenr\.?|verfalld\.?|ref\.?|mandat|end-to-end|\bnotprovided\b"#)
    private static let c2 = RX(#"\b\d{1,2}[./-]\d{1,2}([./-]\d{2,4})?\b|\b\d{1,2}:\d{2}\b"#, ci: false)
    private static let c3 = RX(#"\b[a-z]*\d[a-z\d]*\b"#)
    private static let c4 = RX(#"\b(gmbh|ag|se|kg|ug|ohg|e\.?\s?k\.?|co|eu|sarl|s\.?a\.?r\.?l\.?|et cie|s\.?c\.?a\.?|ltd|inc|b\.?v\.?|mbh)\b"#)
    private static let c5 = RX(#"[*#/\\,;:|·_]+"#, ci: false)
    private static let c6 = RX(#"(^|\s)[.\-]+(?=\s|$)"#, ci: false)
    private static let ws = RX(#"\s+"#, ci: false)
    private static let keyRX = RX(#"[^a-z0-9äöüß]+"#, ci: false)
    private static let norm1 = RX(#"[0-9*#/\\.,:;_-]+"#, ci: false)
    private static let norm2 = RX(#"\b(gmbh|ag|se|kg|ug|co|eu|de|sarl|s a r l|ltd|inc|bv|online|services?|payments?|europe|zahlung|lastschrift|sagt danke)\b"#, ci: false)
    private static let salaryRX = RX(#"\b(gehalt|lohn|bezüge|bezuege|salary|besoldung)\b"#)
    private static let transferIn = RX(#"\bumbuchung\b|\bübertrag\b|eigenes konto"#)
    private static let refundRX = RX(#"(rück|rueck)erstatt|erstattung|refund|retoure|storno|(rück|rueck)buchung|(rück|rueck)zahlung|gutschrift"#)
    private static let bankRX = RX(#"bank|sparkasse|volksbank|raiffeisen|ing\b|dkb|comdirect|commerzbank|postbank|n26|abschluss|entgelt|zins"#)
    private static let transferOut = RX(#"\bumbuchung\b|\bübertrag\b|eigene[sn]? konto"#)

    private func cleanText(_ str: String, _ acc: BankAccount?) -> String {
        var x = str
        if let n = acc?.name, Self.ownName.test(n) { x = x.components(separatedBy: n).joined(separator: " ") }
        x = Self.c1.replace(x, with: " ")
        x = Self.c2.replace(x, with: " ")
        x = Self.c3.replace(x, with: " ")
        x = Self.c4.replace(x, with: " ")
        x = Self.c5.replace(x, with: " ")
        x = Self.c6.replace(x, with: " ")
        return Self.ws.replace(x, with: " ").trimmingCharacters(in: .whitespaces)
    }

    private func titleCase(_ w: String) -> String {
        if w.count <= 2 { return w }
        return w == w.uppercased() ? String(w.prefix(1)) + w.dropFirst().lowercased() : w
    }

    private func words(_ s: String, _ n: Int) -> String {
        s.split(separator: " ").prefix(n).map { titleCase(String($0)) }.joined(separator: " ")
    }

    private func merchant(_ t: Transaction) -> (label: String, cat: String?, proc: Bool) {
        if let c = merchCache[t.id] { return c }
        let acc = t.acc.flatMap { accounts[$0] }
        let proc = t.name.isEmpty || BudgetRules.proc.test(t.name)
        var res: (label: String, cat: String?, proc: Bool)
        if let br = BudgetRules.brands.first(where: { $0.0.test(t.name) }) ?? (proc ? BudgetRules.brands.first(where: { $0.0.test(t.text) }) : nil) {
            res = (br.1, br.2, proc)
        } else {
            var label: String?
            if proc {
                if let st = Self.star.first(t.name, group: 1) {
                    let w = words(cleanText(st, acc), 4); if !w.isEmpty { label = w }
                }
                if label == nil {
                    let src = Self.purchase.first(t.text, group: 1) ?? t.text
                    let w = words(cleanText(src, acc), 3); if !w.isEmpty { label = w }
                }
            }
            if label == nil {
                let w = words(cleanText(t.name, acc), 4)
                label = w.isEmpty ? (t.name.isEmpty ? "Unbekannt" : t.name) : w
            }
            res = (label ?? "Unbekannt", nil, proc)
        }
        merchCache[t.id] = res
        return res
    }

    private func keyOf(_ l: String) -> String {
        String(Self.keyRX.replace(l.lowercased(), with: " ").trimmingCharacters(in: .whitespaces).prefix(60))
    }

    func merchKey(_ t: Transaction) -> String { keyOf(merchant(t).label) }

    private func normName(_ n: String) -> String {
        let a = Self.norm1.replace(n.lowercased(), with: " ")
        let b = Self.ws.replace(Self.norm2.replace(a, with: " "), with: " ").trimmingCharacters(in: .whitespaces)
        return b.split(separator: " ").prefix(3).joined(separator: " ")
    }

    private func autoCat(_ t: Transaction) -> String? {
        let k = keys[t.id] ?? merchKey(t)
        if !k.isEmpty, let r = rules[k] { return r }
        let old = normName(t.name).replacingOccurrences(of: #"[.#$\[\]/]"#, with: "_", options: .regularExpression)
        if !old.isEmpty, let r = rules[old], !BudgetRules.proc.test(t.name) { return r }
        let s = t.name + " " + t.text
        if t.amount > 0 {
            if Self.salaryRX.test(s) { return "Gehalt" }
            if Self.transferIn.test(s) { return "Umbuchung" }
            if Self.refundRX.test(s) { return BudgetCats.back }
            let mb = merchant(t); if let c = mb.cat, c != BudgetCats.save { return BudgetCats.back }
            return "Sonstige Einnahmen"
        }
        if BudgetRules.fee.test(s) && !BudgetRules.proc.test(t.name) && (t.name.isEmpty || Self.bankRX.test(s)) { return "Gebühren & Zinsen" }
        let m = merchant(t)
        if let c = m.cat { return c }
        for (re, c) in BudgetRules.keys where re.test(m.proc ? t.text : s) { return c }
        if Self.transferOut.test(s) { return "Umbuchung" }
        if let ai = aicat[k], ai != "Sonstiges" { return ai }
        return nil
    }

    private func baseCat(_ t: Transaction) -> String? {
        if let c = t.cat, t.catSrc != "ai" { return c }
        return autoCat(t)
    }

    /// Alles neu berechnen: Händler, PayPal-Paare, Kategorien
    private func rebuild() {
        merchCache = [:]
        allTx = Array(rawTx.values) + Array(manual.values)
        var k: [String: String] = [:], l: [String: String] = [:]
        for t in allTx {
            if t.src == "manual" { l[t.id] = t.name; k[t.id] = keyOf(t.name); continue }
            let key = merchKey(t); k[t.id] = key
            l[t.id] = alias[key] ?? merchant(t).label
        }
        keys = k; labels = l
        buildPayPal()
        var c: [String: String] = [:]
        for t in allTx {
            if ppMap[t.id] != nil { c[t.id] = "Umbuchung"; continue }
            if let b = baseCat(t) { c[t.id] = b; continue }
            if let bankID = ppFrom[t.id], let b = rawTx[bankID], let bc = baseCat(b) { c[t.id] = bc; continue }
            c[t.id] = "Sonstiges"
        }
        cats = c
    }

    func cat(_ t: Transaction) -> String { cats[t.id] ?? "Sonstiges" }
    func label(_ t: Transaction) -> String { labels[t.id] ?? t.name }

    /// PayPal nicht doppelt zählen (wie ppPairs() auf der Webseite)
    private func buildPayPal() {
        var map: [String: (with: String?, kind: String)] = [:], from: [String: String] = [:]
        let ppNameRX = RX("paypal")
        var pp: [Transaction] = [], bank: [Transaction] = []
        for t in rawTx.values where !t.ex {
            guard let a = t.acc.flatMap({ accounts[$0] }) else { continue }
            if a.isPayPal { pp.append(t) } else if ppNameRX.test(t.name) || (t.name.isEmpty && ppNameRX.test(t.text)) { bank.append(t) }
        }
        if !pp.isEmpty && !bank.isEmpty {
            let day: (String) -> Int = { Gym.dayNumber($0) }
            var used = Set<String>()
            let ppOut = pp.filter { $0.amount < 0 }, ppIn = pp.filter { $0.amount > 0 }
            for b in bank.filter({ $0.amount < 0 && !ppKeep.contains($0.id) }).sorted(by: { $0.date < $1.date }) {
                let lb = keys[b.id] ?? "", db = day(b.date)
                var best: Transaction?, score = Int.max
                for p in ppOut where !used.contains(p.id) {
                    let dd = abs(day(p.date) - db)
                    if dd > 5 || -p.amount < -b.amount - 1 { continue }
                    let lp = keys[p.id] ?? "", w1 = String(lb.split(separator: " ").first ?? ""), w2 = String(lp.split(separator: " ").first ?? "")
                    let same = !lb.isEmpty && lb != "paypal" && (lp == lb || (w1.count >= 4 && w1 == w2) || (lb.count >= 5 && lp.contains(lb)) || (lp.count >= 5 && lb.contains(lp)))
                    let exact = p.amount == b.amount
                    if !same && !exact { continue }
                    let sc = dd + (exact ? 0 : 1) + (same ? 0 : 2)
                    if sc < score { score = sc; best = p }
                }
                if let best { used.insert(best.id); map[b.id] = (best.id, "bank"); from[best.id] = b.id }
            }
            let topup = RX(#"bankgutschrift|bankkonto|bank account|aufladung|top.?up|einzahlung|transfer from|allgemeine abbuchung|ausgleich|von bank"#)
            for p in ppIn where !ppKeep.contains(p.id) {
                let m = bank.first { $0.amount == -p.amount && abs(day($0.date) - day(p.date)) <= 5 }
                if m != nil || topup.test(p.name + " " + p.text) { map[p.id] = (m?.id, "topup") }
            }
            for b in bank where b.amount > 0 && !ppKeep.contains(b.id) {
                if let m = ppOut.first(where: { !used.contains($0.id) && $0.amount == -b.amount && abs(day($0.date) - day(b.date)) <= 5 }) {
                    used.insert(m.id); map[b.id] = (m.id, "payout"); map[m.id] = (b.id, "payout")
                }
            }
        }
        ppMap = map; ppFrom = from
    }

    // MARK: Auswertungen

    func effKey(_ t: Transaction) -> String {
        let k = String(t.date.prefix(7))
        guard salaryShift, t.amount > 0, (Int(t.date.suffix(2)) ?? 0) >= 20, cat(t) == "Gehalt" else { return k }
        let p = k.split(separator: "-").compactMap { Int($0) }
        guard p.count == 2 else { return k }
        return p[1] == 12 ? String(format: "%04d-01", p[0] + 1) : String(format: "%04d-%02d", p[0], p[1] + 1)
    }

    func totals(year: Int, month: Int) -> MonthTotals {
        let key = String(format: "%04d-%02d", year, month)
        var r = MonthTotals()
        for t in allTx where !t.ex && effKey(t) == key {
            let c = cat(t)
            if BudgetCats.noSpend.contains(c) { continue }
            if t.amount > 0 { if c == BudgetCats.back { r.back += t.amount } else { r.inc += t.amount }; continue }
            if c == BudgetCats.save { continue }
            r.out += -t.amount
            r.byCat[c, default: 0] += -t.amount
            r.txByCat[c, default: []].append(t)
        }
        return r
    }

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    func nextPayday() -> (date: Date, amount: Int)? {
        let sal = allTx.filter { $0.amount > 0 && cat($0) == "Gehalt" }.sorted { $0.date > $1.date }.prefix(4)
        guard let first = sal.first else { return nil }
        let days = sal.map { Int($0.date.suffix(2)) ?? 1 }.sorted(), day = days[days.count / 2]
        let cal = Calendar.current, t = today
        func on(_ monthOffset: Int) -> Date {
            let base = cal.date(byAdding: .month, value: monthOffset, to: cal.date(from: cal.dateComponents([.year, .month], from: t))!)!
            let n = cal.range(of: .day, in: .month, for: base)?.count ?? 28
            return cal.date(byAdding: .day, value: min(day, n) - 1, to: base)!
        }
        var d = on(0)
        if d <= t || (first.date.prefix(7) == Gym.iso(t).prefix(7) && (Int(first.date.suffix(2)) ?? 0) >= day - 3) { d = on(1) }
        let n = min(3, sal.count)
        return (d, sal.prefix(3).reduce(0) { $0 + $1.amount } / n)
    }

    func salaryInfo() -> SalaryInfo {
        let t0 = today, todayS = Gym.iso(t0), cal = Calendar.current
        let sal = allTx.filter { $0.amount > 0 && !$0.ex && cat($0) == "Gehalt" && $0.date <= todayS }.sorted { $0.date > $1.date }
        let last = sal.first.flatMap { s in t0.timeIntervalSince(Gym.date(s.date)) / 86400 <= 40 ? s : nil }
        let nx = nextPayday()
        // Zeitraum vom Stichtag bis zum Tag davor im nächsten Monat (Standard: ganzer Kalendermonat)
        let s0 = Self.periodStart(day: periodDay)
        var start = Gym.iso(s0)
        let end = Gym.iso(cal.date(byAdding: .day, value: -1, to: cal.date(byAdding: .month, value: 1, to: s0)!)!)
        // nach dem Umstellen des Starttags schließt der erste Zeitraum an den alten an
        let prev = Gym.iso(cal.date(byAdding: .month, value: -1, to: s0)!)
        if let since = periodSince, since < start, since >= prev { start = since }
        let auto = last?.amount ?? nx?.amount ?? 0
        let daysLeft = max(1, Int((Gym.date(end).timeIntervalSince(t0) / 86400).rounded()) + 1)
        return SalaryInfo(start: start, end: end, amount: salaryManual > 0 ? salaryManual : auto, fromSalary: last != nil,
                          manual: salaryManual > 0, daysLeft: daysLeft)
    }

    func adjustments(_ si: SalaryInfo, cat: String? = nil) -> [BudgetAdjustment] {
        adj.values.filter { $0.d >= si.start && $0.d <= si.end && (cat == nil || $0.cat == cat) }.sorted { $0.d > $1.d }
    }

    func periodSpend(_ si: SalaryInfo) -> [String: Int] {
        var by: [String: Int] = [:]
        for t in allTx where !t.ex && t.amount < 0 && t.date >= si.start && t.date <= si.end {
            let c = cat(t)
            if BudgetCats.noSpend.contains(c) || BudgetCats.income.contains(c) { continue }
            by[c, default: 0] += -t.amount
        }
        for a in adjustments(si) { by[a.cat] = max(0, (by[a.cat] ?? 0) - a.a) }
        return by
    }

    func income(_ si: SalaryInfo) -> (extra: [ExtraIncome], total: Int) {
        let ex = extraIncome.filter { $0.monthly || $0.period == si.start }
        return (ex, si.amount + ex.reduce(0) { $0 + $1.a })
    }

    func periodTx(_ si: SalaryInfo, cat c: String) -> [Transaction] {
        allTx.filter { !$0.ex && $0.amount < 0 && $0.date >= si.start && $0.date <= si.end && cat($0) == c }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.amount < $1.amount }
    }

    private static let rhythms: [(String, Double, Double, String, Int)] = [
        ("week", 6, 8, "wöchentlich", 0), ("month", 26, 35, "monatlich", 1), ("quarter", 84, 97, "vierteljährlich", 3),
        ("half", 170, 195, "halbjährlich", 6), ("year", 350, 380, "jährlich", 12)]
    private static let perMonthFactor: [String: Double] = ["week": 52.0 / 12, "month": 1, "quarter": 1.0 / 3, "half": 1.0 / 6, "year": 1.0 / 12]

    func contracts() -> [Contract] {
        var groups: [String: [Transaction]] = [:]
        for t in allTx where t.amount < 0 && !t.ex && t.src != "manual" {
            if BudgetCats.noSpend.contains(cat(t)) { continue }
            let k = keys[t.id] ?? ""; if k.isEmpty { continue }
            groups[k, default: []].append(t)
        }
        var out: [Contract] = []
        let t0 = today, cal = Calendar.current
        for (k, raw) in groups where raw.count >= 2 {
            let list = raw.sorted { $0.date < $1.date }
            let amts = list.map { -$0.amount }.sorted(), med = Double(amts[amts.count / 2])
            let daily = ["Lebensmittel", "Essen gehen", "Shopping", "Bargeld"].contains(cat(list.last!))
            let same = list.filter { abs(Double(-$0.amount) - med) <= (daily ? max(1, med * 0.01) : max(100, med * 0.2)) }
            if same.count < 2 { continue }
            if daily && Double(same.count) < Double(list.count) * 0.8 { continue }
            var gaps: [Double] = []
            for i in 1..<same.count { gaps.append(Gym.date(same[i].date).timeIntervalSince(Gym.date(same[i - 1].date)) / 86400) }
            let g = gaps.sorted()[gaps.count / 2]
            guard let r = Self.rhythms.first(where: { g >= $0.1 && g <= $0.2 }) else { continue }
            if r.0 == "week" && same.count < 4 { continue }
            let last = Gym.date(same.last!.date)
            let next = r.0 == "week" ? cal.date(byAdding: .day, value: 7, to: last)! : cal.date(byAdding: .month, value: r.4, to: last)!
            let kk = k.replacingOccurrences(of: #"[.#$\[\]/]"#, with: "_", options: .regularExpression)
            if (contractMeta[kk]?["hidden"] as? Bool) == true { continue }
            if t0.timeIntervalSince(last) / 86400 > g * 1.8 { continue }
            let tail = same.suffix(3)
            let avg = Int((Double(tail.reduce(0) { $0 - $1.amount }) / Double(tail.count)).rounded())
            let a1 = -same[same.count - 1].amount, a0 = same.count > 1 ? -same[same.count - 2].amount : a1
            let raise: (from: Int, to: Int)? = (a1 - a0 >= 50 && Double(a1) > Double(a0) * 1.02) ? (a0, a1) : nil
            let first = Gym.date(same[0].date)
            let isNew = t0.timeIntervalSince(first) / 86400 <= g * 2.2 && same.count <= 3
            let base = raise?.to ?? avg
            out.append(Contract(key: kk, name: label(same.last!), cat: cat(same.last!), rhythm: r.0, rhythmLabel: r.3, avg: base,
                                perMonth: Int((Double(base) * (Self.perMonthFactor[r.0] ?? 1)).rounded()), last: last, next: next,
                                txs: Array(same.reversed()), raise: raise, isNew: isNew, manualID: nil))
        }
        // von Hand eingetragene Verträge (spaces/<budget>/recurring, wie auf der Webseite)
        for (id, r) in recurring {
            guard (r["kind"] as? String) != "income", let start = r["start"] as? String else { continue }
            let every = r["every"] as? String ?? "month", amount = Int(DB.num(r["amount"]))
            let next = Self.nextDate(start: start, every: every) ?? Gym.date(start)
            let label = ["week": "wöchentlich", "month": "monatlich", "quarter": "vierteljährlich", "year": "jährlich"][every] ?? "monatlich"
            out.append(Contract(key: "rec_" + id, name: r["name"] as? String ?? "Vertrag", cat: r["cat"] as? String ?? "Sonstiges", rhythm: every,
                                rhythmLabel: label, avg: amount, perMonth: Int((Double(amount) * (Self.perMonthFactor[every] ?? 1)).rounded()),
                                last: Gym.date(start), next: next, txs: [], raise: nil, isNew: false, manualID: id))
        }
        return out.sorted { $0.perMonth > $1.perMonth }
    }

    /// nächste Fälligkeit ab heute (wie nextDate() auf der Webseite)
    static func nextDate(start: String, every: String) -> Date? {
        let cal = Calendar.current, t = cal.startOfDay(for: Date()), s = Gym.date(start)
        if every == "week" {
            var d = s
            while d < t { d = cal.date(byAdding: .day, value: 7, to: d)! }
            return d
        }
        let step = every == "year" ? 12 : every == "quarter" ? 3 : 1
        for i in 0..<60 {
            guard let d = cal.date(byAdding: .month, value: i * step, to: s) else { continue }
            if d >= t { return d }
        }
        return nil
    }

    func saveRecurring(id: String?, name: String, cents: Int, kind: String, every: String, start: String, cat: String) {
        guard let sid = budgetSid else { return }
        let id = id ?? (String(Int(Date().timeIntervalSince1970 * 1000), radix: 36) + DB.randomID(4).lowercased())
        db.child("spaces/\(sid)/recurring/\(id)").put(["amount": cents, "name": String(name.prefix(60)), "kind": kind, "every": every, "start": start, "cat": cat])
    }

    func deleteRecurring(_ id: String) {
        guard let sid = budgetSid else { return }
        db.child("spaces/\(sid)/recurring/\(id)").drop()
    }

    func pairInfo(_ t: Transaction) -> (with: Transaction?, kind: String)? {
        guard let p = ppMap[t.id] else { return nil }
        return (p.with.flatMap { rawTx[$0] }, p.kind)
    }

    // MARK: Schreiben

    private func safeKey(_ s: String) -> String { s.replacingOccurrences(of: #"[.#$\[\]/]"#, with: "_", options: .regularExpression) }

    private func rememberMerchant(_ k: String, cat: String?, name: String?) {
        guard !k.isEmpty else { return }
        if let cat {
            rules[k] = cat; fin.child("rules/\(k)").put(cat)
            var upd: [String: Any] = [:]
            for (id, t) in rawTx where keys[id] == k && t.catSrc != "me" && t.cat != nil {
                rawTx[id]?.cat = nil; rawTx[id]?.catSrc = nil
                upd["\(id)/cat"] = NSNull(); upd["\(id)/catSrc"] = NSNull()
            }
            if !upd.isEmpty { fin.child("tx").merge(upd) }
        }
        if let name {
            let def = rawTx.values.first { keys[$0.id] == k }.map { merchant($0).label } ?? ""
            let v: String? = (!name.isEmpty && name != def) ? name : nil
            if let v { alias[k] = v } else { alias[k] = nil }
            fin.child("alias/\(k)").put(v)
        }
    }

    func saveTx(_ t: Transaction, cat: String, exclude: Bool, remember: Bool, name: String) {
        guard t.src != "manual", rawTx[t.id] != nil else { return }
        let key = keys[t.id] ?? "", old = label(t)
        let newName: String? = (!name.isEmpty && name != old) ? String(name.prefix(40)) : nil
        if ppMap[t.id] != nil {
            if cat == "Umbuchung" {
                if exclude != t.ex { rawTx[t.id]?.ex = exclude; fin.child("tx/\(t.id)/ex").put(exclude ? true : nil) }
                if let newName { rememberMerchant(key, cat: nil, name: newName) }
                rebuild(); return
            }
            setKeep(t, true)
            rawTx[t.id]?.cat = cat; rawTx[t.id]?.catSrc = "me"; rawTx[t.id]?.ex = exclude
            fin.child("tx/\(t.id)").merge(["cat": cat, "catSrc": "me", "ex": exclude ? true as Any : NSNull()])
            rebuild(); return
        }
        if remember {
            rememberMerchant(key, cat: cat, name: newName ?? (alias[key] != nil ? alias[key] : nil))
            rawTx[t.id]?.cat = nil; rawTx[t.id]?.catSrc = nil; rawTx[t.id]?.ex = exclude
            fin.child("tx/\(t.id)").merge(["cat": NSNull(), "catSrc": NSNull(), "ex": exclude ? true as Any : NSNull()])
        } else {
            rawTx[t.id]?.cat = cat; rawTx[t.id]?.catSrc = "me"; rawTx[t.id]?.ex = exclude
            fin.child("tx/\(t.id)").merge(["cat": cat, "catSrc": "me", "ex": exclude ? true as Any : NSNull()])
            if let newName { rememberMerchant(key, cat: nil, name: newName) }
        }
        rebuild()
    }

    func setKeep(_ t: Transaction, _ on: Bool) {
        if on { ppKeep.insert(t.id) } else { ppKeep.remove(t.id) }
        fin.child("meta/ppKeep/\(t.id)").put(on ? true : nil)
        rebuild()
    }

    func setBudget(_ cat: String, cents: Int?) {
        let k = safeKey(cat)
        if let cents, cents > 0 { budgets[cat] = cents; fin.child("budgets/\(k)").put(cents) }
        else { budgets[cat] = nil; fin.child("budgets/\(k)").drop() }
    }

    func saveAdjustment(id: String?, cat: String, cents: Int, note: String?, date: String, tx: String?) {
        let id = id ?? ("a" + String(Int(Date().timeIntervalSince1970 * 1000), radix: 36))
        var v: [String: Any] = ["cat": cat, "a": cents, "d": date, "at": DB.nowMs]
        if let note, !note.isEmpty { v["n"] = String(note.prefix(60)) }
        if let tx { v["tx"] = tx }
        if let a = BudgetAdjustment.parse(id, v) { adj[id] = a }
        fin.child("adj/\(id)").put(v)
    }

    func deleteAdjustment(_ a: BudgetAdjustment) {
        adj[a.id] = nil
        fin.child("adj/\(a.id)").drop()
    }

    func hideContract(_ c: Contract) {
        contractMeta[c.key, default: [:]]["hidden"] = true
        fin.child("contracts/\(c.key)/hidden").put(true)
    }

    // MARK: Bank-Abruf über den Helfer (fin-sync)

    private func api(_ body: [String: Any]) async throws -> [String: Any] {
        guard let user = Auth.auth().currentUser else { throw NSError(domain: "Ours", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bitte melde dich an."]) }
        let token = try await user.getIDToken()
        var req = URLRequest(url: Self.worker)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("https://nkllasbus.github.io", forHTTPHeaderField: "Origin")
        var b = body; b["token"] = token
        req.httpBody = try JSONSerialization.data(withJSONObject: b)
        req.timeoutInterval = 90
        let (data, resp) = try await URLSession.shared.data(for: req)
        let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let h = resp as? HTTPURLResponse, h.statusCode >= 400 {
            throw NSError(domain: "Ours", code: h.statusCode, userInfo: [NSLocalizedDescriptionKey: d["error"] as? String ?? "Der Helfer hat nicht geantwortet."])
        }
        return d
    }

    private static func hashTx(date: String, amount: Int, name: String, text: String) -> String {
        let s = [date, String(amount), name, text].joined(separator: "|")
        var h: Int32 = 0
        for u in s.utf16 { h = h &* 31 &+ Int32(u) }
        return "h" + String(UInt32(bitPattern: h), radix: 36)
    }

    func sync(manual: Bool) async {
        guard !syncing, !eb.isEmpty else { return }
        syncing = true; message = nil
        defer { syncing = false }
        var nNew = 0, got = 0, newest = "", pend = 0, errs: [String] = []
        for (sk, s) in eb {
            let accs = accounts.values.filter { $0.session == sk }
            if accs.isEmpty { continue }
            let last = accs.map(\.syncAt).min() ?? 0
            let from = Gym.iso(Date(timeIntervalSince1970: (last > 0 ? last - 7 * 864e5 : DB.nowMs - 365 * 864e5) / 1000))
            do {
                let d = try await api(["mode": "fin-sync", "session": s["session"] ?? "", "ticket": s["ticket"] ?? "",
                                       "accounts": accs.compactMap(\.ebUid), "from": from])
                if let vu = d["validUntil"] as? String, vu != s["validUntil"] as? String { fin.child("eb/\(sk)/validUntil").put(vu) }
                for r in (d["accounts"] as? [[String: Any]]) ?? [] {
                    guard let a = accs.first(where: { $0.ebUid == r["uid"] as? String }) else { continue }
                    if let e = r["error"] as? String, !e.isEmpty { errs.append("\(a.name): \(e)"); continue }
                    var upd: [String: Any] = [:]
                    if r["balance"] != nil, !(r["balance"] is NSNull) { upd["accounts/\(a.id)/balance"] = Int(DB.num(r["balance"])) }
                    upd["accounts/\(a.id)/syncAt"] = DB.nowMs
                    var seen = Set<String>()
                    let list = (r["tx"] as? [[String: Any]]) ?? []
                    got += list.count
                    for t in list {
                        guard let date = t["date"] as? String else { continue }
                        if date > newest { newest = date }
                        if (t["pending"] as? Bool) == true { pend += 1 }
                        let amount = Int(DB.num(t["amount"])), name = t["name"] as? String ?? "", text = t["text"] as? String ?? ""
                        let rawID = (t["id"] as? String) ?? Self.hashTx(date: date, amount: amount, name: name, text: text)
                        let id = String((a.id + "_" + rawID).replacingOccurrences(of: #"[.#$\[\]/\s]"#, with: "_", options: .regularExpression).prefix(120))
                        if rawTx[id] == nil { nNew += 1 }
                        let pending = (t["pending"] as? Bool) == true
                        let base: [String: Any] = ["acc": a.id, "date": date, "amount": amount, "name": name, "text": text,
                                                   "pending": pending ? true as Any : NSNull(), "src": "eb"]
                        for (k, v) in base { upd["tx/\(id)/\(k)"] = v }
                        seen.insert(id)
                    }
                    if (r["pend"] as? Bool) == true {
                        for (id, t) in rawTx where t.acc == a.id && t.pending && t.src == "eb" && t.date >= from && !seen.contains(id) { upd["tx/\(id)"] = NSNull() }
                    }
                    _ = try? await fin.updateChildValues(upd)
                }
            } catch {
                errs.append(error.localizedDescription)
            }
        }
        fin.child("meta/lastSync").put(["at": DB.nowMs, "got": got, "newest": newest.isEmpty ? NSNull() as Any : newest])
        let info = got > 0 ? " Die Bank hat \(got) Umsätze geschickt, der neueste ist vom \(Gym.date(newest).formatted(.dateTime.day().month().year()))\(pend > 0 ? " (\(pend) vorgemerkt)" : "")."
                           : " Die Bank hat keine Umsätze geschickt."
        if let e = errs.first { message = e }
        else if manual { message = (nNew > 0 ? "\(nNew) neue Umsätze geladen." : "Keine neuen Umsätze.") + info }
        await categorizeNew()
    }

    /// Unbekannte Händler einmal von Claude zuordnen lassen (nur sichere Antworten)
    private func categorizeNew() async {
        var seen = Set<String>(), todo: [(String, Transaction)] = []
        for t in allTx where t.amount < 0 && !t.ex && t.src != "manual" && (t.cat == nil || t.catSrc == "ai") {
            let k = keys[t.id] ?? ""
            if k.isEmpty || seen.contains(k) || aicat[k] != nil { continue }
            seen.insert(k)
            if autoCat(t) != nil { continue }
            todo.append((k, t)); if todo.count >= 60 { break }
        }
        guard !todo.isEmpty else { return }
        let cl = catList.filter { !BudgetCats.income.contains($0) && $0 != "Umbuchung" }
        guard let d = try? await api(["mode": "fin-cat", "cats": cl, "items": todo.map { k, t in
            ["name": label(t), "orig": t.name, "text": cleanText(t.text, t.acc.flatMap { accounts[$0] }), "amount": t.amount] as [String: Any] }]),
              let sure = d["sure"] as? [Bool] else { return }
        let res = (d["cats"] as? [String]) ?? []
        var upd: [String: Any] = [:]
        for (i, (k, _)) in todo.enumerated() {
            let c = i < res.count ? res[i] : "Sonstiges", ok = i < sure.count && sure[i] && c != "Sonstiges"
            upd[k] = ok ? c : "Sonstiges"
        }
        fin.child("aicat").merge(upd)
    }

    // MARK: Ausgaben von Hand, Gehalt, weitere Einnahmen

    func saveExpense(id: String?, cents: Int, title: String, cat: String, date: String) {
        guard let sid = budgetSid else { return }
        let id = id.map { String($0.dropFirst(2)) } ?? (String(Int(Date().timeIntervalSince1970 * 1000), radix: 36) + DB.randomID(4).lowercased())
        db.child("spaces/\(sid)/expenses/\(id)").put(["amount": cents, "title": String(title.prefix(60)), "cat": cat, "date": date, "createdAt": DB.nowMs])
    }

    func deleteExpense(_ t: Transaction) {
        guard let sid = budgetSid, t.src == "manual" else { return }
        db.child("spaces/\(sid)/expenses/\(t.id.dropFirst(2))").drop()
    }

    func autoSalary() -> Int {
        let si = salaryInfo()
        if si.manual { let saved = salaryManual; salaryManual = 0; let a = salaryInfo().amount; salaryManual = saved; return a }
        return si.amount
    }

    static func periodStart(day: Int) -> Date {
        let cal = Calendar.current, t0 = cal.startOfDay(for: Date())
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: t0))!
        var s0 = cal.date(byAdding: .day, value: day - 1, to: monthStart)!
        if t0 < s0 { s0 = cal.date(byAdding: .month, value: -1, to: s0)! }
        return s0
    }

    func setPeriodDay(_ d: Int) {
        let v = min(28, max(1, d))
        guard v != periodDay else { return }
        let since = salaryInfo().start
        periodDay = v; periodSince = since
        fin.child("meta").merge(["periodDay": v == 1 ? NSNull() as Any : v, "periodSince": since])
    }

    func setSalary(_ cents: Int?) {
        salaryManual = cents ?? 0
        fin.child("meta/salaryAmt").put(cents.flatMap { $0 > 0 ? $0 : nil })
    }

    func saveIncome(id: String?, name: String, cents: Int, monthly: Bool) {
        let id = id ?? ("i" + String(Int(Date().timeIntervalSince1970 * 1000), radix: 36))
        var v: [String: Any] = ["n": name.isEmpty ? "Einnahme" : String(name.prefix(40)), "a": cents, "m": monthly]
        if !monthly { v["p"] = salaryInfo().start }
        fin.child("meta/extraInc/\(id)").put(v)
    }

    func deleteIncome(_ x: ExtraIncome) {
        fin.child("meta/extraInc/\(x.id)").drop()
    }

    // MARK: Bank verbinden (Enable Banking über den Helfer)

    struct BankOption: Identifiable, Hashable { var id: String { name }; let name: String; let country: String; let logo: String?; let maxDays: Int }
    struct PickedAccount: Identifiable, Hashable { var id: String { uid }; let uid: String; let iban: String?; let name: String; let product: String? }
    struct BankResult { let session: String; let ticket: String; let bank: String; let validUntil: String?; let accounts: [PickedAccount] }
    static let bankReturn = "https://nkllasbus.github.io/OursApp/budget.html"

    func banks() async throws -> [BankOption] {
        let d = try await api(["mode": "fin-banks", "country": "DE"])
        return ((d["banks"] as? [[String: Any]]) ?? []).compactMap { b in
            guard let n = b["name"] as? String else { return nil }
            return BankOption(name: n, country: b["country"] as? String ?? "DE", logo: b["logo"] as? String, maxDays: Int(DB.num(b["maxDays"])))
        }
    }

    /// Gibt die Anmeldeseite der Bank und den Prüfwert zurück
    func startBank(_ b: BankOption) async throws -> (url: URL, state: String) {
        let d = try await api(["mode": "fin-start", "bank": ["name": b.name, "country": b.country], "days": min(180, max(1, b.maxDays > 0 ? b.maxDays : 90)),
                               "redirect": Self.bankReturn])
        guard let s = d["url"] as? String, let url = URL(string: s), let state = d["state"] as? String else {
            throw NSError(domain: "Ours", code: 2, userInfo: [NSLocalizedDescriptionKey: "Die Bank hat keine Anmeldeseite geschickt."])
        }
        return (url, state)
    }

    func finishBank(code: String) async throws -> BankResult {
        let d = try await api(["mode": "fin-finish", "code": code])
        let accs = ((d["accounts"] as? [[String: Any]]) ?? []).compactMap { a -> PickedAccount? in
            guard let u = a["uid"] as? String else { return nil }
            return PickedAccount(uid: u, iban: a["iban"] as? String, name: a["name"] as? String ?? "Konto", product: a["product"] as? String)
        }
        guard let session = d["session"] as? String, let ticket = d["ticket"] as? String else {
            throw NSError(domain: "Ours", code: 3, userInfo: [NSLocalizedDescriptionKey: "Die Bankverbindung war unvollständig."])
        }
        return BankResult(session: session, ticket: ticket, bank: d["bank"] as? String ?? "", validUntil: d["validUntil"] as? String, accounts: accs)
    }

    func savePicked(_ r: BankResult, picked: Set<String>) async {
        let sk = safeKey(r.session)
        var s: [String: Any] = ["session": r.session, "ticket": r.ticket, "bank": r.bank, "accounts": Array(picked), "at": DB.nowMs]
        if let v = r.validUntil { s["validUntil"] = v }
        for (k, o) in eb where (o["bank"] as? String) == r.bank && k != sk { fin.child("eb/\(k)").drop(); eb[k] = nil }
        eb[sk] = s
        _ = try? await fin.child("eb/\(sk)").setValue(s)
        for a in r.accounts where picked.contains(a.uid) {
            let existing = accounts.values.first { $0.src == "eb" && a.iban != nil && $0.iban == a.iban }
            let id = existing?.id ?? String(safeKey("eb_" + (a.iban ?? a.uid)).replacingOccurrences(of: " ", with: "_").prefix(60))
            var acc: [String: Any] = ["name": existing?.name ?? (a.name.isEmpty ? (r.bank.isEmpty ? "Konto" : r.bank) : a.name), "bank": r.bank,
                                      "src": "eb", "kind": "bank", "session": sk, "ebUid": a.uid]
            if let iban = a.iban { acc["iban"] = iban }
            if let b = existing?.balance { acc["balance"] = b }
            if let t = existing?.syncAt, t > 0 { acc["syncAt"] = t }
            _ = try? await fin.child("accounts/\(id)").setValue(acc)
        }
        try? await Task.sleep(nanoseconds: 600_000_000)
        await sync(manual: true)
    }

    // MARK: CSV-Import (gleiche Erkennung wie die Webseite)

    struct CSVData {
        var head: [String]
        var body: [[String]]
        var map: [String: Int]     // date, amount, name, text → Spalte (-1 = keine)
        var paypal: Bool
        var accName: String
    }

    static func readCSV(_ data: Data, fileName: String) -> CSVData? {
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) ?? ""
        let lines = text.replacingOccurrences(of: "\u{FEFF}", with: "").components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { return nil }
        let sample = lines.prefix(30).joined(separator: "\n")
        let delim = [";", ",", "\t"].max { a, b in sample.components(separatedBy: a).count < sample.components(separatedBy: b).count } ?? ";"
        let d = Character(delim)
        func parse(_ l: String) -> [String] {
            var out: [String] = [], cur = "", inq = false
            let ch = Array(l)
            var i = 0
            while i < ch.count {
                let c = ch[i]
                if inq {
                    if c == "\"" { if i + 1 < ch.count && ch[i + 1] == "\"" { cur.append("\""); i += 1 } else { inq = false } } else { cur.append(c) }
                } else if c == "\"" { inq = true }
                else if c == d { out.append(cur.trimmingCharacters(in: .whitespaces)); cur = "" }
                else { cur.append(c) }
                i += 1
            }
            out.append(cur.trimmingCharacters(in: .whitespaces))
            return out
        }
        let rows = lines.map(parse)
        let dateRX = RX(#"^(buchungs?tag|buchung|datum|date|buchungsdatum|valuta(datum)?|wertstellung|transaktionsdatum|booking date)$"#)
        let amountRX = RX(#"^(betrag( \(eur\)| in eur| \(€\))?|umsatz|amount|netto|brutto|betrag eur|wert)$"#)
        let nameRX = RX(#"^(name|empfänger|empfaenger|auftraggeber\/empfänger|beguenstigter\/zahlungspflichtiger|begünstigter\/zahlungspflichtiger|zahlungsempfänger.*|auftraggeber.*|gegenpartei|payee|counterparty|partner)$"#)
        let textRX = RX(#"^(verwendungszweck|beschreibung|description|betreff|buchungstext|vorgang|hinweis|typ|art|details?)$"#)
        var hi = rows.firstIndex { r in r.contains { dateRX.test($0) } && r.contains { amountRX.test($0) } } ?? 0
        if hi < 0 { hi = 0 }
        let head = rows[hi]
        let body = Array(rows.dropFirst(hi + 1)).filter { $0.count >= min(3, head.count) }
        func find(_ re: RX) -> Int { head.firstIndex { re.test($0) } ?? -1 }
        let paypal = head.contains("Transaktionscode") || head.contains("Brutto")
        var map: [String: Int] = [
            "date": find(dateRX),
            "amount": paypal && head.contains("Netto") ? head.firstIndex(of: "Netto")! : find(amountRX),
            "name": find(nameRX),
            "text": paypal && head.contains("Typ") ? head.firstIndex(of: "Typ")! : find(textRX),
        ]
        if map["name"] == -1 { map["name"] = find(RX("name|empf|auftrag")) }
        if map["text"] == -1 { map["text"] = find(RX("zweck|text|betreff")) }
        let tr = RX("trade.?republic")
        let accName = paypal ? "PayPal" : (tr.test(fileName) || head.contains { RX("trade republic").test($0) }) ? "Trade Republic" : RX("paypal").test(fileName) ? "PayPal" : ""
        return CSVData(head: head, body: body, map: map, paypal: paypal, accName: accName)
    }

    static func parseDate(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if let m = RX(#"^(\d{1,2})\.(\d{1,2})\.(\d{2,4})"#).re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) {
            let g = (1...3).map { Int(s[Range(m.range(at: $0), in: s)!]) ?? 0 }
            let y = g[2] < 100 ? 2000 + g[2] : g[2]
            return String(format: "%04d-%02d-%02d", y, g[1], g[0])
        }
        if let m = RX(#"^(\d{4})-(\d{2})-(\d{2})"#).first(s) { return m }
        if let m = RX(#"^(\d{1,2})/(\d{1,2})/(\d{4})"#).re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) {
            let g = (1...3).map { Int(s[Range(m.range(at: $0), in: s)!]) ?? 0 }
            return String(format: "%04d-%02d-%02d", g[2], g[1], g[0])
        }
        return nil
    }

    static func parseAmount(_ raw: String) -> Int? {
        var s = raw.replacingOccurrences(of: "€", with: "").replacingOccurrences(of: "EUR", with: "").filter { !$0.isWhitespace }
        if s.isEmpty { return nil }
        if RX(#",\d{1,2}$"#).test(s) { s = s.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
        else { s = s.replacingOccurrences(of: ",", with: "") }
        guard let v = Double(s), v.isFinite else { return nil }
        return Int((v * 100).rounded())
    }

    static func parseSigned(_ raw: String) -> Int? {
        let t = raw.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        let neg = t.hasPrefix("-") || t.hasPrefix("−")
        guard let v = Money.parse(String(t.drop { $0 == "-" || $0 == "−" })) else { return t == "0" ? 0 : nil }
        return neg ? -v : v
    }

    /// Importiert die Zeilen, doppelte werden übersprungen. Gibt (neu, übersprungen) zurück.
    func importCSV(_ c: CSVData, account: String?, newName: String, balance: Int?) async -> (Int, Int) {
        var aid = account ?? ""
        var upd: [String: Any] = [:]
        if account == nil {
            let n = newName.trimmingCharacters(in: .whitespaces).isEmpty ? "Importiertes Konto" : newName.trimmingCharacters(in: .whitespaces)
            aid = String(safeKey("csv_" + n + "_" + String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)).replacingOccurrences(of: " ", with: "_"))
            upd["accounts/\(aid)/name"] = n
            upd["accounts/\(aid)/src"] = "csv"
            upd["accounts/\(aid)/kind"] = n.lowercased().contains("depot") ? "depot" : "bank"
        }
        if let balance { upd["accounts/\(aid)/balance"] = balance }
        upd["accounts/\(aid)/syncAt"] = DB.nowMs
        var seen = Set(rawTx.values.filter { $0.acc == aid }.map { Self.hashTx(date: $0.date, amount: $0.amount, name: $0.name, text: $0.text) })
        var n = 0, skip = 0
        let col = { (r: [String], k: String) -> String in let i = c.map[k] ?? -1; return i >= 0 && i < r.count ? r[i] : "" }
        let ppRX = RX(#"bankgutschrift|allgemeine abbuchung|kartengutschrift|umbuchung|überweisung auf|abbuchung von|kreditkarte|ausgleich"#)
        for r in c.body {
            guard let date = Self.parseDate(col(r, "date")), let amount = Self.parseAmount(col(r, "amount")), amount != 0 else { skip += 1; continue }
            let name = String(col(r, "name").prefix(120))
            let text = String(col(r, "text").split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(300))
            let h = Self.hashTx(date: date, amount: amount, name: name, text: text)
            if seen.contains(h) { skip += 1; continue }
            seen.insert(h)
            var t: [String: Any] = ["acc": aid, "date": date, "amount": amount, "name": name, "text": text, "src": "csv"]
            if c.paypal && ppRX.test(text) { t["cat"] = "Umbuchung"; t["catSrc"] = "rule" }
            upd["tx/\(safeKey(aid + "_" + h))"] = t
            n += 1
        }
        _ = try? await fin.updateChildValues(upd)
        await categorizeNew()
        return (n, skip)
    }
}
