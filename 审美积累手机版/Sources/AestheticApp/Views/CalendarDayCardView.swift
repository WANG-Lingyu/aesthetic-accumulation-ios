import SwiftUI

/// 当日卡片：日期标题 + 照片 3 列网格 + 整体备注
struct DayCardView: View {
    @EnvironmentObject var calendar: CalendarStore
    @EnvironmentObject var weather: WeatherStore
    let entry: CalendarEntry?
    let date: Date
    var onAddPhotos: () -> Void
    var onOpenPhoto: (Int) -> Void

    /// 本地缓存整体备注，避免 TextEditor 每敲一个字就触发整页重绘（写回时再同步 Store）
    @State private var noteText: String = ""

    private static let titleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 EEEE"
        return f
    }()

    private let columns = [
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6),
        GridItem(.flexible(), spacing: 6)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.titleFormatter.string(from: date))
                    .font(.title3.weight(.semibold))
                    .foregroundColor(AppTheme.primaryText)
                // 显示所选日期当天的天气（含历史 / 预报）：地点 + 天气现象 + 最低~最高温度
                if weather.placeName != nil || weather.weather(for: date) != nil {
                    HStack(spacing: 6) {
                        if let place = weather.placeName {
                            Image(systemName: "location.fill")
                            Text(place)
                        }
                        if let w = weather.weather(for: date) {
                            Image(systemName: w.symbolName)
                                .foregroundColor(AppTheme.primaryText)
                            Text(w.conditionText)
                            Text("\(Int(w.minTemp.rounded()))°~\(Int(w.maxTemp.rounded()))°")
                        }
                    }
                    .font(.subheadline)
                    .foregroundColor(AppTheme.secondaryText)
                }
            }

            if let entry, !entry.photos.isEmpty {
                photoGrid(entry)
            } else {
                emptyHint
            }

            addButton
            noteSection
        }
        .padding(.horizontal, 16)
        .onAppear {
            noteText = entry?.note ?? ""
            weather.loadWeather(for: date)
        }
        .onChange(of: date) { _, _ in
            noteText = entry?.note ?? ""
            weather.loadWeather(for: date)
        }
    }

    private var emptyHint: some View {
        Text("这一天还没有记录")
            .font(.subheadline)
            .foregroundColor(AppTheme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
    }

    private func photoGrid(_ entry: CalendarEntry) -> some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(entry.photos.enumerated()), id: \.element.id) { index, photo in
                photoCell(photo, index: index)
            }
        }
    }

    private func photoCell(_ photo: CalendarPhoto, index: Int) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image = calendar.uiImage(for: photo) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle().fill(AppTheme.divider)
                }
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .onTapGesture { onOpenPhoto(index) }
            .contextMenu {
                Button(role: .destructive) {
                    if let entry {
                        calendar.removePhoto(id: photo.id, from: entry.id)
                    }
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
    }

    private var addButton: some View {
        Button(action: onAddPhotos) {
            Label("添加照片", systemImage: "photo.badge.plus")
                .font(.subheadline.weight(.medium))
                .foregroundColor(AppTheme.primaryText)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(AppTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [4]))
                        .foregroundColor(AppTheme.divider)
                )
        }
        .buttonStyle(.plain)
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("整体备注")
                .font(.headline)
                .foregroundColor(AppTheme.primaryText)
            TextEditor(text: $noteText)
                .frame(minHeight: 100)
                .padding(8)
                .background(AppTheme.cardBackground)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(AppTheme.divider, lineWidth: 1)
                )
        }
        .onChange(of: noteText) { _, newValue in
            // 只在真正变化时写回，避免切日期时无谓地新建/清理记录
            if newValue != (entry?.note ?? "") {
                calendar.setEntryNote(newValue, for: date)
            }
        }
    }
}
