import SwiftUI

struct ImageThumbnailStrip: View {
    let images: [UIImage]
    var highlightedIndices: Set<Int>? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                    thumbnail(image: image, index: index)
                }
            }
            .padding(.horizontal)
        }
    }

    private func thumbnail(image: UIImage, index: Int) -> some View {
        let isHighlighted = highlightedIndices == nil || highlightedIndices!.contains(index)

        return Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isHighlighted ? Theme.champagne : Theme.border.opacity(0.3),
                        lineWidth: isHighlighted ? 2 : 1
                    )
            )
            .overlay(alignment: .topTrailing) {
                Text("\(index + 1)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Theme.champagne)
                    .clipShape(Circle())
                    .offset(x: 4, y: -4)
            }
            .opacity(isHighlighted ? 1 : 0.4)
    }
}
