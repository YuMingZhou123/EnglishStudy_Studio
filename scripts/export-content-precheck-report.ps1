param(
    [string]$ContentPath = "",
    [string]$OutputPath = "",
    [string]$CsvOutputPath = ""
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))

if ([string]::IsNullOrWhiteSpace($ContentPath)) {
    $ContentPath = Join-Path $RepoRoot "content\mvp-sentence-pack.json"
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $RepoRoot "acceptance\content-precheck-report.md"
}

if ([string]::IsNullOrWhiteSpace($CsvOutputPath)) {
    $CsvOutputPath = Join-Path $RepoRoot "content\mvp-content-precheck.csv"
}

$ContentPath = [System.IO.Path]::GetFullPath($ContentPath)
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$CsvOutputPath = [System.IO.Path]::GetFullPath($CsvOutputPath)

if (-not (Test-Path -LiteralPath $ContentPath)) {
    throw "Content file not found: $ContentPath"
}

function ConvertTo-MarkdownText($value) {
    $text = ([string]$value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return ""
    }

    return $text.Replace("\", "\\").Replace("|", "\|").Replace("`r`n", "<br>").Replace("`n", "<br>")
}

function Get-WordCount([string]$text) {
    return ([regex]::Matches($text, "[A-Za-z]+(?:'[A-Za-z]+)?")).Count
}

function Test-ContainsChinese([string]$text) {
    return $text -match "[\u4e00-\u9fff]"
}

function Test-SurfaceInText([string]$text, [string]$surfaceText) {
    if ([string]::IsNullOrWhiteSpace($text) -or [string]::IsNullOrWhiteSpace($surfaceText)) {
        return $false
    }

    $escaped = [regex]::Escape($surfaceText.Trim())
    return $text -match "(?i)(^|[^A-Za-z])$escaped([^A-Za-z]|$)"
}

function Get-LevelRange([string]$level) {
    switch ($level) {
        "beginner" { return [pscustomobject]@{ min = 5; max = 10 } }
        "intermediate" { return [pscustomobject]@{ min = 6; max = 14 } }
        "advanced" { return [pscustomobject]@{ min = 6; max = 18 } }
        default { return $null }
    }
}

function Add-Hint {
    param(
        [System.Collections.Generic.List[object]]$Hints,
        [int]$RowNumber,
        [string]$SceneCode,
        [string]$Level,
        [string]$Severity,
        [string]$Area,
        [string]$Message,
        [string]$Text
    )

    $Hints.Add([pscustomobject]@{
        RowNumber = $RowNumber
        SceneCode = $SceneCode
        Level = $Level
        Severity = $Severity
        Area = $Area
        Message = $Message
        Text = $Text
    })
}

$json = Get-Content -LiteralPath $ContentPath -Raw -Encoding UTF8 | ConvertFrom-Json
$items = @($json.items)
$allowedLevels = @("beginner", "intermediate", "advanced")
$hints = New-Object System.Collections.Generic.List[object]

for ($index = 0; $index -lt $items.Count; $index++) {
    $item = $items[$index]
    $rowNumber = $index + 1
    $sceneCode = ([string]$item.sceneCode).Trim()
    $level = ([string]$item.level).Trim().ToLowerInvariant()
    $text = ([string]$item.text).Trim()
    $translation = ([string]$item.translation).Trim()
    $keywords = @($item.keywords)

    if ([string]::IsNullOrWhiteSpace($sceneCode)) {
        Add-Hint $hints $rowNumber $sceneCode $level "issue" "scene" "SceneCode is blank." $text
    }

    if ($allowedLevels -notcontains $level) {
        Add-Hint $hints $rowNumber $sceneCode $level "issue" "level" "Level must be beginner, intermediate, or advanced." $text
    }

    if ([string]::IsNullOrWhiteSpace($text)) {
        Add-Hint $hints $rowNumber $sceneCode $level "issue" "sentence" "English sentence is blank." $text
    }
    elseif ($text -match "\s{2,}") {
        Add-Hint $hints $rowNumber $sceneCode $level "warning" "sentence" "English sentence contains repeated spaces." $text
    }

    if (-not [string]::IsNullOrWhiteSpace($text) -and $text -notmatch "[.!?]$") {
        Add-Hint $hints $rowNumber $sceneCode $level "warning" "sentence" "English sentence does not end with terminal punctuation." $text
    }

    if ([string]::IsNullOrWhiteSpace($translation)) {
        Add-Hint $hints $rowNumber $sceneCode $level "issue" "translation" "Chinese translation is blank." $text
    }
    elseif (-not (Test-ContainsChinese $translation)) {
        Add-Hint $hints $rowNumber $sceneCode $level "warning" "translation" "Translation does not contain Chinese characters." $text
    }

    $range = Get-LevelRange $level
    if ($null -ne $range -and -not [string]::IsNullOrWhiteSpace($text)) {
        $wordCount = Get-WordCount $text
        if ($wordCount -lt $range.min -or $wordCount -gt $range.max) {
            Add-Hint $hints $rowNumber $sceneCode $level "warning" "difficulty" "Sentence has $wordCount words; recommended range for $level is $($range.min)-$($range.max)." $text
        }
    }

    if ($keywords.Count -lt 2) {
        Add-Hint $hints $rowNumber $sceneCode $level "issue" "keyword" "Every MVP sentence should have at least 2 keywords." $text
    }
    elseif ($keywords.Count -gt 5) {
        Add-Hint $hints $rowNumber $sceneCode $level "warning" "keyword" "Sentence has more than 5 keywords." $text
    }

    $surfaceTexts = @()
    for ($keywordIndex = 0; $keywordIndex -lt $keywords.Count; $keywordIndex++) {
        $keyword = $keywords[$keywordIndex]
        $label = "keyword {0}" -f ($keywordIndex + 1)
        $lemma = ([string]$keyword.lemma).Trim()
        $surfaceText = ([string]$keyword.surfaceText).Trim()
        $meaningCn = ([string]$keyword.meaningCn).Trim()
        $partOfSpeech = ([string]$keyword.partOfSpeech).Trim()
        $priority = 0

        if ([string]::IsNullOrWhiteSpace($lemma)) {
            Add-Hint $hints $rowNumber $sceneCode $level "issue" "keyword" "$label lemma is blank." $text
        }

        if ([string]::IsNullOrWhiteSpace($surfaceText)) {
            Add-Hint $hints $rowNumber $sceneCode $level "issue" "keyword" "$label surfaceText is blank." $text
        }
        else {
            $surfaceTexts += $surfaceText.ToLowerInvariant()
            if (-not (Test-SurfaceInText $text $surfaceText)) {
                Add-Hint $hints $rowNumber $sceneCode $level "issue" "keyword" "$label surfaceText '$surfaceText' was not found in the sentence." $text
            }
        }

        if ([string]::IsNullOrWhiteSpace($meaningCn)) {
            Add-Hint $hints $rowNumber $sceneCode $level "issue" "keyword" "$label meaningCn is blank." $text
        }
        elseif (-not (Test-ContainsChinese $meaningCn)) {
            Add-Hint $hints $rowNumber $sceneCode $level "warning" "keyword" "$label meaningCn does not contain Chinese characters." $text
        }

        if ([string]::IsNullOrWhiteSpace($partOfSpeech)) {
            Add-Hint $hints $rowNumber $sceneCode $level "warning" "keyword" "$label partOfSpeech is blank." $text
        }

        if (-not [int]::TryParse(([string]$keyword.priority), [ref]$priority) -or $priority -le 0) {
            Add-Hint $hints $rowNumber $sceneCode $level "warning" "keyword" "$label priority should be a positive integer." $text
        }
    }

    $duplicateSurfaces = @($surfaceTexts | Group-Object | Where-Object { $_.Count -gt 1 })
    foreach ($duplicate in $duplicateSurfaces) {
        Add-Hint $hints $rowNumber $sceneCode $level "warning" "keyword" "Duplicate keyword surfaceText in the same sentence: $($duplicate.Name)." $text
    }
}

$duplicateTexts = @($items | Group-Object text | Where-Object { $_.Count -gt 1 })
foreach ($duplicate in $duplicateTexts) {
    $rowNumbers = @()
    for ($index = 0; $index -lt $items.Count; $index++) {
        if ([string]$items[$index].text -eq [string]$duplicate.Name) {
            $rowNumbers += ($index + 1)
        }
    }

    foreach ($rowNumber in $rowNumbers) {
        $item = $items[$rowNumber - 1]
        Add-Hint $hints $rowNumber ([string]$item.sceneCode) ([string]$item.level) "issue" "duplicate" "Duplicate sentence text also appears in rows: $($rowNumbers -join ', ')." ([string]$item.text)
    }
}

$hintRows = @($hints.ToArray())
$issueRows = @($hintRows | Where-Object { $_.Severity -eq "issue" })
$warningRows = @($hintRows | Where-Object { $_.Severity -eq "warning" })
$affectedRows = @($hintRows | ForEach-Object { $_.RowNumber } | Sort-Object -Unique)

$severitySummary = [ordered]@{}
foreach ($group in ($hintRows | Group-Object Severity)) {
    $severitySummary[$group.Name] = $group.Count
}

$areaSummary = [ordered]@{}
foreach ($group in ($hintRows | Group-Object Area)) {
    $areaSummary[$group.Name] = $group.Count
}

$summaryLines = @(
    "| Metric | Value |",
    "| --- | ---: |",
    "| Total rows | $($items.Count) |",
    "| Rows with hints | $($affectedRows.Count) |",
    "| Issue hints | $($issueRows.Count) |",
    "| Warning hints | $($warningRows.Count) |"
)

$hintLines = if ($hintRows.Count -eq 0) {
    @("- No automated precheck hints. Human review is still required before marking content as pass.")
}
else {
    @(
        "| Row | Severity | Area | Message | Sentence |",
        "| ---: | --- | --- | --- | --- |"
    ) + @($hintRows | Sort-Object RowNumber, Severity, Area | ForEach-Object {
        "| $($_.RowNumber) | $(ConvertTo-MarkdownText $_.Severity) | $(ConvertTo-MarkdownText $_.Area) | $(ConvertTo-MarkdownText $_.Message) | $(ConvertTo-MarkdownText $_.Text) |"
    })
}

$areaLines = if ($areaSummary.Count -eq 0) {
    @("- No area hints.")
}
else {
    @(
        "| Area | Hints |",
        "| --- | ---: |"
    ) + @($areaSummary.GetEnumerator() | ForEach-Object {
        "| $(ConvertTo-MarkdownText $_.Key) | $($_.Value) |"
    })
}

$generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$lines = @(
    "# Content Precheck Report",
    "",
    "Generated at: $generatedAt",
    "",
    "## Decision",
    "",
    "- Automated precheck pass: $($issueRows.Count -eq 0)",
    "- Human review required: True",
    ('- Content path: `' + $ContentPath + '`'),
    ('- CSV output: `' + $CsvOutputPath + '`'),
    "",
    "## Summary",
    ""
) + $summaryLines + @(
    "",
    "## Area Summary",
    ""
) + $areaLines + @(
    "",
    "## Hints",
    ""
) + $hintLines + @(
    "",
    "## Reviewer Note",
    "",
    '- This report only gives automated hints. Do not mark a row as `pass` until sentence text, translation, keywords, and audio have actually been reviewed.',
    '- Treat `issue` hints as rows to inspect first. `warning` hints may still be acceptable after human review.'
)

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory | Out-Null
}

$csvDirectory = Split-Path -Parent $CsvOutputPath
if (-not (Test-Path -LiteralPath $csvDirectory)) {
    New-Item -ItemType Directory -Path $csvDirectory | Out-Null
}

Set-Content -LiteralPath $OutputPath -Value ($lines -join "`r`n") -Encoding UTF8

if ($hintRows.Count -gt 0) {
    $hintRows | Sort-Object RowNumber, Severity, Area | Export-Csv -LiteralPath $CsvOutputPath -NoTypeInformation -Encoding UTF8
}
else {
    Set-Content -LiteralPath $CsvOutputPath -Value '"RowNumber","SceneCode","Level","Severity","Area","Message","Text"' -Encoding UTF8
}

[pscustomobject]@{
    outputPath = $OutputPath
    csvOutputPath = $CsvOutputPath
    contentPath = $ContentPath
    totalRows = $items.Count
    hintRows = $hintRows.Count
    issueHints = $issueRows.Count
    warningHints = $warningRows.Count
    affectedRows = $affectedRows.Count
    automatedPrecheckPass = $issueRows.Count -eq 0
    humanReviewRequired = $true
    severitySummary = $severitySummary
    areaSummary = $areaSummary
} | ConvertTo-Json -Depth 8
