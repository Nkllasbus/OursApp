import Foundation
import SwiftUI

/// Muskelgruppen wie auf der Webseite (gym.html → GROUPS)
struct MuscleGroup: Identifiable, Hashable {
    let id: String
    let name: String
    let emoji: String
    let color: Color
    let suggestions: [String]

    static let all: [MuscleGroup] = [
        .init(id: "brust", name: "Brust", emoji: "🏋️", color: Color(hex: 0xC8574A), suggestions: ["Bankdrücken", "Schrägbankdrücken", "Kurzhantel-Flys", "Butterfly", "Dips", "Liegestütze"]),
        .init(id: "ruecken", name: "Rücken", emoji: "🧗", color: Color(hex: 0x3F7A8C), suggestions: ["Klimmzüge", "Latziehen", "Rudern am Kabel", "Langhantelrudern", "Kreuzheben", "Hyperextensions"]),
        .init(id: "schulter", name: "Schultern", emoji: "🙆", color: Color(hex: 0x8A6BBF), suggestions: ["Schulterdrücken", "Seitheben", "Frontheben", "Face Pulls", "Reverse Flys", "Arnold Press"]),
        .init(id: "bizeps", name: "Bizeps", emoji: "💪", color: Color(hex: 0xD08A2C), suggestions: ["Langhantelcurls", "Kurzhantelcurls", "Hammercurls", "Konzentrationscurls", "Kabelcurls"]),
        .init(id: "trizeps", name: "Trizeps", emoji: "🦾", color: Color(hex: 0xB8642F), suggestions: ["Trizepsdrücken am Kabel", "French Press", "Dips", "Überkopf-Trizeps", "Enges Bankdrücken"]),
        .init(id: "bauch", name: "Bauch", emoji: "🔥", color: Color(hex: 0x5D8F5A), suggestions: ["Crunches", "Plank", "Beinheben", "Russian Twists", "Ab-Roller", "Kabel-Crunches"]),
        .init(id: "quads", name: "Oberschenkel vorne", emoji: "🦵", color: Color(hex: 0x2F6F9F), suggestions: ["Kniebeugen", "Beinpresse", "Beinstrecker", "Ausfallschritte", "Bulgarian Split Squats"]),
        .init(id: "hams", name: "Oberschenkel hinten", emoji: "🦵", color: Color(hex: 0x2E5B7A), suggestions: ["Beinbeuger liegend", "Beinbeuger sitzend", "Rumänisches Kreuzheben"]),
        .init(id: "po", name: "Po", emoji: "🍑", color: Color(hex: 0xC0607D), suggestions: ["Hip Thrusts", "Abduktoren-Maschine", "Glute Kickbacks", "Sumo-Kniebeugen"]),
        .init(id: "waden", name: "Waden", emoji: "🦶", color: Color(hex: 0x6F7D3A), suggestions: ["Wadenheben stehend", "Wadenheben sitzend", "Wadenheben an der Beinpresse"]),
        .init(id: "unterarme", name: "Unterarme", emoji: "✊", color: Color(hex: 0x8A7350), suggestions: ["Handgelenk-Curls", "Farmer's Walk", "Reverse Curls"]),
        .init(id: "cardio", name: "Cardio", emoji: "🏃", color: Color(hex: 0x4A7F7A), suggestions: ["Laufband", "Fahrrad", "Crosstrainer", "Rudergerät", "Treppensteiger", "Seilspringen"]),
    ]

    static func of(_ id: String) -> MuscleGroup { all.first { $0.id == id } ?? all[0] }
    static func index(_ id: String) -> Int { all.firstIndex { $0.id == id } ?? 99 }
}

/// Übung (spaces/<gym>/exercises/<id>): {name, group, sets, reps, kg, img, at}
struct Exercise: Identifiable, Hashable {
    let id: String
    var name: String
    var group: String
    var sets: Int?
    var reps: String?
    var kg: Double?
    var img: String?
    var at: Double

    var isCardio: Bool { group == "cardio" }
    var targetReps: Int { Int(reps?.prefix { $0.isNumber } ?? "") ?? 10 }
    var detail: String {
        var p: [String] = []
        if sets != nil || reps != nil { p.append("\(sets.map(String.init) ?? "?") × \(reps ?? "?")") }
        if let kg, kg > 0 { p.append("\(Gym.fmtKg(kg)) kg") }
        return p.isEmpty ? MuscleGroup.of(group).name : p.joined(separator: " · ")
    }
    /// Bild der Übung (gleiche Bilder wie die Webseite)
    var imageURL: URL? {
        guard let img, !img.isEmpty else { return nil }
        return URL(string: "https://nkllasbus.github.io/OursApp/gym-img/\(img)-1.jpg")
    }

    static func parse(_ id: String, _ raw: Any?) -> Exercise? {
        let v = DB.dict(raw)
        guard let name = v["name"] as? String, !name.isEmpty else { return nil }
        let s = DB.num(v["sets"]), kg = DB.num(v["kg"])
        let reps: String? = (v["reps"] as? String) ?? ((v["reps"] as? NSNumber).map { $0.stringValue })
        return Exercise(id: id, name: name, group: v["group"] as? String ?? "brust", sets: s > 0 ? Int(s) : nil,
                        reps: reps, kg: kg > 0 ? kg : nil, img: v["img"] as? String, at: DB.num(v["at"]))
    }
}

/// Workout-Vorlage (templates/<id>): {title, ex:[ids], at, col}
struct WorkoutTemplate: Identifiable, Hashable {
    let id: String
    var title: String
    var ex: [String]
    var at: Double
    var col: String?

    static func parse(_ id: String, _ raw: Any?) -> WorkoutTemplate? {
        let v = DB.dict(raw)
        guard let title = v["title"] as? String, !title.isEmpty else { return nil }
        return WorkoutTemplate(id: id, title: title, ex: Gym.stringList(v["ex"]), at: DB.num(v["at"]), col: v["col"] as? String)
    }
}

/// Wiederholung eines Plan-Eintrags
enum PlanRepeat: Hashable {
    case once(String)               // Datum
    case weekly([Int])              // 0 = Montag
    case every(Int, String)         // alle n Tage ab Datum

    var text: String {
        switch self {
        case .once: return "einmalig"
        case .weekly(let d):
            if d.count == 7 { return "jeden Tag" }
            return d.isEmpty ? "wöchentlich" : "jeden " + d.sorted().map { Gym.dayShort[$0] }.joined(separator: ", ")
        case .every(let n, _): return n == 1 ? "jeden Tag" : "alle \(n) Tage"
        }
    }

    var firebase: [String: Any] {
        switch self {
        case .once(let d): return ["type": "once", "date": d]
        case .weekly(let days): return ["type": "weekly", "days": days.sorted()]
        case .every(let n, let s): return ["type": "every", "n": n, "start": s]
        }
    }

    static func parse(_ raw: Any?) -> PlanRepeat? {
        let r = DB.dict(raw)
        switch r["type"] as? String {
        case "once": return .once(r["date"] as? String ?? "")
        case "weekly": return .weekly(Gym.intList(r["days"]))
        case "every": return .every(max(1, Int(DB.num(r["n"]))), r["start"] as? String ?? "")
        default: return nil
        }
    }
}

/// Eintrag im Wochenplan (workouts/<id>): {tpl, time, dur, rep, at, al}
struct PlanEntry: Identifiable, Hashable {
    let id: String
    var tpl: String
    var time: String?
    var dur: Int
    var rep: PlanRepeat
    var at: Double
    var alerts: [Int]

    func occurs(on day: String) -> Bool {
        switch rep {
        case .once(let d): return d == day
        case .weekly(let days): return days.contains(Gym.weekday(day))
        case .every(let n, let start):
            let d = Gym.dayNumber(day) - Gym.dayNumber(start.isEmpty ? day : start)
            return d >= 0 && d % max(1, n) == 0
        }
    }

    static func parse(_ id: String, _ raw: Any?) -> PlanEntry? {
        let v = DB.dict(raw)
        guard let tpl = v["tpl"] as? String, let rep = PlanRepeat.parse(v["rep"]) else { return nil }
        let t = v["time"] as? String
        let dur = Int(DB.num(v["dur"]))
        return PlanEntry(id: id, tpl: tpl, time: (t?.count == 5) ? t : nil, dur: dur > 0 ? dur : 60, rep: rep,
                         at: DB.num(v["at"]), alerts: Gym.intList(v["al"]))
    }
}

/// Ein Satz: Wiederholungen (bei Cardio Minuten), Gewicht, erledigt
struct SetEntry: Hashable {
    var r: Double?
    var kg: Double?
    var done: Bool
}

/// Training (sessions/<id>): {tpl, plan, date, start, end, dur, by, v:2, sets:{exId:{k:{r,kg,d}}}, n:{exId:Anzahl}, ex:[ids], vol, kcal, feel}
struct TrainingSession: Identifiable, Hashable {
    let id: String
    var tpl: String
    var plan: String?
    var date: String
    var start: Double
    var end: Double?
    var dur: Double
    var by: String
    var v2: Bool
    var sets: [String: [SetEntry]]
    var extra: [String: Int]
    var ex: [String]?
    var vol: Double
    var feel: String?

    var isActive: Bool { end == nil }

    func setsFor(_ exId: String) -> [SetEntry] { sets[exId] ?? [] }
    func doneSets(_ exId: String) -> [SetEntry] {
        setsFor(exId).filter { ($0.r ?? 0) > 0 && ($0.done || !v2) }
    }

    static func parse(_ id: String, _ raw: Any?) -> TrainingSession? {
        let v = DB.dict(raw)
        guard let by = v["by"] as? String else { return nil }
        let v2 = DB.num(v["v"]) == 2
        var sets: [String: [SetEntry]] = [:]
        for (exId, rawSets) in DB.dict(v["sets"]) {
            var list: [Int: SetEntry] = [:]
            let pairs: [(Int, Any)]
            if let arr = rawSets as? [Any] {
                pairs = arr.enumerated().map { ($0.offset, $0.element) }
            } else {
                pairs = DB.dict(rawSets).compactMap { k, x in Int(k).map { ($0, x) } }
            }
            for (k, x) in pairs {
                let s = DB.dict(x)
                if s.isEmpty { continue }
                let r = s["r"].map { DB.num($0) }, kg = s["kg"].map { DB.num($0) }
                list[k] = SetEntry(r: r, kg: kg, done: (s["d"] as? Bool) ?? false)
            }
            if let maxK = list.keys.max() {
                sets[exId] = (0...maxK).map { list[$0] ?? SetEntry(r: nil, kg: nil, done: false) }
            }
        }
        var extra: [String: Int] = [:]
        for (k, n) in DB.dict(v["n"]) { extra[k] = Int(DB.num(n)) }
        let endV = DB.num(v["end"])
        return TrainingSession(id: id, tpl: v["tpl"] as? String ?? "", plan: v["plan"] as? String,
                               date: v["date"] as? String ?? "", start: DB.num(v["start"]), end: endV > 0 ? endV : nil,
                               dur: DB.num(v["dur"]), by: by, v2: v2, sets: sets, extra: extra,
                               ex: v["ex"] == nil ? nil : Gym.stringList(v["ex"]), vol: DB.num(v["vol"]), feel: v["feel"] as? String)
    }
}

/// Hilfsfunktionen
enum Gym {
    static let dayShort = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
    static let dayLong = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]

    static func fmtKg(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r).replacingOccurrences(of: ".", with: ",")
    }

    static func fmtDur(_ sec: Double) -> String {
        let s = max(0, Int(sec.rounded()))
        let h = s / 3600, m = s % 3600 / 60, x = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, x) : String(format: "%d:%02d", m, x)
    }

    static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func iso(_ d: Date) -> String { isoFormatter.string(from: d) }
    static func date(_ s: String) -> Date { isoFormatter.date(from: s) ?? Date() }
    /// 0 = Montag
    static func weekday(_ s: String) -> Int { (Calendar(identifier: .gregorian).component(.weekday, from: date(s)) + 5) % 7 }
    static func dayNumber(_ s: String) -> Int {
        let p = s.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return 0 }
        var c = DateComponents(); c.year = p[0]; c.month = p[1]; c.day = p[2]
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        return Int((cal.date(from: c)?.timeIntervalSince1970 ?? 0) / 86400)
    }

    static func monday(offsetWeeks: Int) -> Date {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: Date())
        let wd = (cal.component(.weekday, from: today) + 5) % 7
        return cal.date(byAdding: .day, value: -wd + offsetWeeks * 7, to: today) ?? today
    }

    static func stringList(_ raw: Any?) -> [String] {
        if let a = raw as? [Any] { return a.compactMap { $0 as? String } }
        return DB.dict(raw).sorted { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }.compactMap { $0.value as? String }
    }

    static func intList(_ raw: Any?) -> [Int] {
        if let a = raw as? [Any] { return a.compactMap { ($0 as? NSNumber)?.intValue } }
        return DB.dict(raw).sorted { (Int($0.key) ?? 0) < (Int($1.key) ?? 0) }.compactMap { ($0.value as? NSNumber)?.intValue }
    }
}
