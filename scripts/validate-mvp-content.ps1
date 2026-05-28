param(
    [string]$ContentPath = ""
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

if ([string]::IsNullOrWhiteSpace($ContentPath)) {
    $ContentPath = Join-Path $PSScriptRoot "..\content\mvp-sentence-pack.json"
}

$ContentPath = [System.IO.Path]::GetFullPath($ContentPath)
if (-not (Test-Path -LiteralPath $ContentPath)) {
    throw "Content file not found: $ContentPath"
}

$json = Get-Content -LiteralPath $ContentPath -Raw -Encoding UTF8 | ConvertFrom-Json
$items = @($json.items)
$allowedLevels = @("beginner", "intermediate", "advanced")
$issues = New-Object System.Collections.Generic.List[string]

function Add-Issue([string]$message) {
    $issues.Add($message)
}

if ($items.Count -eq 0) {
    Add-Issue "Content pack must contain at least one item."
}

$duplicateTexts = @($items | Group-Object text | Where-Object { $_.Count -gt 1 })
foreach ($duplicate in $duplicateTexts) {
    Add-Issue "Duplicate sentence text: $($duplicate.Name)"
}

for ($index = 0; $index -lt $items.Count; $index++) {
    $rowNumber = $index + 1
    $item = $items[$index]
    $text = [string]$item.text

    if ([string]::IsNullOrWhiteSpace($item.text)) {
        Add-Issue "Row $rowNumber text is required."
        continue
    }

    if ([string]::IsNullOrWhiteSpace($item.translation)) {
        Add-Issue "Row $rowNumber translation is required."
    }

    if ([string]::IsNullOrWhiteSpace($item.sceneCode)) {
        Add-Issue "Row $rowNumber sceneCode is required."
    }

    if ([string]::IsNullOrWhiteSpace($item.sceneName)) {
        Add-Issue "Row $rowNumber sceneName is required."
    }

    if ($allowedLevels -notcontains ([string]$item.level)) {
        Add-Issue "Row $rowNumber level must be beginner, intermediate, or advanced."
    }

    $keywords = @($item.keywords)
    if ($keywords.Count -lt 2) {
        Add-Issue "Row $rowNumber must contain at least 2 keywords."
    }

    for ($keywordIndex = 0; $keywordIndex -lt $keywords.Count; $keywordIndex++) {
        $keywordNumber = $keywordIndex + 1
        $keyword = $keywords[$keywordIndex]

        if ([string]::IsNullOrWhiteSpace($keyword.lemma)) {
            Add-Issue "Row $rowNumber keyword $keywordNumber lemma is required."
        }

        if ([string]::IsNullOrWhiteSpace($keyword.meaningCn)) {
            Add-Issue "Row $rowNumber keyword $keywordNumber meaningCn is required."
        }

        if ([string]::IsNullOrWhiteSpace($keyword.surfaceText)) {
            Add-Issue "Row $rowNumber keyword $keywordNumber surfaceText is required."
            continue
        }

        if ($text.IndexOf([string]$keyword.surfaceText, [System.StringComparison]::OrdinalIgnoreCase) -lt 0) {
            Add-Issue "Row $rowNumber keyword $keywordNumber surfaceText does not appear in sentence: $($keyword.surfaceText)"
        }
    }
}

$keywordRows = ($items | ForEach-Object { @($_.keywords).Count } | Measure-Object -Sum).Sum
$distinctLemmas = @(
    $items |
        ForEach-Object { $_.keywords } |
        ForEach-Object { ([string]$_.lemma).Trim().ToLowerInvariant() } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object -Unique
)

$levelCounts = [ordered]@{}
foreach ($level in $allowedLevels) {
    $levelCounts[$level] = @($items | Where-Object { $_.level -eq $level }).Count
}

$summary = [pscustomobject]@{
    contentPath = $ContentPath
    items = $items.Count
    scenes = @($items | ForEach-Object { $_.sceneCode } | Sort-Object -Unique).Count
    keywordRows = [int]$keywordRows
    distinctLemmas = $distinctLemmas.Count
    levelCounts = $levelCounts
    issueCount = $issues.Count
}

$summary | ConvertTo-Json -Depth 6

if ($issues.Count -gt 0) {
    $issues | ForEach-Object { Write-Error $_ }
    throw "Content validation failed with $($issues.Count) issue(s)."
}

Write-Host "Content validation passed."
