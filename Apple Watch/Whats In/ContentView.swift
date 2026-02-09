import SwiftUI
import Combine
import UIKit

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

struct NeoButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { isPressed in
                if isPressed { HapticManager.shared.light() }
            }
    }
}

// --- 3. VIEWMODEL ---
@MainActor
class IOSViewModel: ObservableObject {
    @Published var currentMealType: String = "LOADING..."
    @Published var currentFood: String = "..."
    @Published var currentDay: String = ""
    @Published var currentDateString: String = "" // NEW: Stores "Dec 01"
    @Published var nextMealType: String = ""
    @Published var nextFood: String = ""
    @Published var isLoading: Bool = true
    @Published var showRefreshSuccess: Bool = false // NEW: Trigger for toast
    @Published var fullMenu: [String: [String: String]] = [:]
    
    // COLORS
    let appBg = Color(red: 1.0, green: 0.99, blue: 0.94)       // Cream
    let appAccent = Color(red: 1.0, green: 0.42, blue: 0.42)   // Red
    let appPrimary = Color(red: 0.3, green: 0.8, blue: 0.77)   // Teal
    let appSecondary = Color(red: 1.0, green: 0.9, blue: 0.42) // Yellow
    let appSuccess = Color(red: 0.6, green: 0.9, blue: 0.6)    // Green for toast
    
    let menuURL = "https://gist.githubusercontent.com/the-rebooted-coder/b2d795d38fff48d9aa4e15e65d818262/raw/menu.json"
    let timeLimits = (breakfast: 11, lunch: 15, snacks: 18, dinner: 22)
    
    let weekOrder = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    
    func refresh() async {
        defer { DispatchQueue.main.async { self.isLoading = false } }
        guard let url = URL(string: "\(menuURL)?t=\(Date().timeIntervalSince1970)") else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(MenuResponse.self, from: data)
            self.fullMenu = decoded.menu
            self.calculateCurrentMeal(data: decoded)
            
            // Trigger Success Toast
            DispatchQueue.main.async {
                HapticManager.shared.success()
                withAnimation { self.showRefreshSuccess = true }
                // Hide after 2 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { self.showRefreshSuccess = false }
                }
            }
        } catch {
            self.currentFood = "Connection Error"
            self.currentMealType = "OFFLINE"
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
        var dayOffset = 0
        
        if hour < timeLimits.breakfast { targetMeal = "Breakfast" }
        else if hour < timeLimits.lunch { targetMeal = "Lunch" }
        else if hour < timeLimits.snacks { targetMeal = "Snacks" }
        else if hour < timeLimits.dinner { targetMeal = "Dinner" }
        else {
            targetMeal = "Breakfast"
            dayOffset = 1 // Tomorrow
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) {
                targetDay = calendar.weekdaySymbols[calendar.component(.weekday, from: tomorrow) - 1]
            }
        }
        
        self.currentMealType = targetMeal.uppercased()
        self.currentDay = targetDay
        
        // --- Calculate Specific Date (e.g. "Dec 01") ---
        // 1. Parse Week Start (YYYY-MM-DD)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        if let weekStartDate = dateFormatter.date(from: data.meta.weekStart) {
            // 2. Find index of target day in weekOrder (0=Mon, 6=Sun)
            // Note: weekOrder starts at Monday.
            if let targetIndex = weekOrder.firstIndex(of: targetDay) {
                // 3. Add days to weekStart
                if let specificDate = calendar.date(byAdding: .day, value: targetIndex, to: weekStartDate) {
                    let displayFormatter = DateFormatter()
                    displayFormatter.dateFormat = "MMM dd" // "Dec 01" format
                    self.currentDateString = displayFormatter.string(from: specificDate)
                }
            }
        }
        
        if let dayMenu = data.menu[targetDay], let food = dayMenu[targetMeal] {
            self.currentFood = food
        } else {
            self.currentFood = "Not listed"
        }
        
        // Next Meal Logic
        let allMeals = ["Breakfast", "Lunch", "Snacks", "Dinner"]
        if let idx = allMeals.firstIndex(of: targetMeal) {
            var nextM = ""
            var nextD = targetDay
            if idx < 3 { nextM = allMeals[idx + 1] } else { nextM = "Breakfast" }
            
            self.nextMealType = nextM.uppercased()
            if let dayMenu = data.menu[nextD], let nextF = dayMenu[nextM] {
                self.nextFood = nextF
            } else {
                self.nextFood = "-"
            }
        }
    }
}

// --- 4. REUSABLE UI COMPONENTS ---

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
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 13, weight: .black))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black)
                .foregroundColor(.white)
            
            Text(food)
                .font(.custom("CourierNewPS-BoldMT", size: 18))
                .foregroundColor(.black)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
            
            if !isLast {
                DashedLine()
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .frame(height: 1)
                    .foregroundColor(.black)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
            }
        }
    }
}

// --- 5. MODALS & SUB-SCREENS ---

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
                    DashedLine()
                        .stroke(style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .frame(height: 1)
                        .foregroundColor(.black)
                }
                .padding(25)
                .background(Color.white)
                .overlay(Rectangle().stroke(Color.black, lineWidth: 3))
            }
            .padding(30)
        }
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
                VStack(spacing: 20) {
                    if let dayMenu = vm.fullMenu[vm.currentDay] {
                        ForEach(Array(vm.mealOrder.enumerated()), id: \.offset) { index, meal in
                            if let food = dayMenu[meal] {
                                NeoMealRow(label: meal, food: food, isLast: index == vm.mealOrder.count - 1)
                            }
                        }
                    } else {
                        Text("Loading...").foregroundColor(.black)
                    }
                }
                .padding(25)
                .background(Color.white)
                .overlay(Rectangle().stroke(Color.black, lineWidth: 3))
            }
            .padding(20)
        }
        .background(vm.appBg.ignoresSafeArea())
    }
}

struct WeekListView: View {
    @ObservedObject var vm: IOSViewModel
    var body: some View {
        ScrollView {
            VStack(spacing: 30) {
                ForEach(vm.weekOrder, id: \.self) { day in
                    if let dayMenu = vm.fullMenu[day] {
                        ZStack {
                            Rectangle().fill(Color.black).offset(x: 6, y: 6)
                            VStack(spacing: 0) {
                                HStack {
                                    Text(day.uppercased())
                                        .font(.system(size: 24, weight: .black))
                                        .foregroundColor(.white)
                                    Spacer()
                                }
                                .padding(15)
                                .background(Color.black)
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
                        }
                        .padding(.horizontal, 20)
                    }
                }
            }
            .padding(.vertical, 20)
        }
        .background(vm.appBg.ignoresSafeArea())
    }
}

// --- 6. MAIN CONTENT ---
struct ContentView: View {
    @StateObject private var vm = IOSViewModel()
    @State private var showNextMealModal = false
    
    var body: some View {
        NavigationView {
            ZStack {
                vm.appBg.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // HEADER
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
                    .padding(.top, 10)
                    .padding(.bottom, 20)
                    
                    ScrollView {
                        VStack(spacing: 30) {
                            
                            // 1. CURRENT MEAL CARD (With Date & Day)
                            NeoContainer(color: .white) {
                                VStack(alignment: .leading, spacing: 10) {
                                    
                                    // MATCHING WEB LAYOUT: Label, Day, Date
                                    HStack(alignment: .top) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("UPCOMING MEAL")
                                                .font(.system(size: 12, weight: .bold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 3)
                                                .background(Color.black)
                                                .foregroundColor(.white)
                                            
                                            HStack(alignment: .lastTextBaseline, spacing: 8) {
                                                Text(vm.currentDay.uppercased())
                                                    .font(.system(size: 28, weight: .black)) // Big Day
                                                    .foregroundColor(.black)
                                                
                                                Text(vm.currentDateString)
                                                    .font(.system(size: 18, weight: .bold)) // Smaller Date
                                                    .foregroundColor(.gray)
                                            }
                                        }
                                        Spacer()
                                        
                                        // Refresh indicator / Meal Type Badge
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
                            
                            // 2. NEXT MEAL
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
                            .buttonStyle(NeoButtonStyle())
                            
                            // 3. NAVIGATION BUTTONS
                            HStack(spacing: 20) {
                                NavigationLink(destination: TodayListView(vm: vm)) {
                                    ZStack {
                                        Rectangle().fill(Color.black).offset(x: 4, y: 4)
                                        Rectangle().fill(Color.white).overlay(Rectangle().stroke(Color.black, lineWidth: 3))
                                        Text("VIEW TODAY")
                                            .font(.system(size: 16, weight: .black))
                                            .foregroundColor(.black)
                                    }
                                    .frame(height: 60)
                                }
                                .buttonStyle(NeoButtonStyle())
                                
                                NavigationLink(destination: WeekListView(vm: vm)) {
                                    ZStack {
                                        Rectangle().fill(Color.black).offset(x: 4, y: 4)
                                        Rectangle().fill(vm.appPrimary).overlay(Rectangle().stroke(Color.black, lineWidth: 3))
                                        Text("FULL WEEK")
                                            .font(.system(size: 16, weight: .black))
                                            .foregroundColor(.black)
                                    }
                                    .frame(height: 60)
                                }
                                .buttonStyle(NeoButtonStyle())
                            }
                            .padding(.bottom, 20)
                        }
                        .padding(.horizontal, 20)
                    }
                    .refreshable {
                        await vm.refresh()
                    }
                }
                
                // REFRESH SUCCESS TOAST
                if vm.showRefreshSuccess {
                    VStack {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                            Text("Latest Menu Fetched")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 20)
                        .background(vm.appBg) // Cream background to match app
                        .overlay(Rectangle().stroke(Color.black, lineWidth: 3)) // Neo border
                        .shadow(color: .black, radius: 0, x: 4, y: 4) // Neo shadow
                        .foregroundColor(.black)
                        .padding(.top, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        
                        Spacer()
                    }
                    .zIndex(200)
                }
                
                // MODAL LAYER
                if showNextMealModal {
                    NextMealModal(vm: vm, isPresented: $showNextMealModal).zIndex(100)
                }
            }
            .onAppear { Task { await vm.refresh() } }
            .preferredColorScheme(.light)
        }
        .accentColor(.black)
    }
}

#Preview {
    ContentView()
}
