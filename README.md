# WHAT'S IN...

### Because opening a WhatsApp group is too much work.

You live in a PG. You have a hunger. You also have a "Residents" WhatsApp group that is 10% useful information and 90% complaints about the washing machine and "Good Morning" GIFs from the landlord.

Somewhere, buried deep in that digital landfill, is a blurry JPEG of this week’s menu.

You *could* scroll up for 5 minutes to find it. You *could* download it to your gallery where it will get lost forever. Or you could use this.

**"What's In"** is a Neo-Brutalist, PWA-ready menu tracker that tells you exactly what you are about to eat based on the time of day. It’s faster than you. It’s smarter than you. And it definitely looks better than that low-res JPEG.

---

## FEATURES

### 1. It Knows Time
We used advanced alien technology (JavaScript `Date` object) to figure out if it's Breakfast, Lunch, Snacks, or Dinner. You open the app. It shows you the food. You close the app. Zero clicks required.

### 2. Neo-Brutalist Design
Soft shadows and rounded corners are for the weak. We use hard borders, high contrast, and a font that screams at you. It’s ugly-beautiful. Like you.

### 3. Offline First
Your PG Wi-Fi is probably trash. We know. That's why this thing caches everything. It works when the internet doesn't.

### 4. Auto-Updates
When we push a menu change, the app knows. A toast notification pops up. You click "UPDATE NOW." The app refreshes. It’s not rocket science, it’s just better.

---

## SETUP INSTRUCTION
(For the nerds who actually want to deploy this)

### Step 1: Steal the Code
Clone this repo. Download the zip. We don't care how you get it on your machine.

### Step 2: The Data Source
We don't have a backend database because we aren't over-engineering a menu app. We use a raw JSON file hosted on GitHub Gist.

Create a `menu.json` that looks exactly like this. Do not mess up the syntax.

```json
{
  "meta": {
    "weekStart": "2024-12-01", 
    "lastUpdated": "2024-11-30"
  },
  "menu": {
    "Monday": {
      "Breakfast": "Aloo Paratha, Curd",
      "Lunch": "Rice, Dal, Bhindi Fry",
      "Snacks": "Tea, Biscuit",
      "Dinner": "Roti, Chicken Curry"
    },
    "Tuesday": {
      "Breakfast": "Idli, Sambar",
      "Lunch": "Rice, Rajma",
      "Snacks": "Coffee, Samosa",
      "Dinner": "Fried Rice, Manchurian"
    }
    // ... do the rest of the week. You know how days work.
  }
}
