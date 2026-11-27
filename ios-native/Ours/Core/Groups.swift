import Foundation
import Observation
import SwiftUI
import FirebaseDatabase

/// Rolle in einer Gruppe: Erwachsene verwalten alles, Kinder sehen keine gemeinsamen Finanzen
enum GroupRole: String, CaseIterable, Identifiable {
    case adult, child
    var id: String { rawValue }
    var label: String { self == .adult ? "Erwachsen" : "Kind" }
}

enum GroupKind: String, CaseIterable, Identifiable {
    case couple, family, flat, friends
    var id: String { rawValue }
    var label: String {
        switch self {
        case .couple: "Paar"
        case .family: "Familie"
        case .flat: "WG"
        case .friends: "Freunde"
        }
    }
    var symbol: String {
        switch self {
        case .couple: "heart.fill"
        case .family: "figure.2.and.child.holdinghands"
        case .flat: "house.fill"
        case .friends: "person.3.fill"
        }
    }
    var suggestedName: String {
        switch self {
        case .couple: "Wir zwei"
        case .family: "Familie"
        case .flat: "WG"
        case .friends: "Freunde"
        }
    }
}

/// Bereiche, die eine Gruppe teilen kann (gleiche Namen wie auf der Webseite)
enum SpaceType {
    static let label: [String: String] = [
        "calendar": "Kalender", "chores": "Haushalt", "recipes": "Rezepte", "trips": "Reisen",
        "budget": "Gemeinsames Budget", "shopping": "Einkaufslisten", "pocket": "Kinder-Konto", "gym": "Gym",
    ]
    static let symbol: [String: String] = [
        "calendar": "calendar", "chores": "house.fill", "recipes": "fork.knife", "trips": "airplane",
        "budget": "eurosign.circle.fill", "shopping": "cart.fill", "pocket": "banknote.fill", "gym": "dumbbell.fill",
    ]
    /// Diese Bereiche sehen nur Erwachsene
    static let adultsOnly: Set<String> = ["budget"]
    /// Diese Bereiche kann man aus der Webseite in eine Gruppe übernehmen
    static let importable = ["calendar", "chores", "recipes", "trips", "budget"]
}

struct GroupMember: Identifiable, Hashable {
    let id: String
    var name: String
    var role: GroupRole
    var joined: Double
}

struct GroupSpace: Identifiable, Hashable {
    var id: String { sid }
    let sid: String
    var type: String
    var adults: Bool
    var owner: String?
}

struct OursGroup: Identifiable, Hashable {
    let id: String
    var name: String
    var kind: GroupKind
    var colorHex: String
    var members: [GroupMember]
    var spaces: [GroupSpace]

    var color: Color { Color(hexString: colorHex) }
    func role(of uid: String) -> GroupRole? { members.first { $0.id == uid }?.role }
    func isAdult(_ uid: String) -> Bool { role(of: uid) == .adult }
    func space(_ type: String, owner: String? = nil) -> GroupSpace? {
        spaces.first { $0.type == type && (owner == nil || $0.owner == owner) }
    }
    var sortedMembers: [GroupMember] {
        members.sorted { ($0.role == .adult ? 0 : 1, $0.name.lowercased()) < ($1.role == .adult ? 0 : 1, $1.name.lowercased()) }
    }
    var summary: String {
        let n = members.count
        return "\(kind.label) · \(n) \(n == 1 ? "Mitglied" : "Mitglieder")"
    }

    static let palette = ["#2F72C4", "#CF4B42", "#3E9E60", "#D98E30", "#9A60BD", "#25A199", "#D04D66", "#5A5BB8"]

    static func parse(id: String, value: Any?) -> OursGroup? {
        let v = DB.dict(value)
        guard !v.isEmpty else { return nil }
        let members = DB.dict(v["members"]).compactMap { uid, raw -> GroupMember? in
            let m = DB.dict(raw)
            return GroupMember(id: uid, name: m["name"] as? String ?? "Mitglied",
                               role: GroupRole(rawValue: m["role"] as? String ?? "") ?? .adult,
                               joined: DB.num(m["at"]))
        }
        let spaces = DB.dict(v["spaceIds"]).map { sid, raw -> GroupSpace in
            let s = DB.dict(raw)
            return GroupSpace(sid: sid, type: s["type"] as? String ?? "", adults: (s["adults"] as? Bool) ?? false,
                              owner: s["owner"] as? String)
        }
        return OursGroup(id: id, name: v["name"] as? String ?? "Gruppe",
                         kind: GroupKind(rawValue: v["kind"] as? String ?? "") ?? .family,
                         colorHex: v["color"] as? String ?? palette[0],
                         members: members, spaces: spaces)
    }
}

/// Bereich aus der Webseite, der in eine Gruppe übernommen werden kann
struct ImportCandidate: Identifiable, Hashable {
    var id: String { sid }
    let type: String
    let sid: String
    let people: [String: String]   // uid → Name
}

enum GroupError: LocalizedError {
    case invalidCode, expired, alreadyMember, notAdult, lastAdult
    var errorDescription: String? {
        switch self {
        case .invalidCode: "Zu diesem Code gibt es keine Einladung. Prüf die Schreibweise."
        case .expired: "Diese Einladung ist abgelaufen. Lass dir einen neuen Code schicken."
        case .alreadyMember: "Du bist schon in dieser Gruppe."
        case .notAdult: "Das dürfen nur Erwachsene in der Gruppe."
        case .lastAdult: "Du bist der einzige Erwachsene. Mach zuerst jemand anderen zum Erwachsenen."
        }
    }
}

/// Alle Gruppen des Nutzers, live aus Firebase (groupIndex/<uid> → groups/<gid>)
@MainActor
@Observable
final class GroupStore {
    var groups: [OursGroup] = []
    var loaded = false
    private(set) var uid = ""
    private var myName = ""
    private var indexHandle: DatabaseHandle?
    private var handles: [String: DatabaseHandle] = [:]
    private var byID: [String: OursGroup] = [:]
    private var db: DatabaseReference { DB.root }

    func start(uid: String, name: String) {
        myName = name
        guard self.uid != uid else { return }
        stop()
        self.uid = uid
        let ref = db.child("groupIndex/\(uid)")
        ref.keepSynced(true)
        indexHandle = ref.observe(.value, with: { [weak self] snap in
            let ids = Array(DB.dict(snap.value).keys)
            Task { @MainActor in self?.updateIndex(ids) }
        }, withCancel: { [weak self] _ in
            Task { @MainActor in self?.loaded = true }
        })
    }

    func stop() {
        if let h = indexHandle, !uid.isEmpty { db.child("groupIndex/\(uid)").removeObserver(withHandle: h) }
        for (gid, h) in handles { db.child("groups/\(gid)").removeObserver(withHandle: h) }
        handles = [:]; byID = [:]; groups = []; indexHandle = nil; uid = ""; loaded = false
    }

    func setName(_ name: String) { myName = name }

    private func updateIndex(_ ids: [String]) {
        for gid in handles.keys where !ids.contains(gid) {
            if let h = handles[gid] { db.child("groups/\(gid)").removeObserver(withHandle: h) }
            handles[gid] = nil; byID[gid] = nil
        }
        for gid in ids where handles[gid] == nil {
            let ref = db.child("groups/\(gid)")
            ref.keepSynced(true)
            handles[gid] = ref.observe(.value, with: { [weak self] snap in
                let g = OursGroup.parse(id: gid, value: snap.value)
                Task { @MainActor in self?.apply(gid: gid, group: g) }
            }, withCancel: { [weak self] _ in
                Task { @MainActor in self?.apply(gid: gid, group: nil) }
            })
        }
        loaded = true
        publish()
    }

    private func apply(gid: String, group: OursGroup?) {
        if let group, group.role(of: uid) != nil {
            byID[gid] = group
            syncAccess(group)
        } else {
            byID[gid] = nil
        }
        publish()
    }

    private func publish() {
        groups = byID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func group(_ id: String) -> OursGroup? { byID[id] }

    // MARK: Zugriff auf die Bereiche der Gruppe

    /// Darf ich diesen Bereich sehen? (Kinder: keine gemeinsamen Finanzen, nur das eigene Konto)
    func canSee(_ s: GroupSpace, in g: OursGroup) -> Bool {
        if g.isAdult(uid) { return true }
        return !s.adults && (s.owner == nil || s.owner == uid)
    }

    /// Einmal pro Bereich: mich selbst in spaces/<sid>/access eintragen (Regel prüft die Gruppen-Mitgliedschaft)
    private func syncAccess(_ g: OursGroup) {
        let uid = self.uid, name = myName, db = self.db
        for s in g.spaces where canSee(s, in: g) {
            let key = "acc.\(uid).\(s.sid)"
            if UserDefaults.standard.bool(forKey: key) { continue }
            db.child("spaces/\(s.sid)/access/\(uid)").setValue("g:\(g.id)") { _, _ in
                // Fehler heißt meist „schon eingetragen“ – beides ist in Ordnung
                UserDefaults.standard.set(true, forKey: key)
                db.child("spaces/\(s.sid)/profiles/\(uid)").merge(["name": name])
                // Webseite: Bereich als Standard setzen, falls dort noch keiner gewählt ist
                let ptr = db.child("users/\(uid)/spaces/\(s.type)")
                ptr.getData { _, snap in
                    if snap?.value as? String == nil, s.type != "pocket", s.type != "shopping" { ptr.put(s.sid) }
                }
            }
        }
    }

    /// Bereich einer Gruppe holen oder (als Erwachsener) neu anlegen
    func ensureSpace(_ type: String, in g: OursGroup, owner: String? = nil) async throws -> String {
        if let s = g.space(type, owner: owner) { return s.sid }
        guard g.isAdult(uid) else { throw GroupError.notAdult }
        let sid = DB.randomID()
        try await db.child("spaces/\(sid)/access/\(uid)").setValue("owner")
        try await db.child("spaces/\(sid)/meta").setValue([
            "type": type, "owner": uid, "createdAt": DB.nowMs, "group": g.id, "name": g.name,
        ])
        db.child("spaces/\(sid)/profiles/\(uid)").merge(["name": myName])
        var entry: [String: Any] = ["type": type]
        if SpaceType.adultsOnly.contains(type) { entry["adults"] = true }
        if let owner { entry["owner"] = owner }
        try await db.child("groups/\(g.id)/spaceIds/\(sid)").setValue(entry)
        UserDefaults.standard.set(true, forKey: "acc.\(uid).\(sid)")
        return sid
    }

    // MARK: Gruppen anlegen, bearbeiten, verlassen

    @discardableResult
    func create(name: String, kind: GroupKind, color: String) async throws -> String {
        guard let gid = db.child("groups").childByAutoId().key else { throw GroupError.invalidCode }
        let now = DB.nowMs
        try await db.child("groups/\(gid)").setValue([
            "name": String(name.prefix(40)), "kind": kind.rawValue, "color": color, "by": uid, "at": now,
            "members": [uid: ["role": "adult", "name": myName, "at": now]],
        ])
        try await db.child("groupIndex/\(uid)/\(gid)").setValue(true)
        return gid
    }

    func update(_ g: OursGroup, name: String, kind: GroupKind, color: String) {
        db.child("groups/\(g.id)").merge(["name": String(name.prefix(40)), "kind": kind.rawValue, "color": color])
    }

    func setRole(_ role: GroupRole, for m: GroupMember, in g: OursGroup) {
        db.child("groups/\(g.id)/members/\(m.id)/role").put(role.rawValue)
        // Kind: Zugriff auf Bereiche nur für Erwachsene entfernen
        if role == .child {
            for s in g.spaces where s.adults || (s.owner != nil && s.owner != m.id) {
                db.child("spaces/\(s.sid)/access/\(m.id)").drop()
            }
        }
    }

    func remove(_ m: GroupMember, from g: OursGroup) {
        for s in g.spaces { db.child("spaces/\(s.sid)/access/\(m.id)").drop() }
        db.child("groupIndex/\(m.id)/\(g.id)").drop()
        db.child("groups/\(g.id)/members/\(m.id)").drop()
    }

    func leave(_ g: OursGroup) async throws {
        let others = g.members.filter { $0.id != uid }
        if g.isAdult(uid), !others.isEmpty, !others.contains(where: { $0.role == .adult }) { throw GroupError.lastAdult }
        for s in g.spaces { try? await db.child("spaces/\(s.sid)/access/\(uid)").removeValue() }
        if others.isEmpty {
            try await db.child("groups/\(g.id)").removeValue()
        } else {
            try await db.child("groups/\(g.id)/members/\(uid)").removeValue()
        }
        try await db.child("groupIndex/\(uid)/\(g.id)").removeValue()
    }

    // MARK: Einladen und beitreten

    func createInvite(for g: OursGroup, role: GroupRole) async throws -> String {
        guard g.isAdult(uid) else { throw GroupError.notAdult }
        let code = DB.inviteCode()
        try await db.child("groupInvites/\(code)").setValue([
            "gid": g.id, "role": role.rawValue, "name": g.name, "by": uid, "exp": DB.nowMs + 7 * 864e5,
        ])
        return code
    }

    /// Mit Code beitreten. Gibt den Namen der Gruppe zurück.
    func join(code raw: String) async throws -> String {
        let code = raw.uppercased().filter { $0.isLetter || $0.isNumber }
        guard code.count >= 6 else { throw GroupError.invalidCode }
        let snap = try await db.child("groupInvites/\(code)").getData()
        let v = DB.dict(snap.value)
        guard let gid = v["gid"] as? String, let role = v["role"] as? String else { throw GroupError.invalidCode }
        if byID[gid] != nil { throw GroupError.alreadyMember }
        guard DB.num(v["exp"]) > DB.nowMs else { throw GroupError.expired }
        try await db.child("groups/\(gid)/members/\(uid)").setValue([
            "role": role, "name": myName, "code": code, "at": DB.nowMs,
        ])
        try await db.child("groupIndex/\(uid)/\(gid)").setValue(true)
        return v["name"] as? String ?? "Gruppe"
    }

    // MARK: Bisherige Bereiche der Webseite übernehmen

    func detectImport() async -> [ImportCandidate] {
        guard !uid.isEmpty else { return [] }
        let used = Set(groups.flatMap { $0.spaces.map(\.sid) })
        guard let ptr = try? await db.child("users/\(uid)/spaces").getData() else { return [] }
        let map = DB.dict(ptr.value)
        var out: [ImportCandidate] = []
        for type in SpaceType.importable {
            guard let sid = map[type] as? String, !used.contains(sid) else { continue }
            let acc = DB.dict((try? await db.child("spaces/\(sid)/access").getData())?.value)
            guard acc[uid] != nil else { continue }
            let prof = DB.dict((try? await db.child("spaces/\(sid)/profiles").getData())?.value)
            var people: [String: String] = [:]
            for id in acc.keys { people[id] = (DB.dict(prof[id])["name"] as? String) ?? (id == uid ? myName : "Mitglied") }
            out.append(ImportCandidate(type: type, sid: sid, people: people))
        }
        return out
    }

    func importGroup(name: String, kind: GroupKind, color: String, from list: [ImportCandidate]) async throws {
        var people: [String: String] = [uid: myName]
        for c in list { for (id, n) in c.people where people[id] == nil { people[id] = n } }
        guard let gid = db.child("groups").childByAutoId().key else { return }
        let now = DB.nowMs
        var members: [String: Any] = [:]
        for (id, n) in people { members[id] = ["role": "adult", "name": n, "at": now] }
        var spaces: [String: Any] = [:]
        for c in list {
            var e: [String: Any] = ["type": c.type]
            if SpaceType.adultsOnly.contains(c.type) { e["adults"] = true }
            spaces[c.sid] = e
        }
        try await db.child("groups/\(gid)").setValue([
            "name": String(name.prefix(40)), "kind": kind.rawValue, "color": color, "by": uid, "at": now,
            "members": members, "spaceIds": spaces,
        ])
        try await db.child("groupIndex/\(uid)/\(gid)").setValue(true)
        for id in people.keys where id != uid { db.child("groupIndex/\(id)/\(gid)").put(true) }
        for c in list { db.child("spaces/\(c.sid)/meta").merge(["group": gid]) }
    }
}
