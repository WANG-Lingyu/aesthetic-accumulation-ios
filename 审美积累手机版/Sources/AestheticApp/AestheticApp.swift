import SwiftUI

@main
struct AestheticApp: App {
    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(LibraryStore.shared)
                .environmentObject(WardrobeStore.shared)
                .environmentObject(OutfitStore.shared)
                .environmentObject(CalendarStore.shared)
                .environmentObject(WeatherStore.shared)
        }
    }
}
