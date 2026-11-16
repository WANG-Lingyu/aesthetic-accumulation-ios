import SwiftUI

/// 全屏照片查看器：左右滑动切换当天照片，每张下方可写备注
struct CalendarPhotoViewer: View {
    @EnvironmentObject var calendar: CalendarStore
    @Environment(\.dismiss) private var dismiss
    let entryID: String
    @State var currentIndex: Int

    init(entryID: String, startIndex: Int) {
        self.entryID = entryID
        _currentIndex = State(initialValue: startIndex)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if let entry = calendar.entry(id: entryID), !entry.photos.isEmpty {
                TabView(selection: $currentIndex) {
                    ForEach(Array(entry.photos.enumerated()), id: \.element.id) { index, photo in
                        CalendarPhotoPage(entryID: entryID, photo: photo)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .background(Color.black.ignoresSafeArea())
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
            Spacer()
            if let entry = calendar.entry(id: entryID), !entry.photos.isEmpty {
                Text("第 \(currentIndex + 1) / \(entry.photos.count) 张")
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
            Spacer()
            Color.clear.frame(width: 24, height: 24) // 平衡左侧关闭键，让标题居中
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// 查看器里的一页：照片大图 + 下方备注
struct CalendarPhotoPage: View {
    @EnvironmentObject var calendar: CalendarStore
    let entryID: String
    let photo: CalendarPhoto

    /// 本地缓存备注，避免 TextField 每敲一个字就重绘（写回时再同步 Store）
    @State private var noteText: String = ""

    var body: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            if let image = calendar.uiImage(for: photo) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Rectangle().fill(Color.gray.opacity(0.3))
            }
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                Text("照片备注")
                    .font(.caption)
                    .foregroundColor(Color.white.opacity(0.7))
                TextField("写点备注…", text: $noteText, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.subheadline)
                    .padding(10)
                    .background(Color.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .onAppear { noteText = photo.note }
        .onChange(of: noteText) { _, newValue in
            if newValue != photo.note {
                calendar.setPhotoNote(newValue, photoID: photo.id, in: entryID)
            }
        }
    }
}
