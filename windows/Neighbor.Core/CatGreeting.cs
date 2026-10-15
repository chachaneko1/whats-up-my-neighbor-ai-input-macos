namespace Neighbor.Core
{
    /// <summary>Built-in greeting matching, shared with the versioned configuration.</summary>
    public static class CatGreeting
    {
        public static bool IsMatch(string text)
        {
            return CatConfiguration.Defaults.Matches(text);
        }
    }
}
