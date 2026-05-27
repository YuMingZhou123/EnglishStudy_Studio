using System.Diagnostics;
using Api.Application.Common.Interfaces;
using Api.Infrastructure.Options;
using Microsoft.Extensions.Options;

namespace Api.Infrastructure.Tts;

public sealed class LocalTtsProvider(IOptions<TtsOptions> options) : ITtsProvider
{
    public async Task<TtsAudioResult> SynthesizeAsync(
        TtsRequest request,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(request.Text))
        {
            throw new InvalidOperationException("TTS text is required.");
        }

        var ttsOptions = options.Value;
        var provider = ttsOptions.Provider.Trim().ToLowerInvariant();

        if (provider is "piper" || ShouldUsePiper(ttsOptions))
        {
            return await TrySynthesizeWithPiperAsync(request, ttsOptions, cancellationToken);
        }

        return await SynthesizeWithWindowsSpeechAsync(request, ttsOptions, cancellationToken);
    }

    private static bool ShouldUsePiper(TtsOptions options)
    {
        return options.Provider.Equals("auto", StringComparison.OrdinalIgnoreCase) &&
            !string.IsNullOrWhiteSpace(options.PiperModelPath) &&
            File.Exists(options.PiperModelPath);
    }

    private static async Task<TtsAudioResult> TrySynthesizeWithPiperAsync(
        TtsRequest request,
        TtsOptions options,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(options.PiperModelPath))
        {
            if (options.Provider.Equals("piper", StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidOperationException("Piper model path is not configured.");
            }

            return await SynthesizeWithWindowsSpeechAsync(request, options, cancellationToken);
        }

        var outputPath = BuildTempPath(".wav");
        try
        {
            var startInfo = new ProcessStartInfo
            {
                FileName = options.PiperExecutablePath,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            startInfo.ArgumentList.Add("--model");
            startInfo.ArgumentList.Add(options.PiperModelPath);
            startInfo.ArgumentList.Add("--output_file");
            startInfo.ArgumentList.Add(outputPath);

            var process = Process.Start(startInfo)
                ?? throw new InvalidOperationException("Failed to start Piper process.");

            using (process)
            {
                await process.StandardInput.WriteLineAsync(request.Text);
                process.StandardInput.Close();

                await WaitForExitAsync(process, options.ProcessTimeoutSeconds, cancellationToken);
                var error = await process.StandardError.ReadToEndAsync(cancellationToken);
                if (process.ExitCode != 0)
                {
                    if (options.Provider.Equals("piper", StringComparison.OrdinalIgnoreCase))
                    {
                        throw new InvalidOperationException($"Piper failed: {error}");
                    }

                    return await SynthesizeWithWindowsSpeechAsync(request, options, cancellationToken);
                }
            }

            var bytes = await File.ReadAllBytesAsync(outputPath, cancellationToken);
            return new TtsAudioResult(bytes, "audio/wav", ".wav", "piper", request.Voice);
        }
        catch when (!options.Provider.Equals("piper", StringComparison.OrdinalIgnoreCase))
        {
            return await SynthesizeWithWindowsSpeechAsync(request, options, cancellationToken);
        }
        finally
        {
            TryDelete(outputPath);
        }
    }

    private static async Task<TtsAudioResult> SynthesizeWithWindowsSpeechAsync(
        TtsRequest request,
        TtsOptions options,
        CancellationToken cancellationToken)
    {
        var outputPath = BuildTempPath(".wav");
        try
        {
            var rate = Math.Clamp((int)Math.Round((request.Speed - 1) * 4), -4, 4);
            var startInfo = new ProcessStartInfo
            {
                FileName = options.PowerShellPath,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            startInfo.ArgumentList.Add("-NoProfile");
            startInfo.ArgumentList.Add("-ExecutionPolicy");
            startInfo.ArgumentList.Add("Bypass");
            startInfo.ArgumentList.Add("-Command");
            startInfo.ArgumentList.Add("""
                Add-Type -AssemblyName System.Speech;
                $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer;
                $synth.Rate = [int]$env:TTS_RATE;
                $synth.SetOutputToWaveFile($env:TTS_OUTPUT);
                $synth.Speak($env:TTS_TEXT);
                $synth.Dispose();
                """);

            startInfo.Environment["TTS_TEXT"] = request.Text;
            startInfo.Environment["TTS_OUTPUT"] = outputPath;
            startInfo.Environment["TTS_RATE"] = rate.ToString();

            var process = Process.Start(startInfo)
                ?? throw new InvalidOperationException("Failed to start Windows speech process.");

            using (process)
            {
                await WaitForExitAsync(process, options.ProcessTimeoutSeconds, cancellationToken);
                var error = await process.StandardError.ReadToEndAsync(cancellationToken);
                if (process.ExitCode != 0)
                {
                    throw new InvalidOperationException($"Windows speech synthesis failed: {error}");
                }
            }

            var bytes = await File.ReadAllBytesAsync(outputPath, cancellationToken);
            return new TtsAudioResult(
                bytes,
                "audio/wav",
                ".wav",
                "windows-speech",
                request.Voice ?? options.DefaultVoice);
        }
        finally
        {
            TryDelete(outputPath);
        }
    }

    private static async Task WaitForExitAsync(
        Process process,
        int timeoutSeconds,
        CancellationToken cancellationToken)
    {
        using var timeoutCts = new CancellationTokenSource(
            TimeSpan.FromSeconds(Math.Max(5, timeoutSeconds)));
        using var linkedCts = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken,
            timeoutCts.Token);

        try
        {
            await process.WaitForExitAsync(linkedCts.Token);
        }
        catch (OperationCanceledException) when (timeoutCts.IsCancellationRequested)
        {
            try
            {
                process.Kill(entireProcessTree: true);
            }
            catch
            {
                // Process may have exited between timeout and kill.
            }

            throw new TimeoutException("TTS process timed out.");
        }
    }

    private static string BuildTempPath(string extension)
    {
        return Path.Combine(Path.GetTempPath(), $"english-study-tts-{Guid.NewGuid():N}{extension}");
    }

    private static void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                File.Delete(path);
            }
        }
        catch
        {
            // Best-effort cleanup only.
        }
    }
}
