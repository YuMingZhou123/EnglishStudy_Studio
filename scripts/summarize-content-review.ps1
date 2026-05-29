param(
    [string]$ReviewPath = ""
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

if ([string]::IsNullOrWhiteSpace($ReviewPath)) {
    $ReviewPath = Join-Path $PSScriptRoot "..\content\mvp-content-review.csv"
}

$ReviewPath = [System.IO.Path]::GetFullPath($ReviewPath)
if (-not (Test-Path -LiteralPath $ReviewPath)) {
    throw "Review file not found: $ReviewPath. Run .\scripts\export-content-review-sheet.ps1 first."
}

function Get-Status($value) {
    return ([string]$value).Trim().ToLowerInvariant()
}

function Get-Notes($row) {
    return @(
        [string]$row.SentenceNotes,
        [string]$row.TranslationNotes,
        [string]$row.KeywordNotes,
        [string]$row.AudioNotes,
        [string]$row.FinalNotes
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}

$allowedStatuses = @(
    "pass",
    "fix_sentence",
    "fix_translation",
    "fix_keyword",
    "fix_audio",
    "remove"
)

$rows = @(Import-Csv -LiteralPath $ReviewPath -Encoding UTF8)
$passRows = @($rows | Where-Object { (Get-Status $_.ReviewStatus) -eq "pass" })
$fixRows = @($rows | Where-Object {
    $status = Get-Status $_.ReviewStatus
    $status.StartsWith("fix_") -or $status -eq "remove"
})
$blankRows = @($rows | Where-Object { [string]::IsNullOrWhiteSpace($_.ReviewStatus) })
$invalidStatusRows = @($rows | Where-Object {
    $status = Get-Status $_.ReviewStatus
    -not [string]::IsNullOrWhiteSpace($status) -and $allowedStatuses -notcontains $status
})
$notesWithoutStatusRows = @($rows | Where-Object {
    [string]::IsNullOrWhiteSpace([string]$_.ReviewStatus) -and @(Get-Notes $_).Count -gt 0
})
$missingNoteRows = @($rows | Where-Object {
    $status = Get-Status $_.ReviewStatus
    $allowedStatuses -contains $status -and $status -ne "pass" -and @(Get-Notes $_).Count -eq 0
})

$scenePassCounts = @{}
foreach ($group in ($passRows | Group-Object SceneCode)) {
    $scenePassCounts[$group.Name] = $group.Count
}

$levelPassCounts = @{}
foreach ($group in ($passRows | Group-Object Level)) {
    $levelPassCounts[$group.Name] = $group.Count
}

$allScenesHaveMinimum = $true
foreach ($scene in @($rows | ForEach-Object { $_.SceneCode } | Sort-Object -Unique)) {
    if (-not $scenePassCounts.ContainsKey($scene) -or $scenePassCounts[$scene] -lt 15) {
        $allScenesHaveMinimum = $false
        break
    }
}

$allLevelsHaveMinimum = $true
foreach ($level in @("beginner", "intermediate", "advanced")) {
    if (-not $levelPassCounts.ContainsKey($level) -or $levelPassCounts[$level] -lt 15) {
        $allLevelsHaveMinimum = $false
        break
    }
}

$passesMinimumGate =
    $rows.Count -ge 120 -and
    $passRows.Count -ge 100 -and
    $allScenesHaveMinimum -and
    $allLevelsHaveMinimum -and
    $fixRows.Count -eq 0 -and
    $blankRows.Count -eq 0 -and
    $invalidStatusRows.Count -eq 0 -and
    $notesWithoutStatusRows.Count -eq 0 -and
    $missingNoteRows.Count -eq 0

[pscustomobject]@{
    reviewPath = $ReviewPath
    totalRows = $rows.Count
    passRows = $passRows.Count
    fixRows = $fixRows.Count
    blankRows = $blankRows.Count
    invalidStatusRows = $invalidStatusRows.Count
    notesWithoutStatusRows = $notesWithoutStatusRows.Count
    missingNoteRows = $missingNoteRows.Count
    scenePassCounts = $scenePassCounts
    levelPassCounts = $levelPassCounts
    passesMinimumGate = $passesMinimumGate
    gate = [pscustomobject]@{
        totalRows = ">= 120"
        passRows = ">= 100"
        eachScenePassRows = ">= 15"
        eachLevelPassRows = ">= 15"
        fixRows = "0"
        blankRows = "0"
        invalidStatusRows = "0"
        notesWithoutStatusRows = "0"
        missingNoteRows = "0"
    }
} | ConvertTo-Json -Depth 6
