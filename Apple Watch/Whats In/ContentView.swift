import SwiftUI
import Combine
import UIKit
import UserNotifications
import WidgetKit

// --- 1. DATA MODELS ---
struct MenuResponse: Codable {
    let meta: Meta
    let menu: [String: [String: String]]
}

struct Meta: Codable {
    let weekStart: String
}

// --- 2. HELPERS ---
class HapticManager {
    static let shared = HapticManager()
    
    func click() {
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        generator.impactOccurred(intensity: 1.0)
    }
    
    func release() {
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.prepare()
        generator.impactOccurred(intensity: 0.6)
    }
    
    func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        return path
    }
}

// --- 3. NOTIFICATION MANAGER ---
class NotificationManager {
    static let shared = NotificationManager()
    
    let schedules = [
        "Breakfast": (hour: 8, minute: 0),
        "Lunch":     (hour: 13, minute: 0),
        "Snacks":    (hour: 17, minute: 0),
        "Dinner":    (hour: 20, minute: 0)
    ]
    
    let dayMapping: [String: Int] = [
        "Sunday": 1, "Monday": 2, "Tuesday": 3, "Wednesday": 4,
        "Thursday": 5, "Friday": 6, "Saturday": 7
    ]
    
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted { print("Notification permission granted") }
        }
    }
    
    func scheduleNotifications(menu: [String: [String: String]]) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        
        for (dayName, meals) in menu {
            guard let weekday = dayMapping[dayName] else { continue }
            
            for (mealType, food) in meals {
                guard let time = schedules[mealType] else { continue }
                
                let content = UNMutableNotificationContent()
                content.title = "\(mealType.uppercased()) TIME"
                content.body = food
                content.sound = .default
                
                var dateComponents = DateComponents()
                dateComponents.weekday = weekday
                dateComponents.hour = time.hour
                dateComponents.minute = time.minute
                
                let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
                let request = UNNotificationRequest(identifier: "\(dayName)_\(mealType)", content: content, trigger: trigger)
                center.add(request)
            }
        }
    }
}

// --- 4. VIEWMODEL ---
@MainActor
class IOSViewModel: ObservableObject {
    @Published var currentMealType: String = "LOADING..."
    @Published var currentFood: String = "..."
    @Published var currentDay: String = ""
    @Published var currentDateString: String = ""
    @Published var nextMealType: String = ""
    @Published var nextFood: String = ""
    @Published var isLoading: Bool = true
    @Published var showRefreshSuccess: Bool = false
    @Published var fullMenu: [String: [String: String]] = [:]
    
    // ⚠️ IMPORTANT: Ensure this matches your App Group ID exactly
    let appGroupSuite = "group.com.onesilicondiode.menutracker"
    
    let appBg = Color(red: 1.0, green: 0.99, blue: 0.94)       // Cream
    let appAccent = Color(red: 1.0, green: 0.42, blue: 0.42)   // Red
    let appSecondary = Color(red: 1.0, green: 0.9, blue: 0.42) // Yellow
    let appPrimary = Color(red: 0.3, green: 0.8, blue: 0.77)   // Teal
    
    let menuURL = "https://gist.githubusercontent.com/the-rebooted-coder/b2d795d38fff48d9aa4e15e65d818262/raw/menu.json"
    let timeLimits = (breakfast: 11, lunch: 15, snacks: 18, dinner: 22)
    
    let weekOrder = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    let mealOrder = ["Breakfast", "Lunch", "Snacks", "Dinner"]
    
    func refresh(force: Bool = false) async {
        if !force && !fullMenu.isEmpty {
            isLoading = false
            return
        }
        defer { DispatchQueue.main.async { self.isLoading = false } }
        let urlString = force ? "\(menuURL)?t=\(Date().timeIntervalSince1970)" : menuURL
        guard let url = URL(string: urlString) else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(MenuResponse.self, from: data)
            
            self.fullMenu = decoded.menu
            self.calculateCurrentMeal(data: decoded)
            
            // --- SAVE DATA FOR WIDGET ---
            saveDataForWidget(data: data)
            
            NotificationManager.shared.scheduleNotifications(menu: decoded.menu)
            
            if force {
                DispatchQueue.main.async {
                    HapticManager.shared.success()
                    withAnimation { self.showRefreshSuccess = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { self.showRefreshSuccess = false }
                    }
                }
            }
        } catch {
            self.currentFood = "Connection Error"
            self.currentMealType = "OFFLINE"
        }
    }
    
    private func saveDataForWidget(data: Data) {
        if let sharedDefaults = UserDefaults(suiteName: appGroupSuite) {
            sharedDefaults.set(data, forKey: "cachedMenuData")
            // Tell widget to reload immediately
            WidgetCenter.shared.reloadAllTimelines()
            print("Data saved to App Group: \(appGroupSuite)")
        } else {
            print("Failed to access App Group. Check your entitlements.")
        }
    }
    
    func calculateCurrentMeal(data: MenuResponse) {
        let now = Date()
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: "en_US")
        let hour = calendar.component(.hour, from: now)
        let todayName = calendar.weekdaySymbols[calendar.component(.weekday, from: now) - 1]
        
        var targetMeal = ""
        var targetDay = todayName
        
        // Determine Current Meal & Day
        if hour < timeLimits.breakfast { targetMeal = "Breakfast" }
        else if hour < timeLimits.lunch { targetMeal = "Lunch" }
        else if hour < timeLimits.snacks { targetMeal = "Snacks" }
        else if hour < timeLimits.dinner { targetMeal = "Dinner" }
        else {
            // Late night -> Show Tomorrow's Breakfast
            targetMeal = "Breakfast"
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) {
                targetDay = calendar.weekdaySymbols[calendar.component(.weekday, from: tomorrow) - 1]
            }
        }
        
        self.currentMealType = targetMeal.uppercased()
        self.currentDay = targetDay
        
        // Calculate Date String (e.g., Dec 01)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        if let weekStartDate = dateFormatter.date(from: data.meta.weekStart) {
            if let targetIndex = weekOrder.firstIndex(of: targetDay) {
                if let specificDate = calendar.date(byAdding: .day, value: targetIndex, to: weekStartDate) {
                    let displayFormatter = DateFormatter()
                    displayFormatter.dateFormat = "MMM dd"
                    self.currentDateString = displayFormatter.string(from: specificDate)
                }
            }
        }
        
        // Get Current Food
        if let dayMenu = data.menu[targetDay], let food = dayMenu[targetMeal] {
            self.currentFood = food
        } else {
            self.currentFood = "Not listed"
        }
        
        // --- NEXT MEAL LOGIC (FIXED) ---
        if let idx = ["Breakfast", "Lunch", "Snacks", "Dinner"].firstIndex(of: targetMeal) {
            let allMeals = ["Breakfast", "Lunch", "Snacks", "Dinner"]
            var nextM = ""
            var nextD = targetDay
            
            if idx < 3 {
                // If Breakfast/Lunch/Snacks, Next Meal is the NEXT one on the SAME day
                nextM = allMeals[idx + 1]
            } else {
                // If Dinner, Next Meal is BREAKFAST on the NEXT day
                nextM = "Breakfast"
                if let currentDayIdx = weekOrder.firstIndex(of: targetDay) {
                    let nextDayIdx = (currentDayIdx + 1) % weekOrder.count
                    nextD = weekOrder[nextDayIdx]
                }
            }
            
            self.nextMealType = nextM.uppercased()
            
            if let dayMenu = data.menu[nextD], let nextF = dayMenu[nextM] {
                self.nextFood = nextF
            } else {
                self.nextFood = "-"
            }
        }
    }
}

// --- 5. UI COMPONENTS (NEO BRUTALISM) ---

struct NeoContainer<Content: View>: View {
    let color: Color
    let content: Content
    
    init(color: Color = .white, @ViewBuilder content: () -> Content) {
        self.color = color
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            Rectangle().fill(Color.black).offset(x: 6, y: 6)
            Rectangle().fill(color).overlay(Rectangle().stroke(Color.black, lineWidth: 3))
            content.padding(20)
        }
        .padding(.trailing, 6).padding(.bottom, 6)
    }
}

struct NeoMealRow: View {
    let label: String
    let food: String
    let isLast: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased())
                .font(.system(size: 13, weight: .black))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black)
                .foregroundColor(.white)
                .padding(.bottom, 8)
            
            Text(food)
                .font(.custom("CourierNewPS-BoldMT", size: 18))
                .foregroundColor(.black)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if !isLast {
                VStack(spacing: 0) {
                    Spacer().frame(height: 15)
                    DashedLine().stroke(style: StrokeStyle(lineWidth: 2, dash: [6])).frame(height: 1).foregroundColor(.black)
                    Spacer().frame(height: 15)
                }
            }
        }
    }
}

struct NeoPressStyle: ButtonStyle {
    var color: Color = .white
    
    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            Rectangle().fill(Color.black).offset(x: 4, y: 4)
            configuration.label
                .background(color)
                .overlay(Rectangle().stroke(Color.black, lineWidth: 3))
                .offset(x: configuration.isPressed ? 4 : 0, y: configuration.isPressed ? 4 : 0)
        }
        .frame(height: 60)
        .padding(.trailing, 4).padding(.bottom, 4)
        .animation(.easeInOut(duration: 0.05), value: configuration.isPressed)
        .onChange(of: configuration.isPressed) { isPressed in
            if isPressed { HapticManager.shared.click() }
            else { HapticManager.shared.release() }
        }
    }
}

// --- UPDATED: LIQUID GLASS NAV BAR (FIXED) ---

enum Tab: String, CaseIterable {
    case home = "Home"
    case today = "Today"
    case week = "Week"
    
    var icon: String {
        switch self {
        case .home: return "house"
        case .today: return "list.bullet.rectangle.portrait"
        case .week: return "calendar"
        }
    }
}

struct LiquidFloatingNavBar: View {
    @Binding var selectedTab: Tab
    @Namespace private var animationNamespace
    
    // 1. Separate the complex background style to help the compiler
    private var glassEffect: some View {
        ZStack {
            // FIX: Use Rectangle().fill() so it counts as a View, not just a Style
            Rectangle()
                .fill(.ultraThinMaterial)
            
            Color.white.opacity(0.3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 35, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 35, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.8),
                            .white.opacity(0.2),
                            .white.opacity(0.5)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .shadow(color: Color.black.opacity(0.15), radius: 25, x: 0, y: 12)
    }
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Button {
                    HapticManager.shared.light()
                    withAnimation(.interpolatingSpring(stiffness: 300, damping: 20)) {
                        selectedTab = tab
                    }
                } label: {
                    ZStack {
                        // The "Liquid Blob" Background
                        if selectedTab == tab {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.black.opacity(0.85))
                                .matchedGeometryEffect(id: "liquid_blob", in: animationNamespace)
                                .frame(height: 50)
                                .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                        
                        // Icon & Text
                        HStack(spacing: 6) {
                            Image(systemName: selectedTab == tab ? tab.icon + ".fill" : tab.icon)
                                .font(.system(size: 20, weight: selectedTab == tab ? .semibold : .regular))
                                .scaleEffect(selectedTab == tab ? 1.0 : 0.9)
                            
                            if selectedTab == tab {
                                Text(tab.rawValue.uppercased())
                                    .font(.system(size: 11, weight: .black))
                                    .kerning(1.0)
                            }
                        }
                        .foregroundColor(selectedTab == tab ? .white : .primary.opacity(0.6))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                    }
                    .contentShape(Rectangle())
                }
            }
        }
        .padding(6)
        .background(glassEffect) // 2. Apply the separated style here
        .padding(.horizontal, 30)
        .padding(.bottom, 20)
    }
}

// --- 6. MODALS & SCREENS ---

struct NextMealModal: View {
    @ObservedObject var vm: IOSViewModel
    @Binding var isPresented: Bool
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea().onTapGesture { isPresented = false }
            VStack(spacing: 0) {
                HStack {
                    Text("COMING UP")
                        .font(.system(size: 24, weight: .black))
                        .foregroundColor(.black)
                    Spacer()
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark")
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                            .padding(8)
                            .background(vm.appAccent)
                            .overlay(Rectangle().stroke(Color.black, lineWidth: 2))
                    }
                }
                .padding(15)
                .background(vm.appSecondary)
                .overlay(Rectangle().stroke(Color.black, lineWidth: 3))
                
                VStack(alignment: .leading, spacing: 15) {
                    Text(vm.nextMealType)
                        .font(.system(size: 14, weight: .black))
                        .padding(5)
                        .background(Color.black)
                        .foregroundColor(.white)
                    Text(vm.nextFood)
                        .font(.custom("CourierNewPS-BoldMT", size: 24))
                        .foregroundColor(.black)
                        .fixedSize(horizontal: false, vertical: true)
                    DashedLine().stroke(style: StrokeStyle(lineWidth: 2, dash: [6])).frame(height: 1).foregroundColor(.black)
                }
                .padding(25)
                .background(Color.white)
                .overlay(Rectangle().stroke(Color.black, lineWidth: 3))
            }
            .padding(30)
        }
    }
}

// --- REFACTORED VIEWS ---

struct HomeView: View {
    @ObservedObject var vm: IOSViewModel
    @Binding var showNextMealModal: Bool
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("WHAT'S IN")
                        .font(.system(size: 40, weight: .black))
                        .tracking(-2)
                        .italic()
                        .foregroundColor(.black)
                    Spacer()
                    if vm.isLoading { ProgressView().tint(.black) }
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)
                .padding(.bottom, 20)
                
                VStack(spacing: 50) {
                    // Current Meal Card
                    NeoContainer(color: .white) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("UPCOMING MEAL")
                                        .font(.system(size: 12, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 3)
                                        .background(Color.black)
                                        .foregroundColor(.white)
                                    
                                    // --- FIXED LAYOUT (Stacks Date Below Day) ---
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(vm.currentDay.uppercased())
                                            .font(.system(size: 32, weight: .black))
                                            .foregroundColor(.black)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                        
                                        Text(vm.currentDateString)
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundColor(.gray)
                                    }
                                }
                                Spacer()
                                Text(vm.currentMealType)
                                    .font(.system(size: 14, weight: .black))
                                    .padding(6)
                                    .background(vm.appAccent)
                                    .foregroundColor(.black)
                                    .overlay(Rectangle().stroke(Color.black, lineWidth: 2))
                            }
                            Rectangle().frame(height: 4).foregroundColor(.black)
                            Text(vm.currentFood)
                                .font(.custom("CourierNewPS-BoldMT", size: 32))
                                .foregroundColor(.black)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    
                    // Next Meal Preview Button
                    Button(action: {
                        withAnimation(.spring()) { showNextMealModal = true }
                    }) {
                        NeoContainer(color: vm.appSecondary) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("COMING UP NEXT:")
                                        .font(.system(size: 12, weight: .black))
                                        .padding(4)
                                        .background(Color.black)
                                        .foregroundColor(.white)
                                    Text(vm.nextMealType)
                                        .font(.system(size: 24, weight: .black))
                                        .foregroundColor(.black)
                                    Text(vm.nextFood)
                                        .font(.custom("CourierNewPS-BoldMT", size: 16))
                                        .foregroundColor(.black.opacity(0.8))
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "eye.fill").font(.title2).foregroundColor(.black)
                            }
                        }
                    }
                    .buttonStyle(NeoPressStyle(color: .clear))
                    
                    // Extra spacer for floating nav
                    Spacer().frame(height: 120)
                }
                .padding(.horizontal, 20)
            }
        }
        .refreshable { await vm.refresh(force: true) }
    }
}

struct TodayListView: View {
    @ObservedObject var vm: IOSViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack {
                    Text(vm.currentDay.uppercased())
                        .font(.system(size: 32, weight: .black))
                        .foregroundColor(.black)
                    Spacer()
                }
                .padding(20)
                .background(vm.appSecondary)
                .overlay(Rectangle().stroke(Color.black, lineWidth: 3))
                .padding(.top, 60)
                
                VStack(spacing: 20) {
                    if let dayMenu = vm.fullMenu[vm.currentDay] {
                        ForEach(Array(vm.mealOrder.enumerated()), id: \.offset) { index, meal in
                            if let food = dayMenu[meal] {
                                VStack(alignment: .leading, spacing: 0) {
                                    NeoMealRow(label: meal, food: food, isLast: index == vm.mealOrder.count - 1)
                                }
                                .padding(.bottom, 5)
                            }
                        }
                    }
                }
                .padding(25)
                .background(Color.white)
                .overlay(Rectangle().stroke(Color.black, lineWidth: 3))
                .padding(20)
                
                Spacer().frame(height: 120)
            }
        }
    }
}

struct WeekListView: View {
    @ObservedObject var vm: IOSViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                Text("FULL WEEK")
                    .font(.system(size: 30, weight: .black))
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 60)
                
                ForEach(vm.weekOrder, id: \.self) { day in
                    if let dayMenu = vm.fullMenu[day] {
                        VStack(spacing: 0) {
                            HStack {
                                Text(day.uppercased())
                                    .font(.system(size: 24, weight: .black))
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding(15)
                            .background(Color.black)
                            .overlay(Rectangle().stroke(Color.black, lineWidth: 3))
                            
                            VStack(alignment: .leading, spacing: 15) {
                                ForEach(vm.mealOrder, id: \.self) { meal in
                                    if let food = dayMenu[meal] {
                                        VStack(alignment: .leading, spacing: 5) {
                                            HStack(alignment: .top) {
                                                Text(meal.prefix(1))
                                                    .font(.system(size: 14, weight: .black))
                                                    .foregroundColor(.white)
                                                    .frame(width: 24, height: 24)
                                                    .background(Color.black)
                                                Text(food)
                                                    .font(.custom("CourierNewPS-BoldMT", size: 16))
                                                    .foregroundColor(.black)
                                                    .fixedSize(horizontal: false, vertical: true)
                                                    .padding(.leading, 5)
                                                Spacer()
                                            }
                                            if meal != "Dinner" {
                                                DashedLine().stroke(style: StrokeStyle(lineWidth: 1, dash: [3])).frame(height: 1).foregroundColor(.black.opacity(0.3)).padding(.top, 5)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(20)
                            .background(Color.white)
                            .overlay(Rectangle().stroke(Color.black, lineWidth: 3))
                        }
                        .padding(.horizontal, 20)
                    }
                }
                Spacer().frame(height: 120)
            }
            .padding(.vertical, 20)
        }
    }
}

// --- 7. MAIN CONTENT ---
struct ContentView: View {
    @StateObject private var vm = IOSViewModel()
    @State private var showNextMealModal = false
    @State private var selectedTab: Tab = .home
    
    var body: some View {
        ZStack {
            // Background
            vm.appBg.ignoresSafeArea()
            
            // Main Content Logic
            Group {
                switch selectedTab {
                case .home:
                    HomeView(vm: vm, showNextMealModal: $showNextMealModal)
                case .today:
                    TodayListView(vm: vm)
                case .week:
                    WeekListView(vm: vm)
                }
            }
            // Liquid transition animation
            .animation(.easeInOut(duration: 0.2), value: selectedTab)
            .transition(.opacity)
            
            // Bottom Liquid Floating Navigation Bar
            VStack {
                Spacer()
                LiquidFloatingNavBar(selectedTab: $selectedTab)
            }
            // No ignoresSafeArea here on purpose to let it float above the home indicator
            
            // Success Toast
            if vm.showRefreshSuccess {
                VStack {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill").font(.title3)
                        Text("Latest Menu Fetched").font(.system(size: 14, weight: .bold))
                    }
                    .padding(.vertical, 12).padding(.horizontal, 20)
                    .background(ZStack { vm.appBg; Rectangle().stroke(Color.black, lineWidth: 3) }.shadow(color: .black, radius: 0, x: 4, y: 4))
                    .foregroundColor(.black)
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
                .zIndex(200)
            }
            
            // Modal Layer
            if showNextMealModal {
                NextMealModal(vm: vm, isPresented: $showNextMealModal).zIndex(100)
            }
        }
        .onAppear {
            NotificationManager.shared.requestPermission()
            Task { await vm.refresh() }
        }
        .preferredColorScheme(.light)
    }
}

#Preview {
    ContentView()
}
