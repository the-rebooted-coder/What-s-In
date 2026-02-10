import AppIntents
import Foundation

// --- 1. INTENT DEFINITION ---
// This is the function Siri runs when you speak
struct CheckMenuIntent: AppIntent {
    
    // The name users see in the Shortcuts app
    static var title: LocalizedStringResource = "Check Next Meal"
    static var description = IntentDescription("Checks what is being served next based on the current time.")
    
    // This allows Siri to speak the result without opening the app screen
    static var openAppWhenRun: Bool = false
    
    // ⚠️ CRITICAL: Ensure this matches your App Group ID exactly
    let appGroupSuite = "group.com.onesilicondiode.menutracker"
    let timeLimits = (breakfast: 11, lunch: 15, snacks: 18, dinner: 22)

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        
        // 1. Try to load data from the shared App Group
        guard let sharedDefaults = UserDefaults(suiteName: appGroupSuite),
              let data = sharedDefaults.data(forKey: "cachedMenuData"),
              let decoded = try? JSONDecoder().decode(IntentMenuResponse.self, from: data)
        else {
            return .result(
                value: "No Menu Found",
                dialog: "I don't have the menu data yet. Please open the What's In app to sync."
            )
        }
        
        // 2. Logic to find the current meal (Same logic as your Widget)
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
        
        // 3. Get the food item
        let food = decoded.menu[targetDay]?[targetMeal] ?? "Nothing listed"
        
        // 4. Create the natural language response
        let spokenResponse = "For \(targetMeal) on \(targetDay), it is \(food)."
        
        // 5. Return the result to Siri
        return .result(
            value: food,
            dialog: IntentDialog(stringLiteral: spokenResponse)
        )
    }
}

// --- 2. SHORTCUTS PROVIDER ---
// This automatically registers the phrases with Siri
struct MenuShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckMenuIntent(),
            phrases: [
                "What's to eat in \(.applicationName)?",
                "Check menu in \(.applicationName)",
                "What is in \(.applicationName)?"
            ],
            shortTitle: "Check Next Meal",
            systemImageName: "fork.knife"
        )
    }
}

// --- 3. DATA MODELS ---
// Local copies of your models so this file is self-contained
struct IntentMenuResponse: Codable {
    let meta: IntentMeta
    let menu: [String: [String: String]]
}

struct IntentMeta: Codable {
    let weekStart: String
}
