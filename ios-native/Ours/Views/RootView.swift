import SwiftUI

/// Leiste unten wie auf der Webseite: Home · Feed · Seiten · Chats · Du
struct RootView: View {
    enum Tab: Hashable { case home, feed, pages, chats, me }
    @State private var tab: Tab = .home

    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(Tab.home)
            NavigationStack {
                ComingSoonView(title: "Feed", symbol: "newspaper", color: .accentColor,
                               text: "Hier siehst du bald, was deine Freunde machen: neue Rezepte, Trainings und Termine.")
            }
                .tabItem { Label("Feed", systemImage: "newspaper") }
                .tag(Tab.feed)
            PagesView()
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
    }
}
