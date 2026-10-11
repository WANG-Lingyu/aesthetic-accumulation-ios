import SwiftUI

/// 我的页：数据统计 + AI 审美报告 + 设置/客服
struct ProfileView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        StatisticsView()
                    } label: {
                        Label("数据统计", systemImage: "chart.bar")
                    }
                    NavigationLink {
                        AestheticDataView()
                    } label: {
                        Label("AI 审美报告", systemImage: "chart.pie")
                    }
                    Label("设置", systemImage: "gearshape")
                    Label("客服", systemImage: "person.text.rectangle")
                }
            }
            .navigationTitle("我的")
        }
    }
}
