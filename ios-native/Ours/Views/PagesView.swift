import SwiftUI

/// „Seiten“ in der Leiste: Popup über der Leiste, das mit einer Feder-Animation aufgeht (wie ein iOS-Menü)
struct PagesPopup: View {
    let open: (OursPage) -> Void
    private let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Seiten").font(.headline).padding(.leading, 4)
            LazyVGrid(columns: cols, spacing: 14) {
                ForEach(OursPage.allCases) { p in
                    Button { open(p) } label: {
                        VStack(spacing: 7) {
                            Image(systemName: p.symbol)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(p.color.gradient, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                            Text(p.label).font(.footnote.weight(.medium)).foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PressStyle())
                }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
    }
}
