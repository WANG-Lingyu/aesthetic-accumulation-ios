import SwiftUI

/// 占位页（M0 阶段的临时页面）
struct PlaceholderView: View {
    let title: String
    let systemImage: String
    let note: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 44))
            Text(title)
                .font(.title2).fontWeight(.semibold)
            Text(note)
                .font(.callout)
                .foregroundColor(AppTheme.secondaryText)
        }
        .foregroundColor(AppTheme.primaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.background)
    }
}
