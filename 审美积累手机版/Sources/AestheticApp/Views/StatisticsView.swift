import SwiftUI
import Charts

/// 衣橱数据统计：衣物总数 + 分类占比饼状图
struct StatisticsView: View {
    @EnvironmentObject var wardrobe: WardrobeStore

    /// 分类统计（按数量降序）
    private var categoryStats: [CategoryStat] {
        var counts: [String: Int] = [:]
        for item in wardrobe.items {
            counts[item.category, default: 0] += 1
        }
        return counts.map { CategoryStat(name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    private var total: Int { wardrobe.items.count }

    var body: some View {
        List {
            Section("概览") {
                LabeledContent("衣物总数", value: "\(total) 件")
                LabeledContent("分类数量", value: "\(categoryStats.count) 类")
            }

            if categoryStats.isEmpty {
                Section("分类占比") {
                    Text("衣橱还是空的，先去「穿搭」添加单品吧")
                        .font(.callout)
                        .foregroundColor(AppTheme.secondaryText)
                }
            } else {
                Section("分类占比") {
                    Chart(categoryStats) { item in
                        SectorMark(
                            angle: .value("数量", item.count),
                            innerRadius: .ratio(0.55),
                            angularInset: 1.5
                        )
                        .cornerRadius(2)
                        .foregroundStyle(by: .value("分类", item.name))
                    }
                    .frame(height: 220)

                    ForEach(categoryStats) { item in
                        HStack {
                            Text(item.name)
                            Spacer()
                            Text("\(item.count) 件 · \(percent(item.count))")
                                .foregroundColor(AppTheme.secondaryText)
                        }
                    }
                }
            }
        }
        .navigationTitle("数据统计")
        .navigationBarTitleDisplayMode(.inline)
        .background(AppTheme.background)
    }

    private func percent(_ count: Int) -> String {
        guard total > 0 else { return "0%" }
        return "\(Int((Double(count) / Double(total) * 100).rounded()))%"
    }
}

/// 单个分类的数量统计
private struct CategoryStat: Identifiable {
    let name: String
    let count: Int
    var id: String { name }
}
