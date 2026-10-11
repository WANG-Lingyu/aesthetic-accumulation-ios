import SwiftUI
import UIKit
import PhotosUI

enum AppTab: String, CaseIterable {
    case material = "素材"
    case outfit = "穿搭"
    case calendar = "日历"
    case profile = "我的"
}

enum RootAlert: Identifiable {
    case cameraUnavailable
    case duplicates(Int)
    case cutoutFailed

    var id: String {
        switch self {
        case .cameraUnavailable: return "camera"
        case .duplicates: return "duplicates"
        case .cutoutFailed: return "cutout"
        }
    }
}

/// 统一用一个 sheet 承载整个添加流程，避免多个 sheet 相互冲突导致“点了没反应”
enum RootSheet: Identifiable {
    case destination
    case manualCutout(UIImage)
    case category([UIImage])
    case calendarDate([UIImage])
    case itemInfo(images: [UIImage], category: String)

    var id: String {
        switch self {
        case .destination: return "destination"
        case .manualCutout: return "manual"
        case .category: return "category"
        case .calendarDate: return "calendarDate"
        case .itemInfo: return "itemInfo"
        }
    }
}

/// 底部菜单栏（4 tab）+ 中间「＋」统一添加
struct RootTabView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var wardrobe: WardrobeStore
    @EnvironmentObject var calendar: CalendarStore
    @State private var selectedTab: AppTab = .material
    @State private var showPlusMenu = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var pickedItems: [PhotosPickerItem] = []
    @State private var pickedImages: [UIImage] = []
    @State private var addToMaterial = false
    @State private var addToOutfit = false
    @State private var addToCalendar = false
    @State private var readyCutouts: [UIImage] = []
    @State private var pendingManual: [UIImage] = []
    @State private var rootSheet: RootSheet?
    @State private var duplicates: [(new: Photo, existing: Photo)] = []
    @State private var activeAlert: RootAlert?
    @State private var isCutting = false

    var body: some View {
        ZStack(alignment: .bottom) {
            AppTheme.background.ignoresSafeArea()
            content
            tabBar
            if isCutting {
                loadingOverlay
            }
        }
        .confirmationDialog("添加", isPresented: $showPlusMenu, titleVisibility: .visible) {
            Button("拍照") {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    showCamera = true
                } else {
                    activeAlert = .cameraUnavailable
                }
            }
            Button("从相册选择") { showPhotoPicker = true }
            Button("取消", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showCamera) {
            ImagePicker(sourceType: .camera) { image in
                pickedImages = [image]
                addToMaterial = false
                addToOutfit = false
                addToCalendar = false
                rootSheet = .destination
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $pickedItems,
                      maxSelectionCount: 0, matching: .images)
        .onChange(of: pickedItems) { _, items in
            guard !items.isEmpty else { return }
            loadPickedItems(items)
        }
        .fullScreenCover(item: $rootSheet) { sheet in
            switch sheet {
            case .destination:
                DestinationSheet(addToMaterial: $addToMaterial, addToOutfit: $addToOutfit, addToCalendar: $addToCalendar) {
                    processDestination()
                }
            case .manualCutout(let img):
                ManualCutoutView(image: img,
                                 onDone: { cutout in
                                     readyCutouts.append(cutout)
                                     continueOutfitFlow()
                                 },
                                 onUseOriginal: {
                                     readyCutouts.append(img)
                                     continueOutfitFlow()
                                 })
            case .category(let images):
                CategoryPickerSheet(images: images) { category in
                    // 分类选完，先弹「品牌/尺码/价格」补充信息，再入衣橱
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        rootSheet = .itemInfo(images: images, category: category)
                    }
                }
            case .itemInfo(let images, let category):
                ItemInfoSheet { brand, size, price in
                    for img in images {
                        wardrobe.addItem(category: category, image: img,
                                         brand: brand, size: size, price: price)
                    }
                    readyCutouts = []
                }
            case .calendarDate(let images):
                CalendarDatePickerSheet { date in
                    calendar.addPhotos(images, to: date)
                    calendar.selectedDate = Calendar.current.startOfDay(for: date)
                    selectedTab = .calendar
                }
            }
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .cameraUnavailable:
                return Alert(title: Text("当前设备不支持相机"),
                             message: Text("请改用「从相册选择」"),
                             dismissButton: .default(Text("好")))
            case .duplicates(let count):
                return Alert(
                    title: Text("发现重复照片"),
                    message: Text("新导入的照片中有 \(count) 张与库中已有照片几乎相同"),
                    primaryButton: .destructive(Text("删除新导入的重复照片")) {
                        store.deletePhotos(Set(duplicates.map { $0.new.id }))
                        duplicates = []
                    },
                    secondaryButton: .cancel(Text("保留")) { duplicates = [] }
                )
            case .cutoutFailed:
                return Alert(title: Text("抠图失败"),
                             message: Text("没能识别出主体，请换背景干净、主体清晰的照片"),
                             dismissButton: .default(Text("好")))
            }
        }
    }

    private func loadPickedItems(_ items: [PhotosPickerItem]) {
        Task { @MainActor in
            var images: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    images.append(image)
                }
            }
            pickedItems = []
            pickedImages = images
            addToMaterial = false
            addToOutfit = false
            addToCalendar = false
            rootSheet = .destination
        }
    }

    private func processDestination() {
        let images = pickedImages
        pickedImages = []

        if addToMaterial {
            var newIDs: [String] = []
            for image in images {
                if let data = image.jpegData(compressionQuality: 0.9),
                   let photo = store.importImage(data, ext: "jpg") {
                    newIDs.append(photo.id)
                    store.generateTags(for: photo.id)
                }
            }
            checkDuplicates(for: newIDs)
        }

        if addToOutfit {
            // 后台异步抠图：不阻塞主线程，期间显示 Loading
            isCutting = true
            Task { @MainActor in
                let (successes, failures) = await cutOutBackgrounds(images)
                isCutting = false
                readyCutouts = successes
                pendingManual = failures
                selectedTab = .outfit   // 抠图完成后跳转穿搭页
                continueOutfitFlow()
            }
        } else if addToMaterial {
            selectedTab = .material
        }

        if addToCalendar {
            // 弹日期选择，确定后再入日历并跳转
            rootSheet = .calendarDate(images)
        }
    }

    /// 后台抠图：成功进衣橱，失败自动降级进手动抠像
    private func cutOutBackgrounds(_ images: [UIImage]) async -> (successes: [UIImage], failures: [UIImage]) {
        var successes: [UIImage] = []
        var failures: [UIImage] = []
        for image in images {
            if let cutout = await BackgroundRemover.removeBackground(from: image) {
                successes.append(cutout)
            } else {
                failures.append(image)
            }
        }
        return (successes, failures)
    }

    private func continueOutfitFlow() {
        // 等上一个 sheet 完全关闭后再弹下一个，避免“点了确定没反应”
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if pendingManual.isEmpty {
                rootSheet = .category(readyCutouts)
            } else {
                rootSheet = .manualCutout(pendingManual.removeFirst())
            }
        }
    }

    private func checkDuplicates(for photoIDs: [String]) {
        let dups = store.findDuplicates(for: photoIDs)
        if !dups.isEmpty {
            duplicates = dups
            activeAlert = .duplicates(dups.count)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .material: MaterialView()
        case .outfit: OutfitView()
        case .calendar: CalendarView()
        case .profile: ProfileView()
        }
    }

    /// 抠图进行中的 Loading 遮罩
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                Text("正在 AI 抠图…")
                    .font(.callout)
                    .foregroundColor(.white)
            }
        }
    }

    private var tabBar: some View {
        HStack {
            tabButton(.material, "photo.on.rectangle")
            tabButton(.outfit, "tshirt")
            Spacer().frame(width: 64)
            tabButton(.calendar, "calendar")
            tabButton(.profile, "person")
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(AppTheme.cardBackground)
        .overlay(alignment: .top) { Rectangle().fill(AppTheme.divider).frame(height: 1) }
        .overlay { centerPlusButton }
    }

    private func tabButton(_ tab: AppTab, _ systemImage: String) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 20))
                Text(tab.rawValue)
                    .font(.caption2)
            }
            .foregroundColor(selectedTab == tab ? AppTheme.primaryText : AppTheme.secondaryText)
            .frame(maxWidth: .infinity)
        }
    }

    private var centerPlusButton: some View {
        Button {
            showPlusMenu = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 52, height: 52)
                .background(AppTheme.primaryText)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .offset(y: -20)
    }
}

/// 选择添加到素材 / 搭配 / 日历
struct DestinationSheet: View {
    @Binding var addToMaterial: Bool
    @Binding var addToOutfit: Bool
    @Binding var addToCalendar: Bool
    var onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("添加到哪里（可多选）")
                    .font(.headline)
                    .foregroundColor(AppTheme.primaryText)
                checkboxRow("加入素材", isOn: $addToMaterial)
                checkboxRow("加入搭配（衣橱）", isOn: $addToOutfit)
                checkboxRow("加入日历", isOn: $addToCalendar)
                HStack(spacing: 16) {
                    Button("取消") { dismiss() }
                        .foregroundColor(AppTheme.secondaryText)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                    Button("确定") {
                        dismiss()
                        onConfirm()
                    }
                    .disabled(!addToMaterial && !addToOutfit && !addToCalendar)
                    .foregroundColor(.white)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 24)
                    .background(AppTheme.primaryText.opacity((!addToMaterial && !addToOutfit && !addToCalendar) ? 0.35 : 1))
                    .cornerRadius(8)
                }
                .padding(.top, 4)
            }
            .padding(20)
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
            .padding(.horizontal, 48)
        }
    }

    private func checkboxRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundColor(isOn.wrappedValue ? AppTheme.primaryText : AppTheme.secondaryText)
                Text(title)
                    .foregroundColor(AppTheme.primaryText)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
