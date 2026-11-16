import SwiftUI

/// 素材缩略图卡片（统一正方形，裁切填充）
struct PhotoCard: View {
    let photo: Photo
    @EnvironmentObject var store: LibraryStore

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image = store.uiImage(for: photo) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle().fill(AppTheme.divider)
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
