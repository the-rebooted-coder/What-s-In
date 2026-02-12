using Microsoft.UI;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Microsoft.Windows.AppNotifications;
using Microsoft.Windows.AppNotifications.Builder;
using Windows.UI.Notifications;
using Windows.Data.Xml.Dom;
using System;
using System.Net.Http;
using System.Text.Json;
using System.Threading.Tasks;
using System.Collections.Generic;
using Windows.Graphics;
using WhatsInApp.Models;

namespace WhatsInApp
{
    public sealed partial class MainWindow : Window
    {
        private const string MENU_URL = "https://gist.githubusercontent.com/the-rebooted-coder/b2d795d38fff48d9aa4e15e65d818262/raw/menu.json";
        private MenuResponse? _currentData;
        private readonly HttpClient _client = new HttpClient();

        public MainWindow()
        {
            this.InitializeComponent();
            ExtendsContentIntoTitleBar = true;
            this.Title = "What's In";

            var appWindow = this.AppWindow;
            appWindow.Resize(new SizeInt32(500, 850));
            if (appWindow.Presenter is OverlappedPresenter presenter)
            {
                presenter.IsMaximizable = false;
                presenter.IsResizable = false;
            }
            DisplayArea displayArea = DisplayArea.GetFromWindowId(appWindow.Id, DisplayAreaFallback.Primary);
            int centeredX = (displayArea.WorkArea.Width - 500) / 2;
            int centeredY = (displayArea.WorkArea.Height - 850) / 2;
            appWindow.Move(new PointInt32(centeredX, centeredY));

            if (Microsoft.UI.Windowing.AppWindowTitleBar.IsCustomizationSupported())
            {
                var titleBar = appWindow.TitleBar;
                titleBar.ButtonBackgroundColor = Colors.Transparent;
                titleBar.ButtonForegroundColor = Colors.Black;
                titleBar.ButtonHoverBackgroundColor = Colors.Black;
                titleBar.ButtonHoverForegroundColor = Colors.White;
                titleBar.ButtonInactiveBackgroundColor = Colors.Transparent;
                titleBar.ButtonInactiveForegroundColor = Colors.Gray;
            }

            _ = FetchMenuAsync();
        }

        private void NavView_Loaded(object sender, RoutedEventArgs e) => NavView.SelectedItem = NavView.MenuItems[0];

        private void NavView_SelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
        {
            if (args.SelectedItem is NavigationViewItem item)
            {
                if (item.Tag.ToString() == "home")
                {
                    HomePanel.Visibility = Visibility.Visible;
                    WeekPanel.Visibility = Visibility.Collapsed;
                }
                else
                {
                    HomePanel.Visibility = Visibility.Collapsed;
                    WeekPanel.Visibility = Visibility.Visible;
                    RenderWeekView();
                }
            }
        }

        private async Task FetchMenuAsync()
        {
            try
            {
                DispatcherQueue.TryEnqueue(() => FoodItems.Text = "Syncing...");
                string url = $"{MENU_URL}?t={DateTime.Now.Ticks}";
                string json = await _client.GetStringAsync(url);
                _currentData = JsonSerializer.Deserialize<MenuResponse>(json);
                DispatcherQueue.TryEnqueue(() => {
                    RenderHomeView();
                    ScheduleWeeklyNotifications();
                });
            }
            catch { /* Ignore */ }
        }

        private void Refresh_Click(object sender, RoutedEventArgs e) => _ = FetchMenuAsync();

        private void ScheduleWeeklyNotifications()
        {
            if (_currentData?.Menu == null) return;
            var notifier = ToastNotificationManager.CreateToastNotifier();
            var mealTimes = new Dictionary<string, int> { { "Breakfast", 9 }, { "Lunch", 13 }, { "Snacks", 17 }, { "Dinner", 20 } };
            var now = DateTime.Now;

            for (int i = 0; i < 7; i++)
            {
                var targetDate = now.AddDays(i);
                string dayName = targetDate.DayOfWeek.ToString();

                if (_currentData.Menu.ContainsKey(dayName))
                {
                    foreach (var meal in mealTimes)
                    {
                        var notifyTime = new DateTime(targetDate.Year, targetDate.Month, targetDate.Day, meal.Value, 0, 0);
                        if (notifyTime > now)
                        {
                            string food = _currentData.Menu[dayName].ContainsKey(meal.Key) ? _currentData.Menu[dayName][meal.Key] : "Check Menu";
                            string xml = $@"<toast><visual><binding template='ToastGeneric'><text>{meal.Key} Time</text><text>{food}</text></binding></visual></toast>";
                            var doc = new XmlDocument();
                            doc.LoadXml(xml);
                            notifier.AddToSchedule(new ScheduledToastNotification(doc, notifyTime));
                        }
                    }
                }
            }
        }

        private void RenderHomeView()
        {
            if (_currentData?.Menu == null) return;
            var now = DateTime.Now;
            string currentDay = now.DayOfWeek.ToString();

            // 1. Determine Current Meal
            int hour = now.Hour;
            string targetMeal = "Breakfast";
            if (hour < 11) targetMeal = "Breakfast";
            else if (hour < 15) targetMeal = "Lunch";
            else if (hour < 18) targetMeal = "Snacks";
            else if (hour < 22) targetMeal = "Dinner";
            else targetMeal = "Breakfast"; // Late night -> Breakfast

            DayText.Text = currentDay.ToUpper();
            DateText.Text = now.ToString("MMM dd");
            MealType.Text = targetMeal.ToUpper();

            if (_currentData.Menu.ContainsKey(currentDay))
            {
                var menu = _currentData.Menu[currentDay];
                string food = menu.ContainsKey(targetMeal) ? menu[targetMeal] : "-";
                FoodItems.Text = food;

                // 2. FIXED LOGIC FOR NEXT MEAL
                string nextMealName = "";
                string nextDayName = currentDay; // Default to same day

                if (targetMeal == "Dinner")
                {
                    // If it is Dinner, next is Breakfast TOMORROW
                    nextMealName = "Breakfast";
                    nextDayName = now.AddDays(1).DayOfWeek.ToString(); // Safely gets "Friday" if today is "Thursday"
                }
                else
                {
                    // Same day, just next item
                    string[] order = { "Breakfast", "Lunch", "Snacks", "Dinner" };
                    int idx = Array.IndexOf(order, targetMeal);
                    nextMealName = order[idx + 1];
                }

                // 3. Render Next Meal
                NextMealType.Text = nextMealName.ToUpper();

                if (_currentData.Menu.ContainsKey(nextDayName) && _currentData.Menu[nextDayName].ContainsKey(nextMealName))
                {
                    NextFoodItems.Text = _currentData.Menu[nextDayName][nextMealName];
                }
                else
                {
                    NextFoodItems.Text = "Not listed";
                }
            }
        }

        private void RenderWeekView()
        {
            if (_currentData?.Menu == null) return;
            WeekPanel.Children.Clear();
            var days = new List<string> { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" };
            string[] meals = { "Breakfast", "Lunch", "Snacks", "Dinner" };

            foreach (var day in days)
            {
                if (!_currentData.Menu.ContainsKey(day)) continue;

                var grid = new Grid();
                grid.Children.Add(new Border { Background = new SolidColorBrush(Colors.Black), Margin = new Thickness(6, 6, 0, 0) });

                var card = new Border { Background = new SolidColorBrush(Colors.White), BorderBrush = new SolidColorBrush(Colors.Black), BorderThickness = new Thickness(4), Padding = new Thickness(20) };
                var stack = new StackPanel { Spacing = 10 };

                stack.Children.Add(new TextBlock { Text = day.ToUpper(), FontFamily = (FontFamily)Application.Current.Resources["BlockFont"], FontSize = 24, Foreground = new SolidColorBrush(Colors.Black) });
                stack.Children.Add(new Rectangle { Stroke = new SolidColorBrush(Colors.Black), StrokeThickness = 2, StrokeDashArray = new DoubleCollection { 4, 2 }, Height = 2, Margin = new Thickness(0, 0, 0, 10) });

                foreach (var meal in meals)
                {
                    var mStack = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 15, Margin = new Thickness(0, 0, 0, 8) };
                    var badge = new Border { Background = new SolidColorBrush(Colors.Black), Padding = new Thickness(6, 3, 6, 3), VerticalAlignment = VerticalAlignment.Top };
                    badge.Child = new TextBlock { Text = meal.ToUpper(), Foreground = new SolidColorBrush(Colors.White), FontFamily = (FontFamily)Application.Current.Resources["CourierFont"], FontSize = 12, FontWeight = Microsoft.UI.Text.FontWeights.Bold };
                    var fText = new TextBlock { Text = _currentData.Menu[day].ContainsKey(meal) ? _currentData.Menu[day][meal] : "-", FontFamily = (FontFamily)Application.Current.Resources["CourierFont"], FontSize = 14, TextWrapping = TextWrapping.Wrap, Width = 280, Foreground = new SolidColorBrush(Colors.Black) };
                    mStack.Children.Add(badge);
                    mStack.Children.Add(fText);
                    stack.Children.Add(mStack);
                }
                card.Child = stack;
                grid.Children.Add(card);
                WeekPanel.Children.Add(grid);
            }
        }
    }
}