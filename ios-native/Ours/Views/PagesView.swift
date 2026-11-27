import SwiftUI

/// „Seiten“ in der Leiste: Popup mit allen Bereichen (wie auf der Webseite)
struct PagesSheet: View {
    let open: (OursPage) -> Void
    @Environment(\.dismiss) private var dismiss
    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: cols, spacing: 14) {
                    ForEach(OursPage.allCases) { p in
                        Button {
                            dismiss()
                            open(p)
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: p.symbol)
                                    .font(.system(size: 24, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 60, height: 60)
                                    .background(p.color.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                Text(p.label).font(.footnote.weight(.medium)).foregroundStyle(.primary)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PressStyle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .navigationTitle("Seiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
        .presentationDetents([.height(320), .medium])
        .presentationDragIndicator(.visible)
    }
}
