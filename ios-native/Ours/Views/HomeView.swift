import SwiftUI

struct HomeView: View {
    @Environment(Session.self) private var session

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<11: return "Guten Morgen"
        case 11..<17: return "Hallo"
        case 17..<22: return "Guten Abend"
        default: return "Gute Nacht"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(greeting), \(session.firstName)!").font(.title2.bold())
                        Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            .foregroundStyle(.secondary)
                    }
                    PageGrid()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Ours")
        }
    }
}

/// Kacheln für alle Bereiche
struct PageGrid: View {
    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: cols, spacing: 12) {
            ForEach(OursPage.allCases) { page in
                NavigationLink(value: page) {
                    PageTile(page: page)
                }
                .buttonStyle(PressStyle())
            }
        }
        .navigationDestination(for: OursPage.self) { page in
            PageDestination(page: page)
        }
    }
}

struct PageTile: View {
    let page: OursPage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: page.symbol)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 18)
            Text(page.label).font(.headline).foregroundStyle(.white)
            Text(page.subtitle).font(.caption).foregroundStyle(.white.opacity(0.85))
        }
        .padding(14)
        .frame(height: 118)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(page.color.gradient)
        )
    }
}

/// Leichtes Eindrücken beim Antippen
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Ziel je Bereich – wird Schritt für Schritt durch die echten Seiten ersetzt
struct PageDestination: View {
    let page: OursPage

    var body: some View {
        ComingSoonView(title: page.label, symbol: page.symbol, color: page.color,
                       text: "\(page.label) wird gerade für die App neu gebaut. Bis dahin findest du es auf der Webseite.")
    }
}
