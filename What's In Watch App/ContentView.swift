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
    @Published var currentMealType: String = "LOADING..."
    @Published var currentFood: String = "Fetching..."
    @Published var currentDay: String = ""
    @Published var nextMealType: String = ""
    @Published var nextFood: String = ""
    @Published var isLoading: Bool = false
    @Published var fullMenu: [String: [String: String]] = [:] // Store full menu for Week View
    
    // Exact Web App Colors
    let appBg = Color(red: 1.0, green: 0.99, blue: 0.94) // #FFFDF0
    let appAccent = Color(red: 1.0, green: 0.42, blue: 0.42) // #FF6B6B
    let appPrimary = Color(red: 0.3, green: 0.8, blue: 0.77) // #4ECDC4
    let appSecondary = Color(red: 1.0, green: 0.9, blue: 0.42) // #FFE66D
    
    let menuURL = "https://gist.githubusercontent.com/the-rebooted-coder/b2d795d38fff48d9aa4e15e65d818262/raw/menu.json"
    let timeLimits = (breakfast: 11, lunch: 15, snacks: 18, dinner: 22)
    
    // Order for Week View
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
                self.currentFood = "Connection Error"
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
        
        // --- Determine Current Meal ---
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
        self.currentDay = targetDay.uppercased()
        
        if let dayMenu = data.menu[targetDay], let food = dayMenu[targetMeal] {
            self.currentFood = food
        } else {
            self.currentFood = "Not listed"
        }
        
        // --- Determine Next Meal (For "Next Up" section) ---
        let allMeals = ["Breakfast", "Lunch", "Snacks", "Dinner"]
        if let idx = allMeals.firstIndex(of: targetMeal) {
            var nextM = ""
            var nextD = targetDay
            
            if idx < 3 {
                nextM = allMeals[idx + 1]
            } else {
                nextM = "Breakfast"
                // logic for next day roughly
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

// --- 3. REUSABLE STYLES (The "Web App" Look) ---
struct NeoCard<Content: View>: View {
    let color: Color
    let content: Content
    
    init(color: Color = .white, @ViewBuilder content: () -> Content) {
        self.color = color
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            // Hard Shadow
            RoundedRectangle(cornerRadius: 0)
                .fill(Color.black)
                .offset(x: 3, y: 3)
            
            // Main Card
            RoundedRectangle(cornerRadius: 0)
                .fill(color)
                .overlay(
                    RoundedRectangle(cornerRadius: 0)
                        .stroke(Color.black, lineWidth: 2)
                )
            
            content
                .padding(8)
        }
    }
}

// --- 4. WEEK VIEW ---
struct WeekView: View {
    @ObservedObject var vm: WatchViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 15) {
                ForEach(vm.weekOrder, id: \.self) { day in
                    if let dayMenu = vm.fullMenu[day] {
                        VStack(alignment: .leading, spacing: 0) {
                            // Day Header
                            Text(day.uppercased())
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.black)
                                .padding(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black)
                                .foregroundColor(.white)
                            
                            // Meals
                            VStack(spacing: 0) {
                                ForEach(vm.mealOrder, id: \.self) { meal in
                                    if let food = dayMenu[meal] {
                                        HStack(alignment: .top) {
                                            Text(meal.prefix(1)) // B, L, S, D
                                                .font(.system(size: 10, design: .monospaced))
                                                .fontWeight(.bold)
                                                .frame(width: 15)
                                                .padding(.top, 2)
                                            
                                            Text(food)
                                                .font(.system(size: 12, design: .monospaced))
                                                .fixedSize(horizontal: false, vertical: true)
                                            Spacer()
                                        }
                                        .padding(.vertical, 4)
                                        .padding(.horizontal, 4)
                                        Divider().background(Color.black)
                                    }
                                }
                            }
                            .background(Color.white)
                            .overlay(
                                Rectangle().stroke(Color.black, lineWidth: 2)
                            )
                        }
                        .padding(.bottom, 5)
                    }
                }
            }
            .padding()
        }
        .background(vm.appBg)
        .navigationTitle("FULL WEEK")
    }
}

// --- 5. MAIN UI ---
struct ContentView: View {
    @StateObject private var vm = WatchViewModel()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    
                    // HEADER
                    HStack {
                        Text("WHAT'S IN")
                            .font(.system(.title3, design: .rounded))
                            .fontWeight(.black)
                            .italic()
                        Spacer()
                        if vm.isLoading {
                            ProgressView().scaleEffect(0.5)
                        } else {
                            Button(action: { vm.refresh() }) {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundColor(.black)
                                    .font(.caption2)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.top, 5)
                    
                    // MAIN CARD (Current Meal)
                    NeoCard(color: .white) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(vm.currentMealType)
                                    .font(.system(size: 14, design: .monospaced))
                                    .fontWeight(.black)
                                    .padding(2)
                                    .background(vm.appAccent)
                                    .foregroundColor(.black)
                                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                                
                                Spacer()
                                Text(vm.currentDay.prefix(3))
                                    .font(.system(size: 10, design: .monospaced))
                                    .bold()
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
                    
                    // NEXT UP (Small Strip)
                    HStack {
                        Text("NEXT:")
                            .font(.system(size: 10, design: .monospaced))
                            .fontWeight(.black)
                            .padding(2)
                            .background(Color.black)
                            .foregroundColor(.white)
                        
                        Text(vm.nextMealType)
                            .font(.system(size: 10, design: .monospaced))
                            .fontWeight(.bold)
                            .padding(2)
                            .background(vm.appSecondary)
                            .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
                        
                        Spacer()
                    }
                    
                    // WEEK BUTTON
                    NavigationLink(destination: WeekView(vm: vm)) {
                        Text("VIEW FULL WEEK ->")
                            .font(.system(size: 12, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(vm.appPrimary) // Teal
                            .overlay(Rectangle().stroke(Color.black, lineWidth: 2))
                            .shadow(color: .black, radius: 0, x: 2, y: 2)
                    }
                    .buttonStyle(PlainButtonStyle()) // Removes default watch button styling
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .background(vm.appBg)
            .edgesIgnoringSafeArea(.bottom)
            .onAppear {
                vm.refresh()
            }
        }
    }
}

#Preview {
    ContentView()
}
