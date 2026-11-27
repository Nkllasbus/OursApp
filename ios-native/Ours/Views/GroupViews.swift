import SwiftUI
import UIKit

/// Liste aller Gruppen (Du → Gruppen)
struct GroupsView: View {
    @Environment(GroupStore.self) private var store
    @State private var showNew = false
    @State private var showJoin = false
    @State private var showImport = false
    @State private var candidates: [ImportCandidate] = []

    var body: some View {
        List {
            if store.groups.isEmpty && !candidates.isEmpty {
                Section {
                    Button { showImport = true } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "arrow.down.doc.fill")
                                .font(.title2).foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Bisherige Bereiche übernehmen").font(.headline).foregroundStyle(.primary)
                                Text("Deine gemeinsamen Bereiche von der Webseite werden zu deiner ersten Gruppe.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            if store.groups.isEmpty {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "person.3.fill").font(.system(size: 40)).foregroundStyle(.secondary)
                        Text("Noch keine Gruppe").font(.headline)
                        Text("Leg eine Gruppe für deinen Partner, deine Familie oder deine WG an. Darin teilt ihr Kalender, Einkaufslisten, Haushalt und mehr.")
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        HStack {
                            Button("Neue Gruppe") { showNew = true }.buttonStyle(.borderedProminent)
                            Button("Mit Code beitreten") { showJoin = true }.buttonStyle(.bordered)
                        }
                        .buttonBorderShape(.capsule)
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
            } else {
                Section {
                    ForEach(store.groups) { g in
                        NavigationLink(value: MeRoute.group(g.id)) { GroupRow(group: g) }
                    }
                } footer: {
                    Text("Du kannst in mehreren Gruppen sein, z. B. mit deinem Partner und mit deiner Familie.")
                }
            }
        }
        .navigationTitle("Gruppen")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Neue Gruppe", systemImage: "plus") { showNew = true }
                    Button("Mit Code beitreten", systemImage: "ticket") { showJoin = true }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showNew) { GroupEditSheet(group: nil) }
        .sheet(isPresented: $showJoin) { JoinGroupSheet(initialCode: "") }
        .sheet(isPresented: $showImport, onDismiss: reload) { ImportSheet(candidates: candidates) }
        .task(id: store.groups.count) { reload() }
    }

    private func reload() {
        Task { candidates = await store.detectImport() }
    }
}

struct GroupBadge: View {
    let group: OursGroup
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: group.kind.symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(group.color.gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

struct GroupRow: View {
    let group: OursGroup

    var body: some View {
        HStack(spacing: 12) {
            GroupBadge(group: group)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name).font(.body.weight(.semibold))
                Text(group.summary).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Eine Gruppe: Mitglieder, Rollen, Bereiche
struct GroupDetailView: View {
    let gid: String
    @Environment(GroupStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showInvite = false
    @State private var showEdit = false
    @State private var confirmLeave = false
    @State private var removing: GroupMember?
    @State private var errorText: String?

    var body: some View {
        if let g = store.group(gid) {
            let adult = g.isAdult(store.uid)
            List {
                Section {
                    VStack(spacing: 8) {
                        GroupBadge(group: g, size: 76)
                        Text(g.name).font(.title2.bold())
                        Text(g.summary).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(g.sortedMembers) { m in
                        MemberRow(member: m, isMe: m.id == store.uid)
                            .swipeActions(edge: .trailing) {
                                if adult && m.id != store.uid {
                                    Button("Entfernen", role: .destructive) { removing = m }
                                }
                            }
                            .contextMenu {
                                if adult && m.id != store.uid {
                                    if m.role == .child {
                                        Button("Zu Erwachsenen machen", systemImage: "person.fill") { store.setRole(.adult, for: m, in: g) }
                                    } else {
                                        Button("Zu Kind machen", systemImage: "figure.child") { store.setRole(.child, for: m, in: g) }
                                    }
                                    Button("Aus Gruppe entfernen", systemImage: "person.fill.xmark", role: .destructive) { removing = m }
                                }
                            }
                    }
                    if adult {
                        Button { showInvite = true } label: {
                            Label("Mitglied einladen", systemImage: "person.badge.plus")
                        }
                    }
                } header: {
                    Text("Mitglieder")
                } footer: {
                    Text(adult ? "Halte ein Mitglied gedrückt, um die Rolle zu ändern. Kinder sehen keine gemeinsamen Finanzen." : "Mitglieder verwalten können nur Erwachsene.")
                }

                Section("Gemeinsam") {
                    let visible = g.spaces.filter { store.canSee($0, in: g) }
                    if visible.isEmpty {
                        Text("Noch nichts geteilt. Kalender, Einkaufslisten und mehr kommen hier dazu, sobald ihr sie nutzt.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(visible) { s in
                        Label(spaceTitle(s, in: g), systemImage: SpaceType.symbol[s.type] ?? "square.grid.2x2")
                    }
                }

                Section {
                    if adult {
                        Button("Gruppe bearbeiten") { showEdit = true }
                    }
                    Button("Gruppe verlassen", role: .destructive) { confirmLeave = true }
                }
            }
            .navigationTitle(g.name)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showInvite) { InviteSheet(group: g) }
            .sheet(isPresented: $showEdit) { GroupEditSheet(group: g) }
            .confirmationDialog("„\(g.name)“ verlassen?", isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("Verlassen", role: .destructive) {
                    Task {
                        do { try await store.leave(g); dismiss() } catch { errorText = error.localizedDescription }
                    }
                }
            } message: {
                Text("Du siehst die gemeinsamen Termine, Listen und Bereiche dieser Gruppe dann nicht mehr.")
            }
            .confirmationDialog("\(removing?.name ?? "") entfernen?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button("Entfernen", role: .destructive) {
                    if let m = removing { store.remove(m, from: g) }
                    removing = nil
                }
            }
            .alert("Hinweis", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("OK") {}
            } message: {
                Text(errorText ?? "")
            }
        } else {
            ContentUnavailableView("Gruppe nicht gefunden", systemImage: "person.3",
                                   description: Text("Vielleicht wurdest du entfernt oder die Gruppe wurde gelöscht."))
        }
    }

    private func spaceTitle(_ s: GroupSpace, in g: OursGroup) -> String {
        let base = SpaceType.label[s.type] ?? s.type
        if let o = s.owner, let m = g.members.first(where: { $0.id == o }) { return "\(base) von \(m.name)" }
        return base
    }
}

struct MemberRow: View {
    let member: GroupMember
    let isMe: Bool

    var body: some View {
        HStack(spacing: 12) {
            Avatar(name: member.name, size: 38)
            Text(member.name + (isMe ? " (du)" : ""))
            Spacer()
            Text(member.role.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(member.role == .adult ? Color.accentColor : Color.orange)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background((member.role == .adult ? Color.accentColor : Color.orange).opacity(0.12), in: Capsule())
        }
    }
}

/// Neue Gruppe anlegen oder bestehende bearbeiten
struct GroupEditSheet: View {
    let group: OursGroup?
    @Environment(GroupStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: GroupKind = .family
    @State private var color = OursGroup.palette[0]
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        GroupBadge(group: OursGroup(id: "", name: name, kind: kind, colorHex: color, members: [], spaces: []), size: 76)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Art") {
                    Picker("Art", selection: $kind) {
                        ForEach(GroupKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: kind) {
                        if group == nil && (name.isEmpty || GroupKind.allCases.map(\.suggestedName).contains(name)) { name = kind.suggestedName }
                    }
                }
                Section("Name") {
                    TextField("z. B. Familie Müller", text: $name)
                }
                Section("Farbe") {
                    HStack(spacing: 12) {
                        ForEach(OursGroup.palette, id: \.self) { hex in
                            Circle()
                                .fill(Color(hexString: hex))
                                .frame(width: 30, height: 30)
                                .overlay(Circle().stroke(Color.primary.opacity(color == hex ? 0.55 : 0), lineWidth: 3).padding(-4))
                                .onTapGesture { color = hex }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red) }
                }
            }
            .navigationTitle(group == nil ? "Neue Gruppe" : "Gruppe bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(group == nil ? "Erstellen" : "Sichern") { save() }
                        .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sensoryFeedback(.selection, trigger: color)
            .onAppear {
                if let g = group { name = g.name; kind = g.kind; color = g.colorHex }
                else { name = kind.suggestedName; color = OursGroup.palette[store.groups.count % OursGroup.palette.count] }
            }
        }
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        if let g = group { store.update(g, name: n, kind: kind, color: color); dismiss(); return }
        busy = true
        Task {
            do { try await store.create(name: n, kind: kind, color: color); dismiss() }
            catch { errorText = "Das hat nicht geklappt. Prüf die Internetverbindung."; busy = false }
        }
    }
}

/// Einladungscode erstellen und teilen
struct InviteSheet: View {
    let group: OursGroup
    @Environment(GroupStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var role: GroupRole = .adult
    @State private var code: String?
    @State private var busy = false
    @State private var errorText: String?
    @State private var copied = false

    private var shareText: String {
        guard let code else { return "" }
        return "Komm in meine Gruppe „\(group.name)“ bei Ours! Öffne in der App „Du → Gruppen → Mit Code beitreten“ und gib diesen Code ein: \(code)\n\nOder tippe hier: ours://join/\(code)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Rolle", selection: $role) {
                        ForEach(GroupRole.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: role) { code = nil }
                } header: {
                    Text("Als was einladen?")
                } footer: {
                    Text(role == .adult ? "Erwachsene sehen und verwalten alles in der Gruppe." : "Kinder sehen Kalender, Einkaufslisten und Haushalt, aber keine gemeinsamen Finanzen. Sie bekommen später ein eigenes Konto mit Taschengeld.")
                }

                if let code {
                    Section {
                        VStack(spacing: 12) {
                            Text(code)
                                .font(.system(size: 34, weight: .bold, design: .monospaced))
                                .tracking(4)
                                .textSelection(.enabled)
                            Text("7 Tage gültig").font(.footnote).foregroundStyle(.secondary)
                            HStack {
                                ShareLink(item: shareText) {
                                    Label("Teilen", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                Button {
                                    UIPasteboard.general.string = code
                                    copied = true
                                } label: {
                                    Label(copied ? "Kopiert" : "Kopieren", systemImage: copied ? "checkmark" : "doc.on.doc").frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                            .buttonBorderShape(.capsule)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                } else {
                    Section {
                        Button {
                            make()
                        } label: {
                            HStack { Spacer(); if busy { ProgressView() } else { Text("Einladungscode erstellen").bold() }; Spacer() }
                        }
                        .disabled(busy)
                    }
                }
                if let errorText { Section { Text(errorText).foregroundStyle(.red) } }
            }
            .navigationTitle("Einladen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
            .sensoryFeedback(.success, trigger: code)
        }
        .presentationDetents([.medium, .large])
    }

    private func make() {
        busy = true; errorText = nil
        Task {
            do { code = try await store.createInvite(for: group, role: role) }
            catch { errorText = error.localizedDescription }
            busy = false
        }
    }
}

/// Mit Code beitreten (auch über den Link ours://join/CODE)
struct JoinGroupSheet: View {
    let initialCode: String
    @Environment(GroupStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var busy = false
    @State private var errorText: String?
    @State private var joined: String?

    var body: some View {
        NavigationStack {
            Form {
                if let joined {
                    Section {
                        VStack(spacing: 10) {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 52)).foregroundStyle(.green)
                            Text("Willkommen in „\(joined)“!").font(.headline)
                            Text("Die gemeinsamen Bereiche erscheinen gleich in der App.").font(.subheadline).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                } else {
                    Section {
                        TextField("Code, z. B. K7M2QX9A", text: $code)
                            .font(.system(.title3, design: .monospaced))
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .onSubmit(join)
                    } footer: {
                        Text("Den Code bekommst du von einem Erwachsenen der Gruppe.")
                    }
                    if let errorText { Section { Text(errorText).foregroundStyle(.red) } }
                }
            }
            .navigationTitle("Gruppe beitreten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if joined == nil {
                    ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Beitreten", action: join).disabled(busy || code.count < 6)
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
                }
            }
            .sensoryFeedback(.success, trigger: joined)
            .onAppear { if code.isEmpty { code = initialCode } }
        }
        .presentationDetents([.medium])
    }

    private func join() {
        busy = true; errorText = nil
        Task {
            do { joined = try await store.join(code: code) }
            catch let e as GroupError { errorText = e.errorDescription }
            catch { errorText = "Beitreten hat nicht geklappt. Prüf die Internetverbindung." }
            busy = false
        }
    }
}

/// Bisherige gemeinsame Bereiche der Webseite als erste Gruppe übernehmen
struct ImportSheet: View {
    let candidates: [ImportCandidate]
    @Environment(GroupStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<String> = []
    @State private var name = GroupKind.couple.suggestedName
    @State private var kind: GroupKind = .couple
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(candidates) { c in
                        Toggle(isOn: Binding(get: { picked.contains(c.sid) }, set: { on in if on { picked.insert(c.sid) } else { picked.remove(c.sid) } })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Label(SpaceType.label[c.type] ?? c.type, systemImage: SpaceType.symbol[c.type] ?? "square")
                                Text(c.people.values.sorted().joined(separator: ", "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Diese Bereiche übernehmen")
                } footer: {
                    Text("Alle Personen, mit denen du diese Bereiche schon teilst, kommen als Erwachsene in die Gruppe. Eure Daten bleiben, wie sie sind.")
                }
                Section("Gruppe") {
                    Picker("Art", selection: $kind) {
                        ForEach(GroupKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: kind) { name = kind.suggestedName }
                    TextField("Name", text: $name)
                }
                if let errorText { Section { Text(errorText).foregroundStyle(.red) } }
            }
            .navigationTitle("Übernehmen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") { run() }.disabled(busy || picked.isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { picked = Set(candidates.filter { $0.people.count > 1 }.map(\.sid)); if picked.isEmpty { picked = Set(candidates.map(\.sid)) } }
        }
    }

    private func run() {
        busy = true
        Task {
            do {
                try await store.importGroup(name: name.trimmingCharacters(in: .whitespaces), kind: kind,
                                            color: OursGroup.palette[0], from: candidates.filter { picked.contains($0.sid) })
                dismiss()
            } catch {
                errorText = "Das hat nicht geklappt. Sind die neuen Firebase-Regeln schon eingefügt?"
                busy = false
            }
        }
    }
}
