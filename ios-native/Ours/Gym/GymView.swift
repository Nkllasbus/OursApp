import SwiftUI

/// Gym: Plan · Workouts · Verlauf
struct GymView: View {
    @Environment(Session.self) private var session
    @State private var store = GymStore()
    enum Tab: String, CaseIterable { case plan = "Plan", workouts = "Workouts", history = "Verlauf" }
    @State private var tab: Tab = .plan
    @State private var showTraining = false
    @State private var creating = false

    var body: some View {
        Group {
            if !store.loaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.sid == nil {
                ContentUnavailableView {
                    Label("Noch kein Trainingsplan", systemImage: "dumbbell.fill")
                } description: {
                    Text("Leg deinen Plan an: Übungen nach Muskelgruppen, Workouts und ein Wochenplan.")
                } actions: {
                    Button("Trainingsplan anlegen") {
                        creating = true
                        Task { try? await store.createSpace(); creating = false }
                    }
                    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).disabled(creating)
                }
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        if let a = store.activeSession {
                            ActiveTrainingBanner(store: store, session: a) { showTraining = true }
                        }
                        Picker("Ansicht", selection: $tab) {
                            ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        switch tab {
                        case .plan: GymPlanView(store: store, onStart: { showTraining = true })
                        case .workouts: GymWorkoutsView(store: store)
                        case .history: GymHistoryView(store: store)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 30)
                }
                .background(Color(.systemGroupedBackground))
                .refreshable { await store.reload() }
            }
        }
        .navigationTitle("Gym")
        .tint(OursPage.gym.color)
        .task { if let uid = session.uid { await store.start(uid: uid) } }
        .fullScreenCover(isPresented: $showTraining) {
            TrainingView(store: store)
        }
        .sensoryFeedback(.selection, trigger: tab)
    }
}

struct ActiveTrainingBanner: View {
    let store: GymStore
    let session: TrainingSession
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.title2).foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(.white.opacity(0.2), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Training läuft").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                    Text(store.title(of: session)).font(.headline).foregroundStyle(.white)
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(Gym.fmtDur((DB.nowMs - session.start) / 1000))
                        .font(.title3.monospacedDigit().weight(.semibold)).foregroundStyle(.white)
                }
                Image(systemName: "chevron.right").foregroundStyle(.white.opacity(0.8))
            }
            .padding(14)
            .background(OursPage.gym.color.gradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressStyle())
    }
}

// MARK: - Plan

struct GymPlanView: View {
    let store: GymStore
    let onStart: () -> Void
    @State private var weekOffset = 0
    @State private var selectedDay = Gym.iso(Date())
    @State private var editEntry: PlanEntry?
    @State private var newPlanDay: String?

    private var days: [String] {
        let mon = Gym.monday(offsetWeeks: weekOffset)
        return (0..<7).map { Gym.iso(Calendar(identifier: .gregorian).date(byAdding: .day, value: $0, to: mon)!) }
    }

    var body: some View {
        VStack(spacing: 14) {
            // Woche
            HStack {
                Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left") }
                Spacer()
                VStack(spacing: 1) {
                    Text(weekOffset == 0 ? "Diese Woche" : weekOffset == 1 ? "Nächste Woche" : weekOffset == -1 ? "Letzte Woche" : "Woche")
                        .font(.headline)
                    Text("\(Gym.date(days[0]).formatted(.dateTime.day().month())) – \(Gym.date(days[6]).formatted(.dateTime.day().month()))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { weekOffset += 1 } label: { Image(systemName: "chevron.right") }
            }
            .font(.title3.weight(.semibold))

            HStack(spacing: 6) {
                ForEach(Array(days.enumerated()), id: \.element) { i, d in
                    let n = store.entries(on: d)
                    let done = n.contains { store.doneSession(for: $0, on: d) != nil }
                    Button { selectedDay = d } label: {
                        VStack(spacing: 4) {
                            Text(Gym.dayShort[i]).font(.caption2.weight(.semibold))
                            Text(Gym.date(d).formatted(.dateTime.day())).font(.headline)
                            Circle().fill(n.isEmpty ? Color.clear : (done ? Color.green : OursPage.gym.color)).frame(width: 6, height: 6)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(selectedDay == d ? Color.white : (d == Gym.iso(Date()) ? OursPage.gym.color : Color.primary))
                        .background(selectedDay == d ? OursPage.gym.color : Color(.secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Tag
            let entries = store.entries(on: selectedDay)
            VStack(alignment: .leading, spacing: 10) {
                Text(Gym.date(selectedDay).formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                if entries.isEmpty {
                    HStack {
                        Text("Ruhetag").foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                ForEach(entries) { e in
                    PlanCard(store: store, entry: e, day: selectedDay, onStart: {
                        store.startTraining(template: e.tpl, planID: e.id); onStart()
                    }, onEdit: { editEntry = e })
                }
                Button { newPlanDay = selectedDay } label: {
                    Label("In den Plan", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).buttonBorderShape(.capsule)
                .disabled(store.templateList.isEmpty)
            }

            // Frei trainieren
            if store.activeSession == nil && !store.templateList.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Freies Training starten").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(store.templateList) { t in
                                Button {
                                    store.startTraining(template: t.id); onStart()
                                } label: {
                                    Label(t.title, systemImage: "play.fill")
                                }
                                .buttonStyle(.bordered).buttonBorderShape(.capsule)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if store.templateList.isEmpty {
                Text("Erstell zuerst unter „Workouts“ ein Workout, z. B. „Push“ mit deinen Übungen. Danach legst du es hier auf deine Tage.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .sheet(item: $editEntry) { e in PlanEditSheet(store: store, entry: e, day: selectedDay) }
        .sheet(isPresented: Binding(get: { newPlanDay != nil }, set: { if !$0 { newPlanDay = nil } })) {
            PlanEditSheet(store: store, entry: nil, day: newPlanDay ?? selectedDay)
        }
    }
}

struct PlanCard: View {
    let store: GymStore
    let entry: PlanEntry
    let day: String
    let onStart: () -> Void
    let onEdit: () -> Void

    var body: some View {
        let t = store.templates[entry.tpl]
        let ex = store.exercises(of: t)
        let done = store.doneSession(for: entry, on: day)
        let groups = Array(Set(ex.map(\.group))).sorted { MuscleGroup.index($0) < MuscleGroup.index($1) }
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(t?.title ?? "Workout").font(.headline)
                    Text("\(entry.time.map { "\($0) Uhr · " } ?? "")\(entry.dur) Min. · \(entry.rep.text)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                if done != nil {
                    Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
                }
                Menu {
                    Button("Plan ändern", systemImage: "pencil", action: onEdit)
                    Button("Aus dem Plan nehmen", systemImage: "trash", role: .destructive) { store.deletePlan(entry) }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(groups, id: \.self) { g in
                        let mg = MuscleGroup.of(g)
                        Text(mg.name).font(.caption.weight(.semibold))
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .foregroundStyle(mg.color)
                            .background(mg.color.opacity(0.12), in: Capsule())
                    }
                }
            }
            Text(ex.map(\.name).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            if store.activeSession == nil && day == Gym.iso(Date()) {
                Button(action: onStart) {
                    Label(done == nil ? "Training starten" : "Nochmal starten", systemImage: "play.fill")
                        .frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Workout in den Plan legen oder ändern
struct PlanEditSheet: View {
    let store: GymStore
    let entry: PlanEntry?
    let day: String
    @Environment(\.dismiss) private var dismiss
    enum Kind: String, CaseIterable { case weekly = "Wöchentlich", every = "Alle n Tage", once = "Einmalig" }
    @State private var tpl = ""
    @State private var hasTime = true
    @State private var time = Date()
    @State private var dur = 60
    @State private var kind: Kind = .weekly
    @State private var days: Set<Int> = []
    @State private var everyN = 2

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout") {
                    Picker("Workout", selection: $tpl) {
                        ForEach(store.templateList) { Text($0.title).tag($0.id) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Wann") {
                    Toggle("Mit Uhrzeit", isOn: $hasTime)
                    if hasTime {
                        DatePicker("Uhrzeit", selection: $time, displayedComponents: .hourAndMinute)
                    }
                    Picker("Dauer", selection: $dur) {
                        ForEach([30, 45, 60, 75, 90, 120], id: \.self) { Text("\($0) Min.").tag($0) }
                    }
                }
                Section("Wiederholung") {
                    Picker("Wiederholung", selection: $kind) {
                        ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    switch kind {
                    case .weekly:
                        HStack(spacing: 6) {
                            ForEach(0..<7, id: \.self) { i in
                                let on = days.contains(i)
                                Button {
                                    if on { days.remove(i) } else { days.insert(i) }
                                } label: {
                                    Text(Gym.dayShort[i]).font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                                        .foregroundStyle(on ? .white : .primary)
                                        .background(on ? OursPage.gym.color : Color(.tertiarySystemFill), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    case .every:
                        Stepper("Alle \(everyN) Tage", value: $everyN, in: 1...14)
                    case .once:
                        Text("Nur am \(Gym.date(day).formatted(.dateTime.weekday(.wide).day().month(.wide)))").foregroundStyle(.secondary)
                    }
                }
                if entry != nil {
                    Section {
                        Button("Aus dem Plan nehmen", role: .destructive) {
                            if let entry { store.deletePlan(entry) }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(entry == nil ? "In den Plan" : "Plan ändern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }.disabled(tpl.isEmpty || (kind == .weekly && days.isEmpty))
                }
            }
            .onAppear(perform: fill)
        }
    }

    private func fill() {
        tpl = entry?.tpl ?? store.templateList.first?.id ?? ""
        dur = entry?.dur ?? 60
        if let t = entry?.time ?? store.plan.values.compactMap(\.time).first {
            let p = t.split(separator: ":").compactMap { Int($0) }
            if p.count == 2 { time = Calendar.current.date(bySettingHour: p[0], minute: p[1], second: 0, of: Date()) ?? Date() }
        } else {
            time = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date()
        }
        hasTime = entry == nil || entry?.time != nil
        switch entry?.rep {
        case .weekly(let d): kind = .weekly; days = Set(d)
        case .every(let n, _): kind = .every; everyN = n
        case .once: kind = .once
        case nil: kind = .weekly; days = [Gym.weekday(day)]
        }
    }

    private func save() {
        let rep: PlanRepeat
        switch kind {
        case .weekly: rep = .weekly(Array(days))
        case .every:
            if case .every(_, let s) = entry?.rep { rep = .every(everyN, s) } else { rep = .every(everyN, day) }
        case .once:
            if case .once(let d) = entry?.rep { rep = .once(d) } else { rep = .once(day) }
        }
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        let t = hasTime ? String(format: "%02d:%02d", c.hour ?? 18, c.minute ?? 0) : nil
        store.savePlan(id: entry?.id, tpl: tpl, time: t, dur: dur, rep: rep)
        dismiss()
    }
}
