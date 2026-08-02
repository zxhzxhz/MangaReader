import SwiftUI
import UIKit

struct BookCoverView: View {
    let item: LibraryItem
    let coverService: CoverService

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.secondarySystemBackground))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "book.closed")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 52, height: 72)
        .task(id: item.id) {
            if let data = await coverService.coverData(for: item) {
                image = UIImage(data: data)
            }
        }
    }
}
