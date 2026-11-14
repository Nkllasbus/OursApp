import Foundation
import FirebaseCore

/// Firebase-Einstellungen. Diese Werte sind öffentlich (wie in der Webseite) und kein Geheimnis.
enum FirebaseConfig {
    static let apiKey = "AIzaSyD6JNwGczfmHYTqHp9qI5bnutz-JLphgGI"
    static let projectID = "oursapp-ff4cf"
    static let gcmSenderID = "509984933255"
    static let databaseURL = "https://oursapp-ff4cf-default-rtdb.europe-west1.firebasedatabase.app"
    static let storageBucket = "oursapp-ff4cf.firebasestorage.app"
    /// App-ID der iOS-App aus der Firebase-Konsole (Projekteinstellungen → Meine Apps → iOS-App „de.nkllasbus.ours“).
    /// Sieht aus wie 1:509984933255:ios:abc123…
    static let iosAppID = ""

    static var isReady: Bool { iosAppID.contains(":ios:") }

    static func configure() {
        guard isReady, FirebaseApp.app() == nil else { return }
        let o = FirebaseOptions(googleAppID: iosAppID, gcmSenderID: gcmSenderID)
        o.apiKey = apiKey
        o.projectID = projectID
        o.databaseURL = databaseURL
        o.storageBucket = storageBucket
        o.bundleID = Bundle.main.bundleIdentifier ?? "de.nkllasbus.ours"
        FirebaseApp.configure(options: o)
    }
}
