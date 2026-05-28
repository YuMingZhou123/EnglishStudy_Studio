param(
    [string]$PacketPath = "",
    [string]$PacketDirectory = "",
    [string]$ReviewPath = "",
    [switch]$ValidateOnly,
    [switch]$NoBackup,
    [switch]$RefreshArtifacts
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

if (-not [string]::IsNullOrWhiteSpace($PacketPath) -and -not [string]::IsNullOrWhiteSpace($PacketDirectory)) {
    throw "Use either -PacketPath or -PacketDirectory, not both."
}

if ([string]::IsNullOrWhiteSpace($ReviewPath)) {
    $ReviewPath = Join-Path $PSScriptRoot "..\content\mvp-content-review.csv"
}

if ([string]::IsNullOrWhiteSpace($PacketPath) -and [string]::IsNullOrWhiteSpace($PacketDirectory)) {
    $PacketDirectory = Join-Path $PSScriptRoot "..\content\review-packets"
}

$ReviewPath = [System.IO.Path]::GetFullPath($ReviewPath)
if (-not (Test-Path -LiteralPath $ReviewPath)) {
    throw "Review file not found: $ReviewPath. Run .\scripts\export-content-review-sheet.ps1 first."
}

$AllowedStatuses = @(
    "pass",
    "fix_sentence",
    "fix_translation",
    "fix_keyword",
    "fix_audio",
    "remove"
)

function Get-FullPath([string]$path) {
    return [System.IO.Path]::GetFullPath($path)
}

function Normalize-Status($value) {
    return ([string]$value).Trim().ToLowerInvariant()
}

function ConvertFrom-MarkdownText($value) {
    $text = ([string]$value).Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return ""
    }

    return $text.Replace("<br>", "`n").Replace("\|", "|").Replace("\\", "\")
}

function Split-MarkdownTableRow([string]$line) {
    $trimmed = $line.Trim()
    if ($trimmed.StartsWith("|")) {
        $trimmed = $trimmed.Substring(1)
    }

    if ($trimmed.EndsWith("|")) {
        $trimmed = $trimmed.Substring(0, $trimmed.Length - 1)
    }

    $cells = New-Object System.Collections.Generic.List[string]
    $builder = [System.Text.StringBuilder]::new()
    $backslash = [char]92
    $pipe = [char]124

    for ($index = 0; $index -lt $trimmed.Length; $index++) {
        $char = $trimmed[$index]

        if ($char -eq $backslash -and $index + 1 -lt $trimmed.Length) {
            $next = $trimmed[$index + 1]
            if ($next -eq $pipe -or $next -eq $backslash) {
                [void]$builder.Append($next)
                $index++
                continue
            }
        }

        if ($char -eq $pipe) {
            $cells.Add($builder.ToString().Trim())
            [void]$builder.Clear()
            continue
        }

        [void]$builder.Append($char)
    }

    $cells.Add($builder.ToString().Trim())
    return @($cells)
}

function Resolve-PacketFiles {
    if (-not [string]::IsNullOrWhiteSpace($PacketPath)) {
        $path = Get-FullPath $PacketPath
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Packet file not found: $path"
        }

        return @((Get-Item -LiteralPath $path))
    }

    $directory = Get-FullPath $PacketDirectory
    if (-not (Test-Path -LiteralPath $directory)) {
        throw "Packet directory not found: $directory. Run .\scripts\export-content-review-packets.ps1 first."
    }

    $files = @(
        Get-ChildItem -LiteralPath $directory -File -Filter "content-review-batch-*.md" |
            Sort-Object Name
    )

    if ($files.Count -eq 0) {
        throw "No review packet files found under $directory."
    }

    return $files
}

function Read-PacketRows($packetFile) {
    $lines = @(Get-Content -LiteralPath $packetFile.FullName -Encoding UTF8)
    $headerIndex = -1

    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index].Trim().StartsWith("| Row |")) {
            $headerIndex = $index
            break
        }
    }

    if ($headerIndex -lt 0 -or $headerIndex + 2 -ge $lines.Count) {
        throw "Review packet has no editable rows table: $($packetFile.FullName)"
    }

    $packetRows = New-Object System.Collections.Generic.List[object]
    for ($index = $headerIndex + 2; $index -lt $lines.Count; $index++) {
        $line = $lines[$index].Trim()
        if ([string]::IsNullOrWhiteSpace($line)) {
            break
        }

        if (-not $line.StartsWith("|")) {
            continue
        }

        $cells = @(Split-MarkdownTableRow $line)
        if ($cells.Count -lt 10) {
            throw "Review packet row has $($cells.Count) column(s), expected at least 10: $($packetFile.FullName) line $($index + 1)"
        }

        $rowNumber = 0
        if (-not [int]::TryParse($cells[0], [ref]$rowNumber)) {
            throw "Review packet has invalid row number '$($cells[0])': $($packetFile.FullName) line $($index + 1)"
        }

        $status = Normalize-Status $cells[5]
        $notesCell = if ($cells.Count -gt 10) {
            ($cells[9..($cells.Count - 1)] -join " | ")
        }
        else {
            $cells[9]
        }
        $notes = ConvertFrom-MarkdownText $notesCell

        $packetRows.Add([pscustomobject]@{
            rowNumber = $rowNumber
            status = $status
            notes = $notes
            packetPath = $packetFile.FullName
            lineNumber = $index + 1
        })
    }

    return $packetRows.ToArray()
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
    $backupPath = Join-Path $backupRoot "$fileName.packet-import.$timestamp$extension"
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

$packetFiles = @(Resolve-PacketFiles)
$reviewRows = @(Import-Csv -LiteralPath $ReviewPath -Encoding UTF8)
if ($reviewRows.Count -eq 0) {
    throw "Review CSV has no rows: $ReviewPath"
}

$reviewRowsByNumber = @{}
foreach ($row in $reviewRows) {
    $rowNumber = 0
    if (-not [int]::TryParse([string]$row.RowNumber, [ref]$rowNumber)) {
        throw "Review CSV contains invalid RowNumber value: $($row.RowNumber)"
    }

    if ($reviewRowsByNumber.ContainsKey($rowNumber)) {
        throw "Review CSV contains duplicate RowNumber value: $rowNumber"
    }

    $reviewRowsByNumber[$rowNumber] = $row
}

$parsedRows = New-Object System.Collections.Generic.List[object]
foreach ($packetFile in $packetFiles) {
    foreach ($packetRow in @(Read-PacketRows $packetFile)) {
        $parsedRows.Add($packetRow)
    }
}

$blankRows = @($parsedRows | Where-Object {
    [string]::IsNullOrWhiteSpace([string]$_.status) -and [string]::IsNullOrWhiteSpace([string]$_.notes)
})
$notesWithoutStatus = @($parsedRows | Where-Object {
    [string]::IsNullOrWhiteSpace([string]$_.status) -and -not [string]::IsNullOrWhiteSpace([string]$_.notes)
})
if ($notesWithoutStatus.Count -gt 0) {
    $examples = @($notesWithoutStatus | Select-Object -First 10 | ForEach-Object { "$($_.rowNumber):$($_.packetPath)" })
    throw "Review packet contains notes without status. Examples: $($examples -join '; ')"
}

$updates = @($parsedRows | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.status) })

$invalidStatusRows = @($updates | Where-Object { $AllowedStatuses -notcontains $_.status })
if ($invalidStatusRows.Count -gt 0) {
    $examples = @($invalidStatusRows | Select-Object -First 10 | ForEach-Object { "$($_.rowNumber):$($_.status)" })
    throw "Review packet contains invalid status value(s). Allowed values: $($AllowedStatuses -join ', '). Examples: $($examples -join '; ')"
}

$missingNoteRows = @($updates | Where-Object {
    $_.status -ne "pass" -and [string]::IsNullOrWhiteSpace([string]$_.notes)
})
if ($missingNoteRows.Count -gt 0) {
    $examples = @($missingNoteRows | Select-Object -First 10 | ForEach-Object { "$($_.rowNumber):$($_.status)" })
    throw "Review packet fix/remove rows must include notes. Examples: $($examples -join '; ')"
}

$unknownRows = @($updates | Where-Object { -not $reviewRowsByNumber.ContainsKey($_.rowNumber) })
if ($unknownRows.Count -gt 0) {
    $examples = @($unknownRows | Select-Object -First 10 | ForEach-Object { "$($_.rowNumber):$($_.packetPath)" })
    throw "Review packet references row(s) that do not exist in the review CSV. Examples: $($examples -join '; ')"
}

$duplicateUpdates = @(
    $updates |
        Group-Object rowNumber |
        Where-Object { $_.Count -gt 1 }
)
if ($duplicateUpdates.Count -gt 0) {
    throw "Review packet contains duplicate reviewed row(s): $($duplicateUpdates.Name -join ', ')"
}

$passRows = @($updates | Where-Object { $_.status -eq "pass" })
$fixRows = @($updates | Where-Object { $_.status -ne "pass" })

$backupPath = $null
$refreshed = @()
if (-not $ValidateOnly) {
    $backupPath = Backup-Destination $ReviewPath

    foreach ($update in $updates) {
        $target = $reviewRowsByNumber[$update.rowNumber]
        $target.ReviewStatus = $update.status
        $target.FinalNotes = $update.notes
    }

    $reviewRows | Export-Csv -LiteralPath $ReviewPath -NoTypeInformation -Encoding UTF8

    if ($RefreshArtifacts) {
        $htmlSummary = Invoke-JsonScript -ScriptName "export-content-review-html.ps1"
        $packetSummary = Invoke-JsonScript -ScriptName "export-content-review-packets.ps1"
        $dashboardSummary = Invoke-JsonScript -ScriptName "export-mvp-acceptance-dashboard.ps1"
        $tasksSummary = Invoke-JsonScript -ScriptName "export-mvp-acceptance-tasks.ps1"
        $fixPlanSummary = Invoke-JsonScript -ScriptName "export-mvp-fix-plan.ps1"
        $releaseGateSummary = Invoke-JsonScript -ScriptName "export-first-version-release-gate.ps1"
        $statusReportSummary = Invoke-JsonScript -ScriptName "export-first-version-status.ps1"

        $refreshed += $htmlSummary.outputPath
        $refreshed += $packetSummary.indexPath
        $refreshed += $dashboardSummary.outputPath
        $refreshed += $tasksSummary.outputPath
        $refreshed += $fixPlanSummary.outputPath
        $refreshed += $releaseGateSummary.outputPath
        $refreshed += $statusReportSummary.outputPath
    }
}

$summaryParams = @{ ReviewPath = $ReviewPath }
$summary = if ($ValidateOnly) {
    $null
}
else {
    Invoke-JsonScript -ScriptName "summarize-content-review.ps1" -Parameters $summaryParams
}

[pscustomobject]@{
    reviewPath = $ReviewPath
    packetCount = $packetFiles.Count
    parsedRows = $parsedRows.Count
    skippedBlankRows = $blankRows.Count
    reviewedRows = $updates.Count
    passRows = $passRows.Count
    fixRows = $fixRows.Count
    validateOnly = [bool]$ValidateOnly
    imported = -not $ValidateOnly
    backupPath = $backupPath
    refreshedArtifacts = $refreshed
    summary = $summary
} | ConvertTo-Json -Depth 12
