import SwiftUI

/// 审美数据中心 + 年度报告（本地统计）
struct AestheticDataView: View {
    @EnvironmentObject var store: LibraryStore

    private var colorStats: [(name: String, hex: String, count: Int)] {
        var counts: [String: (hex: String, count: Int)] = [:]
        for photo in store.library.photos {
            for c in photo.colors {
                let name = ColorExtractor.colorName(hex: c.hex)
                var entry = counts[name] ?? (hex: c.hex, count: 0)
                entry.count += 1
                counts[name] = entry
            }
        }
        return counts.map { (name: $0.key, hex: $0.value.hex, count: $0.value.count) }
            .sorted { $0.count > $1.count }
    }

    private var tagStats: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        for photo in store.library.photos {
            for tag in photo.tags {
                counts[tag, default: 0] += 1
            }
        }
        return counts.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }

    private var regionCount: Int {
        store.library.photos.reduce(0) { $0 + $1.regions.count }
    }

    var body: some View {
        List {
            Section("概览") {
                LabeledContent("素材总数", value: "\(store.library.photos.count)")
                LabeledContent("册子数量", value: "\(store.library.albums.count)")
                LabeledContent("圈选笔记", value: "\(regionCount)")
                LabeledContent("标签总数", value: "\(store.library.photos.reduce(0) { $0 + $1.tags.count })")
            }

            if !colorStats.isEmpty {
                Section("偏好色系") {
                    ForEach(colorStats.prefix(6), id: \.name) { s in
                        HStack {
                            Circle().fill(Color(hexString: s.hex)).frame(width: 14, height: 14)
                            Text(s.name)
                            Spacer()
                            Text("\(s.count)")
                                .foregroundColor(AppTheme.secondaryText)
                        }
                    }
                }
            }

            if !tagStats.isEmpty {
                Section("高频标签") {
                    ForEach(tagStats.prefix(8), id: \.tag) { s in
                        HStack {
                            Text(s.tag)
                            Spacer()
                            Text("\(s.count)")
                                .foregroundColor(AppTheme.secondaryText)
                        }
                    }
                }
            }

            Section("年度审美报告") {
                Text(reportText)
                    .font(.callout)
                    .foregroundColor(AppTheme.primaryText)
                    .padding(.vertical, 4)
            }
        }
        .navigationTitle("审美数据")
        .navigationBarTitleDisplayMode(.inline)
        .background(AppTheme.background)
    }

    private var reportText: String {
        let total = store.library.photos.count
        if total == 0 {
            return "你还没有收藏素材，先导入一些喜欢的图，我会自动帮你总结审美偏好。"
        }
        let topColor = colorStats.first?.name ?? "无"
        let topTag = tagStats.first?.tag ?? "无"
        return "这一阶段你收藏了 \(total) 张灵感图，写下 \(regionCount) 条圈选笔记。你的偏好色系是「\(topColor)」，最常用的标签是「\(topTag)」。继续积累，让属于你的审美体系越来越清晰。"
    }
}
