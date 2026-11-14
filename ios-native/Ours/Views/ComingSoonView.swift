import SwiftUI

struct ComingSoonView: View {
    let title: String
    let symbol: String
    let color: Color
    let text: String

    var body: some View {
        ContentUnavailableView {
                Label(title, systemImage: symbol)
            } description: {
                Text(text)
            }
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
    }
}
