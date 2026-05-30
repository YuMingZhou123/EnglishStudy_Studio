param(
    [string]$PacketPath = "",
    [string]$PacketDirectory = "",
    [string]$FeedbackPath = "",
    [switch]$ValidateOnly,
    [switch]$NoBackup,
    [switch]$RefreshArtifacts
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

if (-not [string]::IsNullOrWhiteSpace($PacketPath) -and -not [string]::IsNullOrWhiteSpace($PacketDirectory)) {
    throw "Use either -PacketPath or -PacketDirectory, not both."
}

if ([string]::IsNullOrWhiteSpace($FeedbackPath)) {
    $FeedbackPath = Join-Path $PSScriptRoot "..\feedback\internal-beta-feedback.csv"
}

if ([string]::IsNullOrWhiteSpace($PacketPath) -and [string]::IsNullOrWhiteSpace($PacketDirectory)) {
    $PacketDirectory = Join-Path $PSScriptRoot "..\feedback\beta-feedback-packets"
}

$FeedbackPath = [System.IO.Path]::GetFullPath($FeedbackPath)
if (-not (Test-Path -LiteralPath $FeedbackPath)) {
    throw "Feedback file not found: $FeedbackPath. Run .\scripts\export-beta-feedback-template.ps1 first."
}

$Fields = @(
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

function Get-FullPath([string]$path) {
    return [System.IO.Path]::GetFullPath($path)
}

function Normalize-Value($value) {
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
        throw "Packet directory not found: $directory. Run .\scripts\export-beta-feedback-packets.ps1 first."
    }

    $files = @(
        Get-ChildItem -LiteralPath $directory -File -Filter "beta-feedback-*.md" |
            Sort-Object Name
    )

    if ($files.Count -eq 0) {
        throw "No beta feedback packet files found under $directory."
    }

    return $files
}

function Read-Packet($packetFile) {
    $lines = @(Get-Content -LiteralPath $packetFile.FullName -Encoding UTF8)
    $headerIndex = -1

    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index].Trim().StartsWith("| Field |")) {
            $headerIndex = $index
            break
        }
    }

    if ($headerIndex -lt 0 -or $headerIndex + 2 -ge $lines.Count) {
        throw "Beta feedback packet has no feedback table: $($packetFile.FullName)"
    }

    $values = [ordered]@{}
    foreach ($field in $Fields) {
        $values[$field] = ""
    }

    for ($index = $headerIndex + 2; $index -lt $lines.Count; $index++) {
        $line = $lines[$index].Trim()
        if ([string]::IsNullOrWhiteSpace($line)) {
            break
        }

        if (-not $line.StartsWith("|")) {
            continue
        }

        $cells = @(Split-MarkdownTableRow $line)
        if ($cells.Count -lt 2) {
            throw "Beta feedback packet row has $($cells.Count) column(s), expected at least 2: $($packetFile.FullName) line $($index + 1)"
        }

        $field = $cells[0].Trim()
        if ($Fields -notcontains $field) {
            throw "Beta feedback packet contains unknown field '$field': $($packetFile.FullName) line $($index + 1)"
        }

        $valueCell = if ($cells.Count -gt 2) {
            ($cells[1..($cells.Count - 1)] -join " | ")
        }
        else {
            $cells[1]
        }
        $values[$field] = ConvertFrom-MarkdownText $valueCell
    }

    if ([string]::IsNullOrWhiteSpace([string]$values["UserId"])) {
        throw "Beta feedback packet is missing UserId: $($packetFile.FullName)"
    }

    $filledFields = @(
        $Fields |
            Where-Object { $_ -ne "UserId" -and -not [string]::IsNullOrWhiteSpace([string]$values[$_]) }
    )

    return [pscustomobject]@{
        userId = [string]$values["UserId"]
        values = [pscustomobject]$values
        filled = $filledFields.Count -gt 0
        filledFieldCount = $filledFields.Count
        packetPath = $packetFile.FullName
    }
}

function Assert-AllowedValues {
    param(
        [array]$Packets,
        [string]$Column,
        [string[]]$AllowedValues
    )

    $allowedSet = @{}
    foreach ($value in $AllowedValues) {
        $allowedSet[(Normalize-Value $value)] = $true
    }

    $invalidPackets = @($Packets | Where-Object {
        $normalized = Normalize-Value $_.values.$Column
        -not [string]::IsNullOrWhiteSpace($normalized) -and -not $allowedSet.ContainsKey($normalized)
    })

    if ($invalidPackets.Count -eq 0) {
        return
    }

    $examples = @(
        $invalidPackets |
            Select-Object -First 10 |
            ForEach-Object { "$($_.userId):$($_.values.$Column)" }
    )
    $allowedText = (@("blank") + $AllowedValues) -join ", "
    throw "Beta feedback packet contains invalid $Column value(s). Allowed values: $allowedText. Examples: $($examples -join '; ')"
}

function Validate-Packets([array]$packets) {
    $yesCn = [string][char]0x662f
    $noCn = [string][char]0x5426
    $completedCn = -join @([char]0x5b8c, [char]0x6210)
    $usefulCn = -join @([char]0x6709, [char]0x7528)
    $partialCn = -join @([char]0x90e8, [char]0x5206)
    $averageCn = -join @([char]0x4e00, [char]0x822c)

    $yesNoValues = @("yes", "y", "true", "1", "no", "n", "false", "0", $yesCn, $noCn, $completedCn, $usefulCn)
    $partialValues = @("yes", "y", "true", "1", "no", "n", "false", "0", "partial", "partly", "average", $yesCn, $noCn, $completedCn, $usefulCn, $partialCn, $averageCn)

    Assert-AllowedValues -Packets $packets -Column "CompletedTest" -AllowedValues $yesNoValues
    Assert-AllowedValues -Packets $packets -Column "IndependentCompletion" -AllowedValues $yesNoValues
    Assert-AllowedValues -Packets $packets -Column "UnderstandsDifficulty" -AllowedValues $partialValues
    Assert-AllowedValues -Packets $packets -Column "WillingNext" -AllowedValues @("yes", "y", "true", "1", "no", "n", "false", "0", "average", $yesCn, $noCn, $averageCn)
    Assert-AllowedValues -Packets $packets -Column "PerceivedUseful" -AllowedValues $partialValues
    Assert-AllowedValues -Packets $packets -Column "Priority" -AllowedValues @("P0", "P1", "P2")
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
    $backupPath = Join-Path $backupRoot "$fileName.beta-packet-import.$timestamp$extension"
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
$packets = @($packetFiles | ForEach-Object { Read-Packet $_ })
Validate-Packets $packets

$filledPackets = @($packets | Where-Object { $_.filled })
$duplicatePackets = @(
    $filledPackets |
        Group-Object { (Normalize-Value $_.userId) } |
        Where-Object { $_.Count -gt 1 }
)
if ($duplicatePackets.Count -gt 0) {
    throw "Beta feedback packets contain duplicate filled user(s): $($duplicatePackets.Name -join ', ')"
}

$feedbackRows = @(Import-Csv -LiteralPath $FeedbackPath -Encoding UTF8)
if ($feedbackRows.Count -eq 0) {
    throw "Feedback CSV has no rows: $FeedbackPath"
}

$rowsByUserId = @{}
foreach ($row in $feedbackRows) {
    $userId = Normalize-Value $row.UserId
    if ([string]::IsNullOrWhiteSpace($userId)) {
        throw "Feedback CSV contains a row with blank UserId."
    }

    if ($rowsByUserId.ContainsKey($userId)) {
        throw "Feedback CSV contains duplicate UserId value: $($row.UserId)"
    }

    $rowsByUserId[$userId] = $row
}

$unknownFilledPackets = @($filledPackets | Where-Object { -not $rowsByUserId.ContainsKey((Normalize-Value $_.userId)) })
if ($unknownFilledPackets.Count -gt 0) {
    $examples = @(
        $unknownFilledPackets |
            Select-Object -First 10 |
            ForEach-Object { "$($_.userId):$($_.packetPath)" }
    )
    throw "Beta feedback packets can only update existing tester slots from the feedback CSV. Unknown filled tester(s): $($examples -join '; ')"
}

$backupPath = $null
$refreshed = @()
if (-not $ValidateOnly) {
    $backupPath = Backup-Destination $FeedbackPath

    $mergedRows = New-Object System.Collections.Generic.List[object]
    foreach ($row in $feedbackRows) {
        $mergedRows.Add($row)
    }

    foreach ($packet in $filledPackets) {
        $key = Normalize-Value $packet.userId
        $target = $rowsByUserId[$key]

        foreach ($field in $Fields) {
            $value = [string]$packet.values.$field
            if ($field -eq "UserId" -or [string]::IsNullOrWhiteSpace($value)) {
                continue
            }

            $target.$field = $value
        }
    }

    $mergedRows | Export-Csv -LiteralPath $FeedbackPath -NoTypeInformation -Encoding UTF8

    if ($RefreshArtifacts) {
        $htmlSummary = Invoke-JsonScript -ScriptName "export-beta-feedback-html.ps1"
        $packetSummary = Invoke-JsonScript -ScriptName "export-beta-feedback-packets.ps1"
        $audioReadinessSummary = Invoke-JsonScript -ScriptName "check-content-audio-readiness.ps1"
        $dashboardSummary = Invoke-JsonScript -ScriptName "export-mvp-acceptance-dashboard.ps1"
        $tasksSummary = Invoke-JsonScript -ScriptName "export-mvp-acceptance-tasks.ps1"
        $fixPlanSummary = Invoke-JsonScript -ScriptName "export-mvp-fix-plan.ps1"
        $releaseGateSummary = Invoke-JsonScript -ScriptName "export-first-version-release-gate.ps1"
        $statusReportSummary = Invoke-JsonScript -ScriptName "export-first-version-status.ps1"
        $humanPlanSummary = Invoke-JsonScript -ScriptName "export-first-version-human-plan.ps1"
        $handoffSummary = Invoke-JsonScript -ScriptName "export-first-version-handoff.ps1"
        $handoffValidationSummary = Invoke-JsonScript -ScriptName "validate-first-version-handoff.ps1"
        $progressSummary = Invoke-JsonScript -ScriptName "export-first-version-progress.ps1"
        $localBetaReadinessSummary = Invoke-JsonScript -ScriptName "check-local-beta-readiness.ps1"

        $refreshed += $htmlSummary.outputPath
        $refreshed += $packetSummary.indexPath
        $refreshed += $audioReadinessSummary.outputPath
        $refreshed += $dashboardSummary.outputPath
        $refreshed += $tasksSummary.outputPath
        $refreshed += $fixPlanSummary.outputPath
        $refreshed += $releaseGateSummary.outputPath
        $refreshed += $statusReportSummary.outputPath
        $refreshed += $humanPlanSummary.outputPath
        $refreshed += $handoffSummary.outputPath
        $refreshed += $handoffValidationSummary.outputPath
        $refreshed += $progressSummary.outputPath
        $refreshed += $localBetaReadinessSummary.outputPath
    }
}

$summary = if ($ValidateOnly) {
    $null
}
else {
    Invoke-JsonScript -ScriptName "summarize-beta-feedback.ps1" -Parameters @{ FeedbackPath = $FeedbackPath }
}

[pscustomobject]@{
    feedbackPath = $FeedbackPath
    packetCount = $packetFiles.Count
    filledPackets = $filledPackets.Count
    skippedBlankPackets = $packets.Count - $filledPackets.Count
    validateOnly = [bool]$ValidateOnly
    imported = -not $ValidateOnly
    appendedRows = 0
    backupPath = $backupPath
    refreshedArtifacts = $refreshed
    summary = $summary
} | ConvertTo-Json -Depth 12
