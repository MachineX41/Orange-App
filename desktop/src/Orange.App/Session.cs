using System.Text.Json;

namespace Orange.App;

public sealed class Session
{
    public static Session Current { get; } = new();
    public LanguageChoice Language { get; set; } = LanguageChoice.System;
    public AppearanceChoice Appearance { get; set; } = AppearanceChoice.System;
    public bool LaunchAtLogin { get; set; }
    public bool WheelEnabled { get; set; } = true;
    public bool Onboarded { get; set; }
    public List<string> Shelf { get; } = [];
    public List<StoredJob> Jobs { get; } = [];

    static string FilePath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Orange", "settings.json");

    public void Load()
    {
        try
        {
            if (!File.Exists(FilePath)) return;
            var stored = JsonSerializer.Deserialize<Stored>(File.ReadAllText(FilePath));
            if (stored is null) return;
            Language = stored.Language;
            Appearance = stored.Appearance;
            LaunchAtLogin = stored.LaunchAtLogin;
            WheelEnabled = stored.WheelEnabled;
            Onboarded = stored.Onboarded;
            Shelf.AddRange(stored.Shelf.Where(File.Exists));
            Jobs.AddRange(stored.Jobs);
        }
        catch
        {
            // A broken settings file falls back to defaults.
        }
        Lang.Choice = Language;
    }

    public void Save()
    {
        Lang.Choice = Language;
        Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
        var stored = new Stored
        {
            Language = Language,
            Appearance = Appearance,
            LaunchAtLogin = LaunchAtLogin,
            WheelEnabled = WheelEnabled,
            Onboarded = Onboarded,
            Shelf = Shelf.ToList(),
            Jobs = Jobs.Take(200).ToList()
        };
        File.WriteAllText(FilePath, JsonSerializer.Serialize(stored));
    }

    public void Remember(string title, IReadOnlyList<string> outputs, bool success)
    {
        Jobs.Insert(0, new StoredJob { Title = title, When = DateTimeOffset.Now, Success = success, Outputs = outputs.ToList() });
        foreach (var output in outputs.Where(File.Exists))
        {
            if (!Shelf.Contains(output)) Shelf.Insert(0, output);
        }
        Save();
    }

    sealed class Stored
    {
        public LanguageChoice Language { get; set; }
        public AppearanceChoice Appearance { get; set; }
        public bool LaunchAtLogin { get; set; }
        public bool WheelEnabled { get; set; } = true;
        public bool Onboarded { get; set; }
        public List<string> Shelf { get; set; } = [];
        public List<StoredJob> Jobs { get; set; } = [];
    }
}

public sealed class StoredJob
{
    public string Title { get; set; } = "";
    public DateTimeOffset When { get; set; }
    public bool Success { get; set; }
    public List<string> Outputs { get; set; } = [];
}
