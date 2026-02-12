import SwiftUI
import Combine

// --- 1. DATA MODELS ---
struct MenuResponse: Codable {
    let meta: Meta
    let menu: [String: [String: String]]
}

struct Meta: Codable {
    let weekStart: String
}

// --- 2. LOGIC (ViewModel) ---
@MainActor
class WatchViewModel: ObservableObject {
    @Published var currentMealType: String = "..."
    @Published var currentFood: String = "Loading..."
    @Published var currentDay: String = ""
    @Published var isLoading: Bool = false
    @Published var fullMenu: [String: [String: String]] = [:]
    
    // --- APP COLORS ---
    let appBg = Color(red: 1.0, green: 0.99, blue: 0.94)       // Cream
    let appAccent = Color(red: 1.0, green: 0.42, blue: 0.42)   // Red
    let appPrimary = Color(red: 0.3, green: 0.8, blue: 0.77)   // Teal
    
    // Dark Brown Gradient (Essential for White System Text on Cream Background)
    let statusBarGradient = Color(red: 0.25, green: 0.22, blue: 0.18)
    
    let menuURL = "https://gist.githubusercontent.com/the-rebooted-coder/b2d795d38fff48d9aa4e15e65d818262/raw/menu.json"
    let timeLimits = (breakfast: 11, lunch: 15, snacks: 18, dinner: 22)
    
    let weekOrder = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    let mealOrder = ["Breakfast", "Lunch", "Snacks", "Dinner"]
    
    func refresh() {
        isLoading = true
        guard let url = URL(string: "\(menuURL)?t=\(Date().timeIntervalSince1970)") else { return }
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let decoded = try JSONDecoder().decode(MenuResponse.self, from: data)
                self.fullMenu = decoded.menu
                self.calculateCurrentMeal(data: decoded)
            } catch {
                self.currentFood = "Connection Failed"
                self.currentMealType = "OFFLINE"
            }
            self.isLoading = false
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
        
        if hour < timeLimits.breakfast { targetMeal = "Breakfast" }
        else if hour < timeLimits.lunch { targetMeal = "Lunch" }
        else if hour < timeLimits.snacks { targetMeal = "Snacks" }
        else if hour < timeLimits.dinner { targetMeal = "Dinner" }
        else {
            targetMeal = "Breakfast"
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) {
                targetDay = calendar.weekdaySymbols[calendar.component(.weekday, from: tomorrow) - 1]
            }
        }
        
        self.currentMealType = targetMeal.uppercased()
        self.currentDay = targetDay
        
        if let dayMenu = data.menu[targetDay], let food = dayMenu[targetMeal] {
            self.currentFood = food
        } else {
            self.currentFood = "Not listed"
        }
    }
}

// --- 3. UI COMPONENTS ---

struct NeoCard<Content: View>: View {
    let color: Color
    let content: Content
    
    init(color: Color = .white, @ViewBuilder content: () -> Content) {
        self.color = color
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            Rectangle().fill(Color.black).offset(x: 4, y: 4)
            Rectangle().fill(color).overlay(Rectangle().stroke(Color.black, lineWidth: 3))
            content.padding(8)
        }
        .padding(.trailing, 4).padding(.bottom, 4)
    }
}

// --- 4. SUB-SCREENS ---
struct TodayView: View {
    @ObservedObject var vm: WatchViewModel
    
    var body: some View {
        ZStack {
            // Background Layer
            vm.appBg.ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    if let dayMenu = vm.fullMenu[vm.currentDay] {
                        ForEach(vm.mealOrder, id: \.self) { meal in
                            if let food = dayMenu[meal] {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(meal.uppercased())
                                        .font(.system(size: 10, design: .monospaced))
                                        .fontWeight(.black)
                                        .padding(3)
                                        .background(Color.black)
                                        .foregroundColor(.white)
                                    Text(food)
                                        .font(.system(size: 14, design: .monospaced))
                                        .fontWeight(.bold)
                                        .foregroundColor(.black)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Divider().background(Color.black)
                                }
                            }
                        }
                    } else {
                        Text("Loading...").foregroundColor(.black)
                    }
                }
                .padding()
            }
            
            // GRADIENT FOR SYSTEM HEADER LEGIBILITY
            // Native titles are white. This gradient ensures they are readable on cream.
            VStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        vm.statusBarGradient,
                        vm.statusBarGradient.opacity(0.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 50)
                .edgesIgnoringSafeArea(.top)
                .allowsHitTesting(false)
                Spacer()
            }
        }
        .navigationTitle("Today") // Native System Title
        .navigationBarTitleDisplayMode(.large) // Uses standard large scrolling title
    }
}

struct WeekView: View {
    @ObservedObject var vm: WatchViewModel
    
    var body: some View {
        ZStack {
            // Background Layer
            vm.appBg.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(vm.weekOrder, id: \.self) { day in
                        if let dayMenu = vm.fullMenu[day] {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(day.uppercased())
                                    .font(.system(.caption, design: .monospaced))
                                    .fontWeight(.black)
                                    .padding(5)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.black)
                                    .foregroundColor(.white)
                                VStack(spacing: 0) {
                                    ForEach(vm.mealOrder, id: \.self) { meal in
                                        if let food = dayMenu[meal] {
                                            HStack(alignment: .top) {
                                                Text(meal.prefix(1))
                                                    .font(.system(size: 10, design: .monospaced))
                                                    .fontWeight(.bold)
                                                    .foregroundColor(.black)
                                                    .frame(width: 15)
                                                    .padding(.top, 2)
                                                Text(food)
                                                    .font(.system(size: 12, design: .monospaced))
                                                    .foregroundColor(.black)
                                                    .fixedSize(horizontal: false, vertical: true)
                                                Spacer()
                                            }
                                            .padding(.vertical, 6)
                                            .padding(.horizontal, 4)
                                            Divider().background(Color.black)
                                        }
                                    }
                                }
                            }
                            .background(Color.white)
                            .overlay(Rectangle().stroke(Color.black, lineWidth: 2))
                        }
                    }
                }
                .padding()
            }
            
            // GRADIENT FOR SYSTEM HEADER LEGIBILITY
            VStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        vm.statusBarGradient,
                        vm.statusBarGradient.opacity(0.0)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 50)
                .edgesIgnoringSafeArea(.top)
                .allowsHitTesting(false)
                Spacer()
            }
        }
        .navigationTitle("This Week") // Native System Title
        .navigationBarTitleDisplayMode(.large)
    }
}

// --- 5. MAIN CONTENT VIEW ---
struct ContentView: View {
    @StateObject private var vm = WatchViewModel()
    @State private var showToday = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // 1. BACKGROUND
                vm.appBg.ignoresSafeArea()
                
                // 2. MAIN CONTENT
                ScrollView {
                    VStack(spacing: 12) {
                        
                        // Header
                        HStack {
                            Text("WHAT'S IN")
                                .font(.system(size: 26, weight: .black, design: .default))
                                .tracking(-1)
                                .foregroundColor(.black)
                            Spacer()
                            
                            if vm.isLoading {
                                ProgressView().scaleEffect(0.5)
                            }
                        }
                        .padding(.top, 10)
                        
                        // Main Card
                        NeoCard(color: .white) {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(vm.currentMealType)
                                        .font(.system(size: 14, design: .monospaced))
                                        .fontWeight(.black)
                                        .padding(4)
                                        .background(vm.appAccent)
                                        .foregroundColor(.black)
                                        .overlay(Rectangle().stroke(Color.black, lineWidth: 2))
                                    Spacer()
                                }
                                Divider().background(Color.black)
                                Text(vm.currentFood)
                                    .font(.system(size: 16, design: .monospaced))
                                    .fontWeight(.bold)
                                    .foregroundColor(.black)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.top, 2)
                            }
                        }
                        
                        // Navigation Buttons
                        HStack(spacing: 10) {
                            NavigationLink(destination: TodayView(vm: vm), isActive: $showToday) {
                                ZStack {
                                    Rectangle().fill(Color.white)
                                    Rectangle().stroke(Color.black, lineWidth: 2)
                                    Text("TODAY")
                                        .font(.system(size: 12, design: .monospaced))
                                        .fontWeight(.bold)
                                        .foregroundColor(.black)
                                }
                                .frame(height: 40)
                                .background(Color.black.offset(x: 2, y: 2))
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            NavigationLink(destination: WeekView(vm: vm)) {
                                ZStack {
                                    Rectangle().fill(vm.appPrimary)
                                    Rectangle().stroke(Color.black, lineWidth: 2)
                                    Text("WEEK")
                                        .font(.system(size: 12, design: .monospaced))
                                        .fontWeight(.bold)
                                        .foregroundColor(.black)
                                }
                                .frame(height: 40)
                                .background(Color.black.offset(x: 2, y: 2))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    showToday = true
                }
                
                // 3. STATUS BAR GRADIENT (Main Screen)
                VStack {
                    LinearGradient(
                        gradient: Gradient(colors: [
                            vm.statusBarGradient,
                            vm.statusBarGradient.opacity(0.0)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 40)
                    .edgesIgnoringSafeArea(.top)
                    .allowsHitTesting(false)
                    
                    Spacer()
                }
            }
            // Hide nav bar ONLY on root, allow it on sub-screens
            .navigationBarHidden(true)
        }
        .onAppear {
            vm.refresh()
        }
    }
}

#Preview {
    ContentView()
}
