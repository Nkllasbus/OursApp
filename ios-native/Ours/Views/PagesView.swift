import SwiftUI

struct PagesView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                PageGrid()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Seiten")
        }
    }
}
