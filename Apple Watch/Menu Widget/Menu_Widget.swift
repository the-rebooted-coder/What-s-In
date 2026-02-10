import WidgetKit
import SwiftUI

// --- 1. SHARED MODELS ---
struct MenuResponse: Codable {
    let meta: Meta
    let menu: [String: [String: String]]
}

struct Meta: Codable {
    let weekStart: String
}

// --- 2. TIMELINE ENTRY ---
struct SimpleEntry: TimelineEntry {
    let date: Date
    let mealType: String
    let food: String
    let day: String
}

// --- 3. TIMELINE PROVIDER ---
struct Provider: TimelineProvider {
    // ⚠️ Ensure this matches your Main App's Group ID
    let appGroupSuite = "group.com.onesilicondiode.menutracker"
    
    let timeLimits = (breakfast: 11, lunch: 15, snacks: 18, dinner: 22)

    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), mealType: "LUNCH", food: "Paneer Butter Masala", day: "Monday")
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = getCurrentMealEntry(for: Date())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> ()) {
        let currentDate = Date()
        let currentEntry = getCurrentMealEntry(for: currentDate)
        let nextUpdateDate = getNextRefreshTime(from: currentDate)
        
        let timeline = Timeline(entries: [currentEntry], policy: .after(nextUpdateDate))
        completion(timeline)
    }
    
    // --- HELPER LOGIC ---
    func getNextRefreshTime(from date: Date) -> Date {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        var nextHour = 0
        
        if hour < timeLimits.breakfast { nextHour = timeLimits.breakfast }
        else if hour < timeLimits.lunch { nextHour = timeLimits.lunch }
        else if hour < timeLimits.snacks { nextHour = timeLimits.snacks }
        else if hour < timeLimits.dinner { nextHour = timeLimits.dinner }
        else { nextHour = 7 }
        
        if let nextDate = calendar.date(bySettingHour: nextHour, minute: 0, second: 0, of: date) {
            if nextDate > date { return nextDate }
            return calendar.date(byAdding: .day, value: 1, to: nextDate) ?? date.addingTimeInterval(3600)
        }
        return date.addingTimeInterval(3600)
    }

    func getCurrentMealEntry(for date: Date) -> SimpleEntry {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupSuite),
              let data = sharedDefaults.data(forKey: "cachedMenuData"),
              let decoded = try? JSONDecoder().decode(MenuResponse.self, from: data)
        else {
            return SimpleEntry(date: date, mealType: "OPEN APP", food: "To Sync Menu", day: "")
        }
        
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: "en_US")
        let hour = calendar.component(.hour, from: date)
        let todayName = calendar.weekdaySymbols[calendar.component(.weekday, from: date) - 1]
        
        var targetMeal = ""
        var targetDay = todayName
        
        if hour < timeLimits.breakfast { targetMeal = "Breakfast" }
        else if hour < timeLimits.lunch { targetMeal = "Lunch" }
        else if hour < timeLimits.snacks { targetMeal = "Snacks" }
        else if hour < timeLimits.dinner { targetMeal = "Dinner" }
        else {
            targetMeal = "Breakfast"
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) {
                targetDay = calendar.weekdaySymbols[calendar.component(.weekday, from: tomorrow) - 1]
            }
        }
        
        let food = decoded.menu[targetDay]?[targetMeal] ?? "Not listed"
        return SimpleEntry(date: date, mealType: targetMeal.uppercased(), food: food, day: targetDay)
    }
}

// --- 4. WIDGET VIEW (FINAL DESIGN) ---
struct Menu_WidgetEntryView : View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            // Header: Meal Label + Red Dot
            HStack(alignment: .center) {
                Text(entry.mealType)
                    .font(.system(size: 11, weight: .black))
                    .tracking(0.5)
                    .foregroundColor(.black.opacity(0.8))
                
                Spacer()
                
                // Red Status Dot
                Circle()
                    .fill(Color(red: 1.0, green: 0.42, blue: 0.42))
                    .frame(width: 8, height: 8)
            }
            .padding(.bottom, 12)
            
            // Main Content: Food Item
            Text(entry.food)
                .font(.custom("CourierNewPS-BoldMT", size: 16))
                .foregroundColor(.black)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer(minLength: 0)
            
            // Footer: Day + Branding
            VStack(alignment: .leading, spacing: 4) {
                if !entry.day.isEmpty {
                    Text(entry.day.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.gray.opacity(0.9))
                }
                
                // FIXED: Removed .italic() here
                Text("What's In")
                    .font(.system(size: 9, weight: .black))
                    .foregroundColor(.gray.opacity(0.4))
            }
            .padding(.top, 12)
        }
        // Padding for safe area inside the widget
        .padding(16)
        // Full bleed background color
        .containerBackground(for: .widget) {
            Color(red: 1.0, green: 0.99, blue: 0.94) // Cream
        }
    }
}

// --- 5. MAIN WIDGET CONFIG ---
struct Menu_Widget: Widget {
    let kind: String = "Menu_Widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            Menu_WidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Next Meal")
        .description("Shows the upcoming meal.")
        .supportedFamilies([.systemSmall, .systemMedium])
        // Disable default margins for edge-to-edge background
        .contentMarginsDisabled()
    }
}

// --- 6. PREVIEW ---
struct Menu_Widget_Previews: PreviewProvider {
    static var previews: some View {
        Menu_WidgetEntryView(entry: SimpleEntry(date: Date(), mealType: "DINNER", food: "Chapathi, Rajma Curry, Rice, Tomato Rasam", day: "TUESDAY"))
            .previewContext(WidgetPreviewContext(family: .systemSmall))
    }
}
