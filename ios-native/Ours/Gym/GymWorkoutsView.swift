import SwiftUI

/// Workouts (Vorlagen) und Übungen verwalten
struct GymWorkoutsView: View {
    let store: GymStore
    @State private var editTemplate: WorkoutTemplate?
    @State private var newTemplate = false
    @State private var editExercise: Exercise?
    @State private var newExercise = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Workouts").font(.title3.bold())
                    Spacer()
                    Button { newTemplate = true } label: { Label("Neu", systemImage: "plus") }
                        .buttonStyle(.bordered).buttonBorderShape(.capsule)
                        .disabled(store.exercises.isEmpty)
                }
                if store.templateList.isEmpty {
                    Text(store.exercises.isEmpty ? "Leg zuerst unten ein paar Übungen an. Danach fasst du sie zu einem Workout zusammen, z. B. „Push“."
                                                 : "Fass deine Übungen zu einem Workout zusammen, z. B. „Push“ oder „Beine“.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(store.templateList) { t in
                    Button { editTemplate = t } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(t.title).font(.headline).foregroundStyle(.primary)
                                Text(store.exercises(of: t).map(\.name).joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
                            }
                            Spacer()
                            Text("\(t.ex.count)").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(14)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(PressStyle())
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Übungen").font(.title3.bold())
                    Spacer()
                    Button { newExercise = true } label: { Label("Neu", systemImage: "plus") }
                        .buttonStyle(.bordered).buttonBorderShape(.capsule)
                }
                let groups = MuscleGroup.all.filter { g in store.exerciseList.contains { $0.group == g.id } }
                ForEach(groups) { g in
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(g.emoji) \(g.name)").font(.subheadline.weight(.semibold)).foregroundStyle(g.color)
                            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 4)
                        ForEach(store.exerciseList.filter { $0.group == g.id }) { x in
                            Button { editExercise = x } label: {
                                HStack(spacing: 12) {
                                    ExerciseThumb(exercise: x, size: 38)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(x.name).foregroundStyle(.primary)
                                        Text(x.detail).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 6)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .sheet(item: $editTemplate) { t in TemplateEditSheet(store: store, template: t) }
        .sheet(isPresented: $newTemplate) { TemplateEditSheet(store: store, template: nil) }
        .sheet(item: $editExercise) { x in ExerciseEditSheet(store: store, exercise: x, group: x.group) }
        .sheet(isPresented: $newExercise) { ExerciseEditSheet(store: store, exercise: nil, group: "brust") }
    }
}

struct TemplateEditSheet: View {
    let store: GymStore
    let template: WorkoutTemplate?
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var picked: Set<String> = []
    @State private var confirmDelete = false
    @State private var newExercise = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("z. B. Push", text: $title)
                    if template == nil {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(["Push", "Pull", "Beine", "Oberkörper", "Ganzkörper", "Cardio"], id: \.self) { s in
                                    Button(s) { title = s }.buttonStyle(.bordered).buttonBorderShape(.capsule)
                                }
                            }
                        }
                    }
                }
                ForEach(MuscleGroup.all.filter { g in store.exerciseList.contains { $0.group == g.id } }) { g in
                    Section("\(g.emoji) \(g.name)") {
                        ForEach(store.exerciseList.filter { $0.group == g.id }) { x in
                            Button {
                                if picked.contains(x.id) { picked.remove(x.id) } else { picked.insert(x.id) }
                            } label: {
                                HStack {
                                    Image(systemName: picked.contains(x.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(picked.contains(x.id) ? OursPage.gym.color : Color.secondary)
                                        .font(.title3)
                                    Text(x.name).foregroundStyle(.primary)
                                    Spacer()
                                    Text(x.detail).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Section {
                    Button { newExercise = true } label: { Label("Neue Übung", systemImage: "plus") }
                }
                if template != nil {
                    Section { Button("Workout löschen", role: .destructive) { confirmDelete = true } }
                }
            }
            .navigationTitle(template == nil ? "Neues Workout" : "Workout bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        store.saveTemplate(id: template?.id, title: title.trimmingCharacters(in: .whitespaces), ex: Array(picked))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || picked.isEmpty)
                }
            }
            .confirmationDialog("Workout löschen? Es verschwindet auch aus dem Plan.", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) { if let template { store.deleteTemplate(template) }; dismiss() }
            }
            .sheet(isPresented: $newExercise) { ExerciseEditSheet(store: store, exercise: nil, group: "brust") { id in _ = picked.insert(id) } }
            .sensoryFeedback(.selection, trigger: picked)
            .onAppear { title = template?.title ?? ""; picked = Set(template?.ex ?? []) }
        }
    }
}

struct ExerciseEditSheet: View {
    let store: GymStore
    let exercise: Exercise?
    let group: String
    var onSave: ((String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var groupID = "brust"
    @State private var sets = ""
    @State private var reps = ""
    @State private var kg = ""
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Muskelgruppe") {
                    Picker("Muskelgruppe", selection: $groupID) {
                        ForEach(MuscleGroup.all) { Text("\($0.emoji) \($0.name)").tag($0.id) }
                    }
                }
                Section("Name") {
                    TextField("z. B. Bankdrücken", text: $name)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(MuscleGroup.of(groupID).suggestions, id: \.self) { s in
                                Button(s) { name = s }.buttonStyle(.bordered).buttonBorderShape(.capsule)
                            }
                        }
                    }
                }
                Section {
                    HStack { Text("Sätze"); Spacer(); TextField("3", text: $sets).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80) }
                    HStack { Text(groupID == "cardio" ? "Minuten" : "Wiederholungen"); Spacer(); TextField("10", text: $reps).multilineTextAlignment(.trailing).frame(width: 80) }
                    if groupID != "cardio" {
                        HStack { Text("Gewicht (kg)"); Spacer(); TextField("0", text: $kg).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80) }
                    }
                } header: {
                    Text("Vorgabe")
                } footer: {
                    Text("Beim Training schlägt Ours danach automatisch die Werte vom letzten Mal vor.")
                }
                if exercise != nil {
                    Section { Button("Übung löschen", role: .destructive) { confirmDelete = true } }
                }
            }
            .navigationTitle(exercise == nil ? "Neue Übung" : "Übung bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        let id = store.saveExercise(id: exercise?.id, name: name.trimmingCharacters(in: .whitespaces), group: groupID,
                                                    sets: Int(sets), reps: reps.trimmingCharacters(in: .whitespaces),
                                                    kg: Double(kg.replacingOccurrences(of: ",", with: ".")))
                        onSave?(id)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("Übung löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) { if let exercise { store.deleteExercise(exercise) }; dismiss() }
            }
            .onAppear {
                groupID = exercise?.group ?? group
                name = exercise?.name ?? ""
                sets = exercise?.sets.map(String.init) ?? ""
                reps = exercise?.reps ?? ""
                kg = exercise?.kg.map { Gym.fmtKg($0) } ?? ""
            }
        }
    }
}
