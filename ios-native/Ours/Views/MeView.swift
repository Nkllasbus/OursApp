import SwiftUI

/// „Du“: Profil und Einstellungen wie in der Einstellungen-App
struct MeView: View {
    @Environment(Session.self) private var session
    @State private var confirmLogout = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        ProfileEditView()
                    } label: {
                        HStack(spacing: 14) {
                            Avatar(name: session.name, size: 56)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.name).font(.title3.weight(.semibold))
                                Text(session.email).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Allgemein") {
                    row("Freunde", symbol: "person.2.fill", color: .blue)
                    row("Mitteilungen", symbol: "bell.badge.fill", color: .red)
                    row("Datenschutz", symbol: "hand.raised.fill", color: .gray)
                }

                Section {
                    Button("Abmelden", role: .destructive) { confirmLogout = true }
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Du")
            .confirmationDialog("Wirklich abmelden?", isPresented: $confirmLogout, titleVisibility: .visible) {
                Button("Abmelden", role: .destructive) { session.signOut() }
            }
        }
    }

    private func row(_ title: String, symbol: String, color: Color) -> some View {
        NavigationLink {
            ComingSoonView(title: title, symbol: symbol, color: color, text: "Kommt in einer der nächsten Versionen.")
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 29, height: 29)
                    .background(color, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
    }
}

struct Avatar: View {
    let name: String
    var size: CGFloat = 40

    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color.accentColor.gradient, in: Circle())
    }
}

struct ProfileEditView: View {
    @Environment(Session.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    Avatar(name: name.isEmpty ? session.name : name, size: 96)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
            Section {
                TextField("Dein Name", text: $name)
                    .textContentType(.name)
            } header: {
                Text("Name")
            } footer: {
                Text("Deinen Namen sehen deine Freunde.")
            }
        }
        .navigationTitle("Mein Profil")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Fertig") {
                    session.rename(name.trimmingCharacters(in: .whitespaces))
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear { name = session.name }
    }
}
