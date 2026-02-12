using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace WhatsInApp.Models
{
    public class MenuResponse
    {
        [JsonPropertyName("meta")]
        public MetaData Meta { get; set; }

        // Using Dictionary because your keys are dynamic day names (Monday, Tuesday...)
        [JsonPropertyName("menu")]
        public Dictionary<string, Dictionary<string, string>> Menu { get; set; }
    }

    public class MetaData
    {
        [JsonPropertyName("weekStart")]
        public string WeekStart { get; set; }
    }
}