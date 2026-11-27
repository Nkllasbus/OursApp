import SwiftUI

/// Leiste unten wie auf der Webseite: Home · Feed · Seiten · Chats · Du
struct RootView: View {
    enum Tab: Hashable { case home, feed, pages, chats, me }
    @Environment(Session.self) private var session
    @State private var tab: Tab = .home
    @State private var groups = GroupStore()
    @State private var joinCode = ""
    @State private var showJoin = false
    @State private var showPages = false
    @State private var homePath: [OursPage] = []

    var body: some View {
        // „Seiten“ wechselt nicht den Reiter, sondern öffnet das Popup
        TabView(selection: Binding(get: { tab }, set: { new in
            if new == .pages { showPages = true } else { tab = new }
        })) {
            HomeView(path: $homePath)
                .tabItem { Label("Home", systemImage: "house") }
                .tag(Tab.home)
            NavigationStack {
                ComingSoonView(title: "Feed", symbol: "newspaper", color: .accentColor,
                               text: "Hier siehst du bald, was deine Freunde machen: neue Rezepte, Trainings und Termine.")
            }
                .tabItem { Label("Feed", systemImage: "newspaper") }
                .tag(Tab.feed)
            Color.clear
                .tabItem { Label("Seiten", systemImage: "square.grid.2x2") }
                .tag(Tab.pages)
            NavigationStack {
                ComingSoonView(title: "Chats", symbol: "bubble.left.and.bubble.right", color: .accentColor,
                               text: "Chats mit deinen Freunden kommen in einer der nächsten Versionen.")
            }
                .tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right") }
                .tag(Tab.chats)
            MeView()
                .tabItem { Label("Du", systemImage: "person.crop.circle") }
                .tag(Tab.me)
        }
        .sensoryFeedback(.selection, trigger: tab)
        .environment(groups)
        .task(id: session.uid) {
            if let uid = session.uid { groups.start(uid: uid, name: session.name) }
        }
        .onChange(of: session.name) { groups.setName(session.name) }
        // Einladungslink ours://join/CODE
        .onOpenURL { url in
            guard url.scheme == "ours", url.host == "join" else { return }
            joinCode = url.lastPathComponent
            tab = .me
            showJoin = true
        }
        .sheet(isPresented: $showPages) {
            PagesSheet { page in
                tab = .home
                homePath = [page]
            }
        }
        .sheet(isPresented: $showJoin) {
            JoinGroupSheet(initialCode: joinCode).environment(groups)
        }
    }
}
