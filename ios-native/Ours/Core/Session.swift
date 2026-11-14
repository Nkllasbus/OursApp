import Foundation
import Observation
import FirebaseAuth
import FirebaseDatabase

/// Anmeldung und Profil des angemeldeten Nutzers. Gleiche Daten wie die Webseite:
/// users/<uid>/profile/name und pub/<uid>/name
@MainActor
@Observable
final class Session {
    var user: FirebaseAuth.User?
    var name: String = ""
    var checked = false
    private var handle: AuthStateDidChangeListenerHandle?
    private var started = false
    /// Name aus der Registrierung, bis das Profil gespeichert ist
    private var pendingName: String?

    var uid: String? { user?.uid }
    var email: String { user?.email ?? "" }
    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }

    func start() {
        guard !started, FirebaseConfig.isReady else { return }
        started = true
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, u in
            Task { @MainActor in
                guard let self else { return }
                self.user = u
                if let u { await self.loadProfile(u) } else { self.name = "" }
                self.checked = true
            }
        }
    }

    private func loadProfile(_ u: FirebaseAuth.User) async {
        let db = Database.database().reference()
        let snap = try? await db.child("users/\(u.uid)/profile").getData()
        var n = (snap?.value as? [String: Any])?["name"] as? String ?? ""
        if n.isEmpty {
            n = pendingName ?? u.displayName ?? String((u.email ?? "Ich").split(separator: "@").first ?? "Ich")
            db.child("users/\(u.uid)/profile/name").put(n)
        }
        pendingName = nil
        name = n
        let pub = try? await db.child("pub/\(u.uid)/name").getData()
        if (pub?.value as? String) != n { db.child("pub/\(u.uid)/name").put(n) }
    }

    func signIn(email: String, password: String) async throws {
        _ = try await Auth.auth().signIn(withEmail: email, password: password)
    }

    func register(name: String, email: String, password: String) async throws {
        pendingName = String(name.prefix(30))
        _ = try await Auth.auth().createUser(withEmail: email, password: password)
    }

    func resetPassword(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
    }

    func rename(_ newName: String) {
        guard let uid, !newName.isEmpty else { return }
        let n = String(newName.prefix(30))
        name = n
        let db = Database.database().reference()
        db.child("users/\(uid)/profile/name").put(n)
        db.child("pub/\(uid)/name").put(n)
    }

    func signOut() {
        try? Auth.auth().signOut()
    }

    /// Verständliche Fehlermeldungen auf Deutsch
    static func message(for error: Error) -> String {
        let code = AuthErrorCode(rawValue: (error as NSError).code)
        switch code {
        case .invalidEmail: return "Diese E-Mail-Adresse ist ungültig."
        case .emailAlreadyInUse: return "Mit dieser E-Mail gibt es schon ein Konto. Melde dich an."
        case .weakPassword: return "Das Passwort ist zu kurz. Nimm mindestens 6 Zeichen."
        case .wrongPassword, .invalidCredential, .userNotFound: return "E-Mail oder Passwort stimmen nicht."
        case .tooManyRequests: return "Zu viele Versuche. Warte kurz und versuch es nochmal."
        case .networkError: return "Keine Internetverbindung."
        case .userDisabled: return "Dieses Konto ist gesperrt."
        default: return "Das hat nicht geklappt. Versuch es nochmal."
        }
    }
}

extension DatabaseReference {
    /// Speichern ohne auf die Antwort zu warten (offline landet es in der Warteschlange)
    func put(_ value: Any?) {
        setValue(value) { _, _ in }
    }
}
