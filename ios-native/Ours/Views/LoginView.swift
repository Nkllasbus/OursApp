import SwiftUI

/// Anmelden und Registrieren im iOS-Stil
struct LoginView: View {
    @Environment(Session.self) private var session
    enum Mode: String, CaseIterable { case login = "Anmelden", register = "Registrieren" }
    @State private var mode: Mode = .login
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var message: String?
    @State private var isError = false
    @FocusState private var focus: Field?
    enum Field { case name, email, password }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "heart.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(Color.accentColor)
                        Text("Ours").font(.largeTitle.bold())
                        Text("Euer gemeinsamer Alltag an einem Ort.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .listRowBackground(Color.clear)
                }

                Section {
                    Picker("Modus", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    if mode == .register {
                        TextField("Dein Name", text: $name)
                            .textContentType(.name)
                            .focused($focus, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { focus = .email }
                    }
                    TextField("E-Mail", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                    SecureField(mode == .register ? "Passwort (mind. 6 Zeichen)" : "Passwort", text: $password)
                        .textContentType(mode == .register ? .newPassword : .password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { Task { await go() } }
                } footer: {
                    if let message {
                        Text(message).foregroundStyle(isError ? Color.red : Color.secondary)
                    }
                }

                Section {
                    Button {
                        Task { await go() }
                    } label: {
                        HStack {
                            Spacer()
                            if busy { ProgressView().tint(.white) } else { Text(mode.rawValue).bold() }
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .disabled(busy)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    if mode == .login {
                        Button("Passwort vergessen?") { Task { await forgot() } }
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .animation(.default, value: mode)
            .onChange(of: mode) { message = nil }
        }
    }

    private func say(_ text: String, error: Bool) { message = text; isError = error }

    private func go() async {
        let mail = email.trimmingCharacters(in: .whitespaces)
        guard !mail.isEmpty, !password.isEmpty else { return say("Gib E-Mail und Passwort ein.", error: true) }
        if mode == .register && name.trimmingCharacters(in: .whitespaces).isEmpty { return say("Gib deinen Namen ein.", error: true) }
        busy = true; message = nil
        defer { busy = false }
        do {
            if mode == .register {
                try await session.register(name: name.trimmingCharacters(in: .whitespaces), email: mail, password: password)
            } else {
                try await session.signIn(email: mail, password: password)
            }
        } catch {
            say(Session.message(for: error), error: true)
        }
    }

    private func forgot() async {
        let mail = email.trimmingCharacters(in: .whitespaces)
        guard !mail.isEmpty else { return say("Gib oben deine E-Mail ein, dann schicken wir dir einen Link.", error: true) }
        do {
            try await session.resetPassword(email: mail)
            say("Wenn es ein Konto mit dieser E-Mail gibt, ist eine Mail zum Zurücksetzen unterwegs.", error: false)
        } catch {
            say(Session.message(for: error), error: true)
        }
    }
}
