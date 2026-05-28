param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("content", "beta")]
    [string]$Kind,

    [string]$SourcePath = "",
    [string]$DownloadsDirectory = "",
    [switch]$ValidateOnly,
    [switch]$NoBackup,
    [switch]$RefreshArtifacts
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

function Get-FullPath([string]$path) {
    return [System.IO.Path]::GetFullPath($path)
}

function Get-Config([string]$kind) {
    if ($kind -eq "content") {
        return [pscustomobject]@{
            expectedFileName = "mvp-content-review.csv"
            destinationPath = Get-FullPath (Join-Path $PSScriptRoot "..\content\mvp-content-review.csv")
            summaryScript = "summarize-content-review.ps1"
            summaryPathParameter = "ReviewPath"
            htmlScript = "export-content-review-html.ps1"
            requiredColumns = @(
                "RowNumber",
                "SceneCode",
                "SceneName",
                "Level",
                "Text",
                "Translation",
                "KeywordCount",
                "Keywords",
                "ReviewStatus",
                "SentenceNotes",
                "TranslationNotes",
                "KeywordNotes",
                "AudioNotes",
                "FinalNotes"
            )
            keyColumn = "RowNumber"
        }
    }

    return [pscustomobject]@{
        expectedFileName = "internal-beta-feedback.csv"
        destinationPath = Get-FullPath (Join-Path $PSScriptRoot "..\feedback\internal-beta-feedback.csv")
        summaryScript = "summarize-beta-feedback.ps1"
        summaryPathParameter = "FeedbackPath"
        htmlScript = "export-beta-feedback-html.ps1"
        requiredColumns = @(
            "UserId",
            "UserType",
            "EnglishLevel",
            "CompletedTest",
            "IndependentCompletion",
            "StuckStep",
            "UnderstandsDifficulty",
            "WillingNext",
            "PerceivedUseful",
            "AudioIssue",
            "PageIssue",
            "ContentIssue",
            "Priority",
            "Notes"
        )
        keyColumn = "UserId"
    }
}

function Resolve-SourcePath($config) {
    if (-not [string]::IsNullOrWhiteSpace($SourcePath)) {
        $path = Get-FullPath $SourcePath
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Source file not found: $path"
        }

        return $path
    }

    $downloads = if ([string]::IsNullOrWhiteSpace($DownloadsDirectory)) {
        Join-Path $env:USERPROFILE "Downloads"
    }
    else {
        Get-FullPath $DownloadsDirectory
    }

    if (-not (Test-Path -LiteralPath $downloads)) {
        throw "Downloads directory not found: $downloads"
    }

    $candidates = @(
        Get-ChildItem -LiteralPath $downloads -File |
            Where-Object { $_.Name -eq $config.expectedFileName } |
            Sort-Object LastWriteTime -Descending
    )

    if ($candidates.Count -eq 0) {
        throw "No exported $($config.expectedFileName) found under $downloads. Use -SourcePath to import another file."
    }

    return $candidates[0].FullName
}

function Validate-Rows($config, [string]$source) {
    $rows = @(Import-Csv -LiteralPath $source -Encoding UTF8)
    if ($rows.Count -eq 0) {
        throw "CSV has no data rows: $source"
    }

    $columns = @($rows[0].PSObject.Properties.Name)
    $missingColumns = @($config.requiredColumns | Where-Object { $columns -notcontains $_ })
    if ($missingColumns.Count -gt 0) {
        throw "CSV is missing required columns: $($missingColumns -join ', ')"
    }

    $blankKeys = @($rows | Where-Object {
        [string]::IsNullOrWhiteSpace([string]$_.($config.keyColumn))
    })
    if ($blankKeys.Count -gt 0) {
        throw "CSV contains $($blankKeys.Count) row(s) with blank $($config.keyColumn)."
    }

    if ($config.keyColumn -eq "RowNumber") {
        $invalidRowNumbers = @($rows | Where-Object {
            $rowNumber = 0
            -not [int]::TryParse([string]$_.RowNumber, [ref]$rowNumber)
        })

        if ($invalidRowNumbers.Count -gt 0) {
            throw "CSV contains $($invalidRowNumbers.Count) invalid RowNumber value(s)."
        }
    }

    $duplicateKeys = @(
        $rows |
            Group-Object $config.keyColumn |
            Where-Object { $_.Count -gt 1 }
    )
    if ($duplicateKeys.Count -gt 0) {
        throw "CSV contains duplicate $($config.keyColumn) value(s): $($duplicateKeys.Name -join ', ')"
    }

    if ($config.keyColumn -eq "RowNumber") {
        Validate-ContentReviewRows $rows
    }
    else {
        Validate-BetaFeedbackRows $rows
    }

    return $rows
}

function Normalize-Value($value) {
    return ([string]$value).Trim().ToLowerInvariant()
}

function Assert-AllowedValues {
    param(
        [array]$Rows,
        [string]$KeyColumn,
        [string]$Column,
        [string[]]$AllowedValues
    )

    $allowedSet = @{}
    foreach ($value in $AllowedValues) {
        $allowedSet[(Normalize-Value $value)] = $true
    }

    $invalidRows = @($Rows | Where-Object {
        $normalized = Normalize-Value $_.$Column
        -not [string]::IsNullOrWhiteSpace($normalized) -and -not $allowedSet.ContainsKey($normalized)
    })

    if ($invalidRows.Count -eq 0) {
        return
    }

    $examples = @(
        $invalidRows |
            Select-Object -First 10 |
            ForEach-Object { "$($_.$KeyColumn):$($_.$Column)" }
    )
    $allowedText = (@("blank") + $AllowedValues) -join ", "
    throw "CSV contains invalid $Column value(s). Allowed values: $allowedText. Examples: $($examples -join '; ')"
}

function Validate-ContentReviewRows([array]$rows) {
    Assert-AllowedValues `
        -Rows $rows `
        -KeyColumn "RowNumber" `
        -Column "ReviewStatus" `
        -AllowedValues @(
            "pass",
            "fix_sentence",
            "fix_translation",
            "fix_keyword",
            "fix_audio",
            "remove"
        )
}

function Validate-BetaFeedbackRows([array]$rows) {
    $yesCn = [string][char]0x662f
    $noCn = [string][char]0x5426
    $completedCn = -join @([char]0x5b8c, [char]0x6210)
    $usefulCn = -join @([char]0x6709, [char]0x7528)
    $partialCn = -join @([char]0x90e8, [char]0x5206)
    $averageCn = -join @([char]0x4e00, [char]0x822c)

    $yesNoValues = @("yes", "y", "true", "1", "no", "n", "false", "0", $yesCn, $noCn, $completedCn, $usefulCn)
    $partialValues = @("yes", "y", "true", "1", "no", "n", "false", "0", "partial", "partly", "average", $yesCn, $noCn, $completedCn, $usefulCn, $partialCn, $averageCn)

    Assert-AllowedValues -Rows $rows -KeyColumn "UserId" -Column "CompletedTest" -AllowedValues $yesNoValues
    Assert-AllowedValues -Rows $rows -KeyColumn "UserId" -Column "IndependentCompletion" -AllowedValues $yesNoValues
    Assert-AllowedValues -Rows $rows -KeyColumn "UserId" -Column "UnderstandsDifficulty" -AllowedValues $partialValues
    Assert-AllowedValues -Rows $rows -KeyColumn "UserId" -Column "WillingNext" -AllowedValues @("yes", "y", "true", "1", "no", "n", "false", "0", "average", $yesCn, $noCn, $averageCn)
    Assert-AllowedValues -Rows $rows -KeyColumn "UserId" -Column "PerceivedUseful" -AllowedValues $partialValues
    Assert-AllowedValues -Rows $rows -KeyColumn "UserId" -Column "Priority" -AllowedValues @("P0", "P1", "P2")
}

function Backup-Destination([string]$destination) {
    if ($NoBackup -or -not (Test-Path -LiteralPath $destination)) {
        return $null
    }

    $backupRoot = Join-Path $env:TEMP "EnglishStudyStudio-acceptance-backups"
    if (-not (Test-Path -LiteralPath $backupRoot)) {
        New-Item -ItemType Directory -Path $backupRoot | Out-Null
    }

    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($destination)
    $extension = [System.IO.Path]::GetExtension($destination)
    $timestamp = Get-Date -Format "yyyyMMddHHmmss"
    $backupPath = Join-Path $backupRoot "$fileName.$timestamp$extension"
    Copy-Item -LiteralPath $destination -Destination $backupPath -Force
    return $backupPath
}

function Invoke-JsonScript {
    param(
        [string]$ScriptName,
        [hashtable]$Parameters = @{}
    )

    $scriptPath = Join-Path $PSScriptRoot $scriptName
    $output = & $scriptPath @Parameters
    return ($output | Out-String) | ConvertFrom-Json
}

$config = Get-Config $Kind
$source = Resolve-SourcePath $config
$source = Get-FullPath $source
$destination = $config.destinationPath
$rows = Validate-Rows $config $source

if ($ValidateOnly) {
    $summaryParams = @{}
    $summaryParams[$config.summaryPathParameter] = $source
    $summary = Invoke-JsonScript -ScriptName $config.summaryScript -Parameters $summaryParams

    [pscustomobject]@{
        kind = $Kind
        sourcePath = $source
        destinationPath = $destination
        validationOnly = $true
        valid = $true
        imported = $false
        rowCount = $rows.Count
        backupPath = $null
        summary = $summary
        refreshedArtifacts = @()
    } | ConvertTo-Json -Depth 12

    exit 0
}

$destinationDirectory = Split-Path -Parent $destination
if (-not (Test-Path -LiteralPath $destinationDirectory)) {
    New-Item -ItemType Directory -Path $destinationDirectory | Out-Null
}

$sourceInfo = Get-Item -LiteralPath $source
$destinationExists = Test-Path -LiteralPath $destination
$sameFile = $destinationExists -and
    ([System.IO.Path]::GetFullPath($sourceInfo.FullName) -eq [System.IO.Path]::GetFullPath($destination))

$backupPath = if ($sameFile) {
    $null
}
else {
    Backup-Destination $destination
}

if (-not $sameFile) {
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

$summary = Invoke-JsonScript -ScriptName $config.summaryScript
$refreshed = @()
if ($RefreshArtifacts) {
    $htmlSummary = Invoke-JsonScript -ScriptName $config.htmlScript
    $dashboardSummary = Invoke-JsonScript -ScriptName "export-mvp-acceptance-dashboard.ps1"
    $tasksSummary = Invoke-JsonScript -ScriptName "export-mvp-acceptance-tasks.ps1"
    $refreshed += $htmlSummary.outputPath
    $refreshed += $dashboardSummary.outputPath
    $refreshed += $tasksSummary.outputPath
}

[pscustomobject]@{
    kind = $Kind
    sourcePath = $source
    destinationPath = $destination
    imported = -not $sameFile
    rowCount = $rows.Count
    backupPath = $backupPath
    summary = $summary
    refreshedArtifacts = $refreshed
} | ConvertTo-Json -Depth 12
