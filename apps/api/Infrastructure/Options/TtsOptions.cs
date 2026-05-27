namespace Api.Infrastructure.Options;

public sealed class TtsOptions
{
    public const string SectionName = "Tts";

    public string Provider { get; init; } = "auto";

    public string PiperExecutablePath { get; init; } = "piper";

    public string? PiperModelPath { get; init; }

    public string DefaultVoice { get; init; } = "en-US";

    public string PowerShellPath { get; init; } = "powershell";

    public int ProcessTimeoutSeconds { get; init; } = 60;
}
