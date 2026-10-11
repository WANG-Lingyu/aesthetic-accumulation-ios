import SwiftUI
import PhotosUI

/// 日历页：上方月历（翻月 / 选日）+ 下方当日卡片，两部分各自滚动互不影响
struct CalendarView: View {
    @EnvironmentObject var calendar: CalendarStore
    @EnvironmentObject var weather: WeatherStore
    /// 月历当前展示的月份
    @State private var displayedMonth: Date = Calendar.current.startOfDay(for: Date())
    @State private var sheet: CalendarSheet?
    /// 「添加照片」菜单与相机 / 相册选择
    @State private var showAddMenu = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var cameraUnavailable = false

    var body: some View {
        VStack(spacing: 0) {
            MonthCalendarView(selectedDate: $calendar.selectedDate, displayedMonth: $displayedMonth)
            Divider()
            ScrollView {
                DayCardView(
                    entry: calendar.entry(for: calendar.selectedDate),
                    date: calendar.selectedDate,
                    onAddPhotos: { showAddMenu = true },
                    onOpenPhoto: { index in
                        if let entry = calendar.entry(for: calendar.selectedDate) {
                            sheet = .viewer(entryID: entry.id, startIndex: index)
                        }
                    }
                )
                .padding(.top, 16)
                // 底部留出 TabBar 高度，避免整体备注框被底栏遮住、滑不到头
                .padding(.bottom, 72)
            }
        }
        .background(AppTheme.background)
        .onAppear {
            displayedMonth = startOfMonth(calendar.selectedDate)
            weather.load()
        }
        .onChange(of: calendar.selectedDate) { _, newDate in
            // 加号导入跳转时，让月历跟着切到对应月份
            displayedMonth = startOfMonth(newDate)
        }
        .confirmationDialog("添加照片", isPresented: $showAddMenu, titleVisibility: .visible) {
            Button("拍照") {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    showCamera = true
                } else {
                    cameraUnavailable = true
                }
            }
            Button("从相册选择") { showPhotoPicker = true }
            Button("从素材添加") { sheet = .libraryPicker }
            Button("取消", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showCamera) {
            ImagePicker(sourceType: .camera) { image in
                calendar.addPhotos([image], to: calendar.selectedDate)
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoPickerItems,
                      maxSelectionCount: 0, matching: .images)
        .onChange(of: photoPickerItems) { _, items in
            guard !items.isEmpty else { return }
            loadPickedItems(items)
        }
        .fullScreenCover(item: $sheet) { item in
            switch item {
            case .libraryPicker:
                LibraryPhotoPickerSheet { photoIDs in
                    calendar.addPhotos(fromLibrary: photoIDs, to: calendar.selectedDate)
                }
            case .viewer(let entryID, let startIndex):
                CalendarPhotoViewer(entryID: entryID, startIndex: startIndex)
            }
        }
        .alert("当前设备不支持相机", isPresented: $cameraUnavailable) {
            Button("好", role: .cancel) {}
        } message: {
            Text("请改用「从相册选择」")
        }
    }

    /// 相册多选后，把图片直接加进当前选中的那一天
    private func loadPickedItems(_ items: [PhotosPickerItem]) {
        Task { @MainActor in
            var images: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    images.append(image)
                }
            }
            photoPickerItems = []
            if !images.isEmpty {
                calendar.addPhotos(images, to: calendar.selectedDate)
            }
        }
    }

    private func startOfMonth(_ date: Date) -> Date {
        let comps = Calendar.current.dateComponents([.year, .month], from: date)
        return Calendar.current.date(from: comps) ?? date
    }
}

/// 月历：翻月 + 点选日期，支持横向滑动翻月（与下方卡片纵向滚动不冲突）
struct MonthCalendarView: View {
    @EnvironmentObject var calendar: CalendarStore
    @Binding var selectedDate: Date
    @Binding var displayedMonth: Date

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy年M月"
        return f
    }()

    private let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]

    var body: some View {
        VStack(spacing: 8) {
            header
            weekdayRow
            dayGrid
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(AppTheme.cardBackground)
        .simultaneousGesture(monthSwipe)
    }

    private var header: some View {
        HStack {
            Button { changeMonth(-1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
            }
            Spacer()
            VStack(spacing: 2) {
                Text(Self.monthFormatter.string(from: displayedMonth))
                    .font(.headline)
                    .foregroundColor(AppTheme.primaryText)
                Button("回到今天") { goToday() }
                    .font(.caption)
                    .foregroundColor(AppTheme.secondaryText)
            }
            Spacer()
            Button { changeMonth(1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
            }
        }
        .foregroundColor(AppTheme.primaryText)
    }

    private var weekdayRow: some View {
        HStack {
            ForEach(weekdaySymbols, id: \.self) { s in
                Text(s)
                    .font(.caption2)
                    .foregroundColor(AppTheme.secondaryText)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var dayGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(Array(monthCells.enumerated()), id: \.offset) { _, date in
                if let date {
                    dayCell(date)
                } else {
                    Color.clear.frame(height: 34)
                }
            }
        }
    }

    /// 当月格子：前面补空白（周日开头），末尾补足整行
    private var monthCells: [Date?] {
        let cal = Calendar.current
        let start = startOfMonth(displayedMonth)
        let firstWeekday = cal.component(.weekday, from: start) // 1 = 周日
        let daysInMonth = cal.range(of: .day, in: .month, for: start)?.count ?? 30
        var cells: [Date?] = Array(repeating: nil, count: firstWeekday - 1)
        for day in 1...daysInMonth {
            cells.append(cal.date(byAdding: .day, value: day - 1, to: start))
        }
        while cells.count % 7 != 0 {
            cells.append(nil)
        }
        return cells
    }

    private func dayCell(_ date: Date) -> some View {
        let cal = Calendar.current
        let day = cal.component(.day, from: date)
        let isToday = cal.isDateInToday(date)
        let isSelected = cal.isDate(date, inSameDayAs: selectedDate)
        let hasDot = calendar.hasEntry(on: date)

        return Button {
            selectedDate = date
        } label: {
            VStack(spacing: 2) {
                Text("\(day)")
                    .font(.system(size: 14, weight: (isSelected || isToday) ? .semibold : .regular))
                    .frame(width: 28, height: 28)
                    .foregroundColor(isSelected ? .white : AppTheme.primaryText)
                    .background(Circle().fill(isSelected ? AppTheme.primaryText : Color.clear))
                    .overlay(
                        Circle().stroke(isToday && !isSelected ? AppTheme.primaryText : Color.clear, lineWidth: 1)
                    )
                Circle()
                    .fill(hasDot ? AppTheme.primaryText : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var monthSwipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                if value.translation.width < -40 {
                    changeMonth(1)
                } else if value.translation.width > 40 {
                    changeMonth(-1)
                }
            }
    }

    private func startOfMonth(_ date: Date) -> Date {
        let comps = Calendar.current.dateComponents([.year, .month], from: date)
        return Calendar.current.date(from: comps) ?? date
    }

    private func changeMonth(_ delta: Int) {
        if let newMonth = Calendar.current.date(byAdding: .month, value: delta, to: displayedMonth) {
            displayedMonth = newMonth
        }
    }

    private func goToday() {
        selectedDate = Calendar.current.startOfDay(for: Date())
        displayedMonth = startOfMonth(selectedDate)
    }
}
