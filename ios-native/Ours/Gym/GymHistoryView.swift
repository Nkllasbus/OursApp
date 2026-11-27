import SwiftUI

/// Verlauf: abgeschlossene Trainings
struct GymHistoryView: View {
    let store: GymStore
    @State private var open: TrainingSession?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let month = store.history.filter { Gym.date($0.date) >= Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))! }
            HStack(spacing: 10) {
                StatTile(value: "\(month.count)", label: "Trainings im Monat")
                StatTile(value: "\(Int(month.reduce(0) { $0 + $1.dur } / 60))", label: "Minuten")
                StatTile(value: "\(store.history.count)", label: "Gesamt")
            }
            if store.history.isEmpty {
                Text("Noch kein Training abgeschlossen.").foregroundStyle(.secondary).padding(.top, 8)
            }
            ForEach(store.history.prefix(60)) { s in
                Button { open = s } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.title(of: s)).font(.headline).foregroundStyle(.primary)
                            Text("\(Gym.date(s.date).formatted(.dateTime.weekday(.abbreviated).day().month())) · \(Gym.fmtDur(s.dur))\(s.vol > 0 ? " · \(Int(s.vol)) kg bewegt" : "")")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(PressStyle())
            }
        }
        .sheet(item: $open) { s in
            NavigationStack { SessionSummaryView(store: store, session: s, justFinished: false) }
        }
    }
}

struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.bold()).foregroundStyle(OursPage.gym.color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Zusammenfassung eines Trainings
struct SessionSummaryView: View {
    let store: GymStore
    let session: TrainingSession
    let justFinished: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        List {
            Section {
                VStack(spacing: 6) {
                    if justFinished {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 50)).foregroundStyle(.green)
                        Text("Stark gemacht!").font(.title2.bold())
                    }
                    Text(store.title(of: session)).font(.headline)
                    Text(Gym.date(session.date).formatted(.dateTime.weekday(.wide).day().month(.wide))).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
                HStack(spacing: 10) {
                    StatTile(value: Gym.fmtDur(session.dur), label: "Dauer")
                    StatTile(value: "\(store.exercises(in: session).reduce(0) { $0 + session.doneSets($1.id).count })", label: "Sätze")
                    StatTile(value: "\(Int(session.vol))", label: "kg bewegt")
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if justFinished {
                Section("Wie war's?") {
                    Picker("Gefühl", selection: Binding(get: { store.sessions[session.id]?.feel ?? "" }, set: { store.setFeel(session, $0) })) {
                        Text("Leicht").tag("easy"); Text("Gut").tag("good"); Text("Hart").tag("hard")
                    }
                    .pickerStyle(.segmented)
                }
            }
            ForEach(store.exercises(in: session)) { x in
                let sets = session.doneSets(x.id)
                if !sets.isEmpty {
                    Section(x.name) {
                        ForEach(Array(sets.enumerated()), id: \.offset) { i, z in
                            HStack {
                                Text("Satz \(i + 1)").foregroundStyle(.secondary)
                                Spacer()
                                Text(x.isCardio ? "\(Int(z.r ?? 0)) min" : "\(Int(z.r ?? 0)) × \(Gym.fmtKg(z.kg ?? 0)) kg")
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
            if !justFinished {
                Section { Button("Training löschen", role: .destructive) { confirmDelete = true } }
            }
        }
        .navigationTitle(justFinished ? "Geschafft" : "Training")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        .confirmationDialog("Training löschen? Das lässt sich nicht rückgängig machen.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { store.deleteSession(session); dismiss() }
        }
        .sensoryFeedback(.success, trigger: justFinished)
    }
}
