import SwiftUI
import FirebaseCore
import FirebaseDatabase

@main
struct OursApp: App {
    @State private var session: Session

    init() {
        FirebaseConfig.configure()
        if FirebaseConfig.isReady {
            // Daten bleiben auf dem Gerät gespeichert: die App startet sofort und funktioniert offline
            Database.database().persistenceCacheSizeBytes = 80 * 1024 * 1024   // viele Umsätze: großer Speicher
            Database.database().isPersistenceEnabled = true
        }
        _session = State(initialValue: Session())
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !FirebaseConfig.isReady {
                    SetupMissingView()
                } else if !session.checked {
                    LaunchView()
                } else if session.user == nil {
                    LoginView()
                } else {
                    RootView()
                }
            }
            .environment(session)
            .tint(Color.accentColor)
            .preferredColorScheme(.light)
            .onAppear { session.start() }
        }
    }
}

/// Startbildschirm, solange die Anmeldung geprüft wird
struct LaunchView: View {
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            ProgressView()
        }
    }
}

/// Hinweis für die Entwicklung: Firebase-iOS-App noch nicht eingetragen
struct SetupMissingView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "wrench.and.screwdriver").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Noch nicht fertig eingerichtet").font(.title2.bold())
            Text("In der Datei FirebaseConfig.swift fehlt die App-ID der iOS-App aus der Firebase-Konsole.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
        .padding(32)
    }
}
