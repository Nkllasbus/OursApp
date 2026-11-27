import Foundation
import Observation
import FirebaseDatabase
import UserNotifications
import UIKit

/// Trainingsdaten live aus Firebase: users/<uid>/spaces/gym → spaces/<sid>/{exercises, templates, workouts, sessions}
@MainActor
@Observable
final class GymStore {
    var sid: String?
    var loaded = false
    var exercises: [String: Exercise] = [:]
    var templates: [String: WorkoutTemplate] = [:]
    var plan: [String: PlanEntry] = [:]
    var sessions: [String: TrainingSession] = [:]
    /// Pause nach jedem Satz in Sekunden (0 = aus)
    var restSeconds: Int = UserDefaults.standard.object(forKey: "gym.rest") as? Int ?? 90 {
        didSet { UserDefaults.standard.set(restSeconds, forKey: "gym.rest") }
    }
    var restEnd: Date?

    private(set) var uid = ""
    private var handles: [(DatabaseReference, DatabaseHandle)] = []
    private var db: DatabaseReference { DB.root }

    // MARK: Laden

    func start(uid: String) async {
        guard self.uid != uid else { return }
        self.uid = uid
        let snap = try? await db.child("users/\(uid)/spaces/gym").getData()
        if let s = snap?.value as? String, !s.isEmpty { attach(s) } else { loaded = true }
    }

    private func attach(_ sid: String) {
        stop()
        self.sid = sid
        let base = db.child("spaces/\(sid)")
        base.keepSynced(true)
        observe(base.child("exercises")) { s, v in s.exercises = Dictionary(uniqueKeysWithValues: DB.dict(v).compactMap { k, x in Exercise.parse(k, x).map { (k, $0) } }) }
        observe(base.child("templates")) { s, v in s.templates = Dictionary(uniqueKeysWithValues: DB.dict(v).compactMap { k, x in WorkoutTemplate.parse(k, x).map { (k, $0) } }) }
        observe(base.child("workouts")) { s, v in s.plan = Dictionary(uniqueKeysWithValues: DB.dict(v).compactMap { k, x in PlanEntry.parse(k, x).map { (k, $0) } }) }
        observe(base.child("sessions")) { s, v in
            s.sessions = Dictionary(uniqueKeysWithValues: DB.dict(v).compactMap { k, x in TrainingSession.parse(k, x).map { (k, $0) } })
            s.loaded = true
            UIApplication.shared.isIdleTimerDisabled = s.activeSession != nil
        }
    }

    private func observe(_ ref: DatabaseReference, _ apply: @escaping (GymStore, Any?) -> Void) {
        let h = ref.observe(.value, with: { [weak self] snap in
            let v = snap.value
            Task { @MainActor in if let self { apply(self, v) } }
        }, withCancel: { [weak self] _ in
            Task { @MainActor in self?.loaded = true }
        })
        handles.append((ref, h))
    }

    /// Ziehen zum Aktualisieren: Daten neu verbinden
    func reload() async {
        if let s = sid { attach(s) } else {
            let snap = try? await db.child("users/\(uid)/spaces/gym").getData()
            if let s = snap?.value as? String, !s.isEmpty { attach(s) }
        }
        try? await Task.sleep(nanoseconds: 400_000_000)
    }

    func stop() {
        for (r, h) in handles { r.removeObserver(withHandle: h) }
        handles = []
    }

    /// Eigenen Trainingsbereich anlegen (wie auf der Webseite)
    func createSpace() async throws {
        let sid = DB.randomID()
        try await db.child("spaces/\(sid)/access/\(uid)").setValue("owner")
        try await db.child("spaces/\(sid)/meta").setValue(["type": "gym", "owner": uid, "createdAt": DB.nowMs])
        try await db.child("users/\(uid)/spaces/gym").setValue(sid)
        attach(sid)
    }

    private func ref(_ path: String) -> DatabaseReference? {
        guard let sid else { return nil }
        return db.child("spaces/\(sid)/\(path)")
    }

    // MARK: Abfragen

    var exerciseList: [Exercise] {
        exercises.values.sorted { (MuscleGroup.index($0.group), $0.name.lowercased()) < (MuscleGroup.index($1.group), $1.name.lowercased()) }
    }
    var templateList: [WorkoutTemplate] { templates.values.sorted { $0.at < $1.at } }
    var mySessions: [TrainingSession] { sessions.values.filter { $0.by == uid } }
    var activeSession: TrainingSession? { mySessions.first { $0.start > 0 && $0.isActive } }
    var history: [TrainingSession] { mySessions.filter { !$0.isActive }.sorted { $0.start > $1.start } }

    func exercises(of t: WorkoutTemplate?) -> [Exercise] { (t?.ex ?? []).compactMap { exercises[$0] } }
    func exercises(in s: TrainingSession) -> [Exercise] {
        if let ex = s.ex { return ex.compactMap { exercises[$0] } }
        return exercises(of: templates[s.tpl])
    }
    func title(of s: TrainingSession) -> String { templates[s.tpl]?.title ?? "Training" }

    func entries(on day: String) -> [PlanEntry] {
        plan.values.filter { $0.occurs(on: day) && !exercises(of: templates[$0.tpl]).isEmpty }
            .sorted { ($0.time ?? "99") < ($1.time ?? "99") }
    }

    func doneSession(for e: PlanEntry, on day: String) -> TrainingSession? {
        mySessions.first { !$0.isActive && $0.date == day && ($0.plan == e.id || $0.tpl == e.tpl) }
    }

    /// letztes beendetes Training mit dieser Übung
    func last(for exId: String, before: Double) -> TrainingSession? {
        mySessions.filter { !$0.isActive && $0.start < before && !$0.doneSets(exId).isEmpty }.max { $0.start < $1.start }
    }

    func setCount(_ s: TrainingSession, _ x: Exercise) -> Int {
        let lastN = last(for: x.id, before: s.start)?.doneSets(x.id).count ?? 0
        return max(s.setsFor(x.id).count, s.extra[x.id] ?? 0, x.sets ?? 0, lastN, x.isCardio ? 1 : 3)
    }

    /// angezeigter Wert: eingetragen > letztes Mal > Standard
    func value(_ s: TrainingSession, _ x: Exercise, _ k: Int, reps: Bool) -> Double {
        let cur = s.setsFor(x.id)
        if k < cur.count, let v = reps ? cur[k].r : cur[k].kg { return v }
        if let l = last(for: x.id, before: s.start) {
            let ls = l.doneSets(x.id)
            let e = k < ls.count ? ls[k] : ls.last
            if let v = reps ? e?.r : e?.kg { return v }
        }
        if reps { return x.isCardio ? 20 : 10 }
        return x.kg ?? 0
    }

    func step(_ x: Exercise, reps: Bool, at v: Double) -> Double {
        reps ? (x.isCardio ? 5 : 1) : (v < 20 ? 1 : 2.5)
    }

    func lastText(_ s: TrainingSession, _ x: Exercise) -> String? {
        guard let l = last(for: x.id, before: s.start) else { return nil }
        return l.doneSets(x.id).map { x.isCardio ? "\(Int($0.r ?? 0)) min" : "\(Int($0.r ?? 0))×\(Gym.fmtKg($0.kg ?? 0)) kg" }.joined(separator: ", ")
    }

    // MARK: Training

    func startTraining(template: String, planID: String? = nil) {
        guard activeSession == nil, let r = ref("sessions") else { return }
        let id = r.childByAutoId().key ?? DB.randomID()
        var data: [String: Any] = ["tpl": template, "date": Gym.iso(Date()), "start": DB.nowMs, "by": uid, "v": 2]
        if let planID { data["plan"] = planID }
        if let s = TrainingSession.parse(id, data) { sessions[id] = s }
        r.child(id).put(data)
        UIApplication.shared.isIdleTimerDisabled = true
        requestNotifications()
    }

    func saveSet(_ s: TrainingSession, _ x: Exercise, _ k: Int, r: Double? = nil, kg: Double? = nil, done: Bool? = nil) {
        guard var cur = sessions[s.id] else { return }
        var list = cur.sets[x.id] ?? []
        while list.count <= k { list.append(SetEntry(r: nil, kg: nil, done: false)) }
        if let r { list[k].r = r }
        if let kg { list[k].kg = kg }
        if let done { list[k].done = done }
        cur.sets[x.id] = list
        sessions[s.id] = cur
        var upd: [String: Any] = ["d": list[k].done]
        if let r = list[k].r { upd["r"] = r }
        if let kg = list[k].kg { upd["kg"] = kg }
        ref("sessions/\(s.id)/sets/\(x.id)/\(k)")?.merge(upd)
    }

    func toggleDone(_ s: TrainingSession, _ x: Exercise, _ k: Int) {
        let cur = s.setsFor(x.id)
        let wasDone = k < cur.count && cur[k].done
        let r = value(s, x, k, reps: true), kg = x.isCardio ? nil : value(s, x, k, reps: false)
        saveSet(s, x, k, r: r, kg: kg, done: !wasDone)
        if !wasDone && !x.isCardio && restSeconds > 0 { startRest() } else if wasDone { stopRest() }
    }

    func addSet(_ s: TrainingSession, _ x: Exercise) {
        let n = setCount(s, x) + 1
        sessions[s.id]?.extra[x.id] = n
        ref("sessions/\(s.id)/n/\(x.id)")?.put(n)
    }

    /// Training beenden: Dauer und Volumen speichern
    func endTraining(_ s: TrainingSession) {
        let end = DB.nowMs, dur = ((end - s.start) / 1000).rounded()
        var vol = 0.0
        for x in exercises(in: s) { vol += s.doneSets(x.id).reduce(0) { $0 + ($1.r ?? 0) * ($1.kg ?? 0) } }
        sessions[s.id]?.end = end
        sessions[s.id]?.dur = dur
        sessions[s.id]?.vol = vol.rounded()
        ref("sessions/\(s.id)")?.merge(["end": end, "dur": dur, "vol": vol.rounded()])
        stopRest()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func cancelTraining(_ s: TrainingSession) {
        sessions[s.id] = nil
        ref("sessions/\(s.id)")?.drop()
        stopRest()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func deleteSession(_ s: TrainingSession) {
        sessions[s.id] = nil
        ref("sessions/\(s.id)")?.drop()
    }

    func setFeel(_ s: TrainingSession, _ feel: String) {
        sessions[s.id]?.feel = feel
        ref("sessions/\(s.id)/feel")?.put(feel)
    }

    // MARK: Pausentimer mit iPhone-Mitteilung

    func startRest() {
        restEnd = Date().addingTimeInterval(TimeInterval(restSeconds))
        let c = UNMutableNotificationContent()
        c.title = "Pause vorbei"
        c.body = "Weiter mit dem nächsten Satz 💪"
        c.sound = .default
        let req = UNNotificationRequest(identifier: "gym.rest", content: c,
                                        trigger: UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(1, restSeconds)), repeats: false))
        UNUserNotificationCenter.current().add(req)
    }

    func stopRest() {
        restEnd = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["gym.rest"])
    }

    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: Übungen, Workouts, Plan bearbeiten

    func saveExercise(id: String?, name: String, group: String, sets: Int?, reps: String?, kg: Double?) -> String {
        let id = id ?? (ref("exercises")?.childByAutoId().key ?? DB.randomID())
        let old = exercises[id]
        var data: [String: Any] = ["name": String(name.prefix(60)), "group": group, "at": old?.at ?? DB.nowMs]
        if let sets, sets > 0 { data["sets"] = sets }
        if let reps, !reps.isEmpty { data["reps"] = String(reps.prefix(7)) }
        if let kg, kg > 0 { data["kg"] = (kg * 10).rounded() / 10 }
        if let img = old?.img { data["img"] = img }
        if let e = Exercise.parse(id, data) { exercises[id] = e }
        ref("exercises/\(id)")?.put(data)
        return id
    }

    func deleteExercise(_ x: Exercise) {
        exercises[x.id] = nil
        ref("exercises/\(x.id)")?.drop()
        for t in templates.values where t.ex.contains(x.id) {
            ref("templates/\(t.id)/ex")?.put(t.ex.filter { $0 != x.id })
        }
    }

    func saveTemplate(id: String?, title: String, ex: [String]) {
        let id = id ?? (ref("templates")?.childByAutoId().key ?? DB.randomID())
        let sorted = ex.compactMap { exercises[$0] }
            .sorted { (MuscleGroup.index($0.group), $0.name.lowercased()) < (MuscleGroup.index($1.group), $1.name.lowercased()) }
            .map(\.id)
        var data: [String: Any] = ["title": String(title.prefix(30)), "ex": sorted, "at": templates[id]?.at ?? DB.nowMs]
        if let col = templates[id]?.col { data["col"] = col }
        if let t = WorkoutTemplate.parse(id, data) { templates[id] = t }
        ref("templates/\(id)")?.put(data)
    }

    func deleteTemplate(_ t: WorkoutTemplate) {
        templates[t.id] = nil
        ref("templates/\(t.id)")?.drop()
        for e in plan.values where e.tpl == t.id { ref("workouts/\(e.id)")?.drop() }
    }

    func savePlan(id: String?, tpl: String, time: String?, dur: Int, rep: PlanRepeat) {
        let id = id ?? (ref("workouts")?.childByAutoId().key ?? DB.randomID())
        var data: [String: Any] = ["tpl": tpl, "dur": dur, "rep": rep.firebase, "at": plan[id]?.at ?? DB.nowMs]
        if let time { data["time"] = time }
        if let al = plan[id]?.alerts, !al.isEmpty { data["al"] = al }
        if let e = PlanEntry.parse(id, data) { plan[id] = e }
        ref("workouts/\(id)")?.put(data)
    }

    func deletePlan(_ e: PlanEntry) {
        plan[e.id] = nil
        ref("workouts/\(e.id)")?.drop()
    }
}
