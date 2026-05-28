param(
    [string]$OutputPath = "",
    [int]$UserCount = 10
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $PSScriptRoot "..\feedback\internal-beta-feedback.csv"
}

if ($UserCount -lt 1) {
    throw "UserCount must be greater than 0."
}

$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

$rows = for ($index = 1; $index -le $UserCount; $index++) {
    [pscustomobject]@{
        UserId = "U{0:D2}" -f $index
        UserType = ""
        EnglishLevel = ""
        CompletedTest = ""
        IndependentCompletion = ""
        StuckStep = ""
        UnderstandsDifficulty = ""
        WillingNext = ""
        PerceivedUseful = ""
        AudioIssue = ""
        PageIssue = ""
        ContentIssue = ""
        Priority = ""
        Notes = ""
    }
}

$rows | Export-Csv -LiteralPath $OutputPath -NoTypeInformation -Encoding UTF8

[pscustomobject]@{
    outputPath = $OutputPath
    rows = $rows.Count
} | ConvertTo-Json -Depth 3
