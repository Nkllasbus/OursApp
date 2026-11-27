import SwiftUI

/// Laufendes Training im Vollbild: Sätze abhaken, Werte anpassen, Pausentimer
struct TrainingView: View {
    let store: GymStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmEnd = false
    @State private var confirmCancel = false
    @State private var summary: TrainingSession?
    @State private var tick = 0

    var body: some View {
        NavigationStack {
            Group {
                if let s = store.activeSession {
                    ScrollView {
                        VStack(spacing: 14) {
                            TimelineView(.periodic(from: .now, by: 1)) { _ in
                                Text(Gym.fmtDur((DB.nowMs - s.start) / 1000))
                                    .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                                    .frame(maxWidth: .infinity)
                            }
                            RestBar(store: store)
                            ForEach(store.exercises(in: s)) { x in
                                ExerciseSetsCard(store: store, session: s, exercise: x, tick: $tick)
                            }
                            if store.exercises(in: s).isEmpty {
                                Text("Dieses Workout hat keine Übungen.").foregroundStyle(.secondary)
                            }
                            Button {
                                let any = store.exercises(in: s).contains { !s.doneSets($0.id).isEmpty }
                                if any { finish(s) } else { confirmEnd = true }
                            } label: {
                                Text("Training beenden").bold().frame(maxWidth: .infinity).padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                            .padding(.top, 6)
                            Button("Training abbrechen (nicht speichern)", role: .destructive) { confirmCancel = true }
                                .font(.subheadline)
                            Text("Der Bildschirm bleibt an, solange das Training läuft.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(16)
                    }
                    .background(Color(.systemGroupedBackground))
                    .navigationTitle(store.title(of: s))
                    .confirmationDialog("Noch kein Satz abgehakt – trotzdem beenden?", isPresented: $confirmEnd, titleVisibility: .visible) {
                        Button("Beenden") { finish(s) }
                    }
                    .confirmationDialog("Training abbrechen? Es wird nicht gespeichert.", isPresented: $confirmCancel, titleVisibility: .visible) {
                        Button("Abbrechen und verwerfen", role: .destructive) { store.cancelTraining(s); dismiss() }
                    }
                } else if let summary {
                    SessionSummaryView(store: store, session: store.sessions[summary.id] ?? summary, justFinished: true)
                } else {
                    ContentUnavailableView("Kein Training aktiv", systemImage: "dumbbell")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down") }
                        .accessibilityLabel("Minimieren")
                }
            }
            .sensoryFeedback(.impact(weight: .light), trigger: tick)
        }
        .tint(OursPage.gym.color)
    }

    private func finish(_ s: TrainingSession) {
        store.endTraining(s)
        summary = store.sessions[s.id] ?? s
    }
}

/// Pause nach dem Satz: Countdown und Auswahl der Pausenlänge
struct RestBar: View {
    let store: GymStore

    var body: some View {
        VStack(spacing: 10) {
            if let end = store.restEnd {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let left = end.timeIntervalSince(ctx.date)
                    HStack {
                        Image(systemName: "timer")
                        Text(left > 0 ? "Pause: \(Gym.fmtDur(left))" : "Pause vorbei – weiter geht's!")
                            .font(.headline.monospacedDigit())
                        Spacer()
                        Button("Überspringen") { store.stopRest() }.font(.subheadline)
                    }
                    .padding(12)
                    .foregroundStyle(left > 0 ? Color.primary : Color.green)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            HStack(spacing: 6) {
                Text("Pause").font(.subheadline).foregroundStyle(.secondary)
                ForEach([60, 90, 120, 180, 0], id: \.self) { v in
                    Button(v == 0 ? "aus" : Gym.fmtDur(Double(v))) { store.restSeconds = v }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .foregroundStyle(store.restSeconds == v ? Color.white : Color.primary)
                        .background(store.restSeconds == v ? OursPage.gym.color : Color(.tertiarySystemFill), in: Capsule())
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

struct ExerciseThumb: View {
    let exercise: Exercise
    var size: CGFloat = 46

    var body: some View {
        Group {
            if let url = exercise.imageURL {
                AsyncImage(url: url) { img in img.resizable().scaledToFill() } placeholder: { placeholder }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var placeholder: some View {
        let g = MuscleGroup.of(exercise.group)
        return ZStack { g.color.opacity(0.15); Text(g.emoji).font(.system(size: size * 0.45)) }
    }
}

struct ExerciseSetsCard: View {
    let store: GymStore
    let session: TrainingSession
    let exercise: Exercise
    @Binding var tick: Int

    var body: some View {
        let s = store.sessions[session.id] ?? session
        let n = store.setCount(s, exercise)
        let cur = s.setsFor(exercise.id)
        let doneN = cur.filter(\.done).count
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ExerciseThumb(exercise: exercise)
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name).font(.headline)
                    Text(store.lastText(s, exercise).map { "Letztes Mal: \($0)" } ?? "Zum ersten Mal – pass die Werte an und hak jeden Satz ab.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(doneN)/\(n)").font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(doneN >= n ? Color.green : Color.secondary)
            }
            HStack {
                Text("Satz").frame(width: 40, alignment: .leading)
                Text(exercise.isCardio ? "Minuten" : "Wdh.").frame(maxWidth: .infinity)
                if !exercise.isCardio { Text("kg").frame(maxWidth: .infinity) }
            }
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(0..<n, id: \.self) { k in
                let done = k < cur.count && cur[k].done
                HStack(spacing: 8) {
                    Button {
                        store.toggleDone(s, exercise, k); tick += 1
                    } label: {
                        ZStack {
                            Circle().fill(done ? Color.green : Color(.tertiarySystemFill)).frame(width: 36, height: 36)
                            if done { Image(systemName: "checkmark").font(.subheadline.bold()).foregroundStyle(.white) }
                            else { Text("\(k + 1)").font(.subheadline.weight(.semibold)) }
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(width: 40, alignment: .leading)
                    ValueStepper(store: store, session: s, exercise: exercise, k: k, reps: true)
                    if !exercise.isCardio {
                        ValueStepper(store: store, session: s, exercise: exercise, k: k, reps: false)
                    }
                }
                .opacity(done ? 0.75 : 1)
            }
            Button { store.addSet(s, exercise) } label: { Label("Satz", systemImage: "plus") }
                .font(.subheadline.weight(.semibold))
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// − Wert + (Wiederholungen oder Gewicht)
struct ValueStepper: View {
    let store: GymStore
    let session: TrainingSession
    let exercise: Exercise
    let k: Int
    let reps: Bool
    @State private var text = ""
    @FocusState private var focused: Bool

    private var value: Double { store.value(session, exercise, k, reps: reps) }

    var body: some View {
        HStack(spacing: 4) {
            Button { change(-1) } label: { Image(systemName: "minus").frame(width: 28, height: 32) }
            TextField("", text: $text)
                .multilineTextAlignment(.center)
                .keyboardType(reps ? .numberPad : .decimalPad)
                .font(.body.monospacedDigit().weight(.semibold))
                .focused($focused)
                .frame(minWidth: 36)
                .onSubmit(commit)
                .onChange(of: focused) { if !focused { commit() } }
            Button { change(1) } label: { Image(systemName: "plus").frame(width: 28, height: 32) }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .padding(.horizontal, 4)
        .background(Color(.tertiarySystemFill), in: Capsule())
        .frame(maxWidth: .infinity)
        .onAppear { text = format(value) }
        .onChange(of: value) { if !focused { text = format(value) } }
    }

    private func format(_ v: Double) -> String { reps ? String(Int(v)) : Gym.fmtKg(v) }

    private func change(_ d: Double) {
        let v = value, nv = max(0, ((v + d * store.step(exercise, reps: reps, at: v)) * 100).rounded() / 100)
        save(nv); text = format(nv)
    }

    private func commit() {
        guard let v = Double(text.replacingOccurrences(of: ",", with: ".")), v >= 0 else { text = format(value); return }
        save(v)
    }

    private func save(_ v: Double) {
        if reps { store.saveSet(session, exercise, k, r: v) } else { store.saveSet(session, exercise, k, kg: v) }
    }
}
