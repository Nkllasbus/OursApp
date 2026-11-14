import SwiftUI

/// Die Bereiche von Ours mit Farbe und Symbol (gleiche Farben wie auf der Webseite)
enum OursPage: String, CaseIterable, Identifiable {
    case dates, recipes, chores, budget, gym, calendar, trips, mail

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dates: "Dateideen"
        case .recipes: "Rezepte"
        case .chores: "Haushalt"
        case .budget: "Budget"
        case .gym: "Gym"
        case .calendar: "Kalender"
        case .trips: "Reisen"
        case .mail: "Mail"
        }
    }

    var subtitle: String {
        switch self {
        case .dates: "Ideen für eure Dates"
        case .recipes: "Sammlung & Swipen"
        case .chores: "Aufgaben teilen"
        case .budget: "Konten & Verträge"
        case .gym: "Plan & Training"
        case .calendar: "Gemeinsame Termine"
        case .trips: "Packliste & Plan"
        case .mail: "Gmail lesen"
        }
    }

    var symbol: String {
        switch self {
        case .dates: "lightbulb.fill"
        case .recipes: "fork.knife"
        case .chores: "house.fill"
        case .budget: "eurosign.circle.fill"
        case .gym: "dumbbell.fill"
        case .calendar: "calendar"
        case .trips: "airplane"
        case .mail: "envelope.fill"
        }
    }

    var color: Color {
        switch self {
        case .dates: Color(hex: 0xD04D66)
        case .recipes: Color(hex: 0xD98E30)
        case .chores: Color(hex: 0x9A60BD)
        case .budget: Color(hex: 0x3E9E60)
        case .gym: Color(hex: 0x5A5BB8)
        case .calendar: Color(hex: 0xCF4B42)
        case .trips: Color(hex: 0x25A199)
        case .mail: Color(hex: 0x2F72C4)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}
