param(
    [switch]$SkipInfrastructure,
    [switch]$SkipServerStart,
    [switch]$SkipContentImport,
    [switch]$SkipAudio,
    [switch]$SkipReadiness,
    [switch]$IncludeSmoke,
    [switch]$Open
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
Add-Type -AssemblyName System.Net.Http

$RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$LogDirectory = Join-Path $RepoRoot ".local\logs"
$RunbookPath = Join-Path $RepoRoot "acceptance\local-beta-run.md"
$ApiUrl = "http://localhost:5180"
$WebUrl = "http://localhost:3000"

function Ensure-Directory([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function ConvertTo-FileUri([string]$path) {
    return ([System.Uri][System.IO.Path]::GetFullPath($path)).AbsoluteUri
}

function Invoke-JsonScript {
    param(
        [string]$ScriptName,
        [hashtable]$Parameters = @{}
    )

    $scriptPath = Join-Path $PSScriptRoot $ScriptName
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Script not found: $scriptPath"
    }

    $output = & $scriptPath @Parameters 6>$null
    $text = $output | Out-String
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "Script returned empty output: $ScriptName"
    }

    return $text | ConvertFrom-Json
}

function Invoke-NativeCommand {
    param(
        [string]$FilePath,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory = $RepoRoot
    )

    Push-Location $WorkingDirectory
    try {
        $output = & $FilePath @Arguments 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed ($FilePath $($Arguments -join ' ')): $output"
        }

        return $output.Trim()
    }
    finally {
        Pop-Location
    }
}

function Test-Url([string]$Url) {
    $client = [System.Net.Http.HttpClient]::new()
    try {
        $client.Timeout = [TimeSpan]::FromSeconds(5)
        $response = $client.GetAsync($Url).GetAwaiter().GetResult()
        return [pscustomobject]@{
            reachable = [bool]$response.IsSuccessStatusCode
            statusCode = [int]$response.StatusCode
            error = $null
        }
    }
    catch {
        return [pscustomobject]@{
            reachable = $false
            statusCode = $null
            error = $_.Exception.Message
        }
    }
    finally {
        $client.Dispose()
    }
}

function Wait-Url([string]$Url, [int]$TimeoutSeconds = 60) {
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $last = $null
    while ((Get-Date) -lt $deadline) {
        $last = Test-Url $Url
        if ($last.reachable) {
            return $last
        }

        Start-Sleep -Seconds 2
    }

    if ($null -eq $last) {
        $last = Test-Url $Url
    }

    return $last
}

function Get-CommandPath([string[]]$Names) {
    foreach ($name in $Names) {
        $command = Get-Command $name -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            return $command.Source
        }
    }

    throw "Required command not found: $($Names -join ' or ')"
}

function Start-HiddenProcess {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [string]$WorkingDirectory,
        [string]$LogName
    )

    Ensure-Directory $LogDirectory
    $stdoutPath = Join-Path $LogDirectory "$LogName.out.log"
    $stderrPath = Join-Path $LogDirectory "$LogName.err.log"

    $process = Start-Process `
        -FilePath $FilePath `
        -ArgumentList $Arguments `
        -WorkingDirectory $WorkingDirectory `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -PassThru

    return [pscustomobject]@{
        started = $true
        processId = $process.Id
        stdoutPath = $stdoutPath
        stderrPath = $stderrPath
    }
}

function Ensure-Api {
    $healthUrl = "$ApiUrl/health"
    $initial = Test-Url $healthUrl
    if ($initial.reachable) {
        return [pscustomobject]@{
            url = $ApiUrl
            healthUrl = $healthUrl
            started = $false
            reachable = $true
            statusCode = $initial.statusCode
            process = $null
            error = $null
        }
    }

    if ($SkipServerStart) {
        return [pscustomobject]@{
            url = $ApiUrl
            healthUrl = $healthUrl
            started = $false
            reachable = $false
            statusCode = $null
            process = $null
            error = $initial.error
        }
    }

    $dotnet = Get-CommandPath @("dotnet")
    $process = Start-HiddenProcess `
        -FilePath $dotnet `
        -Arguments @("run", "--project", "apps/api", "--launch-profile", "http") `
        -WorkingDirectory $RepoRoot `
        -LogName "api"

    $ready = Wait-Url $healthUrl 90
    return [pscustomobject]@{
        url = $ApiUrl
        healthUrl = $healthUrl
        started = $true
        reachable = [bool]$ready.reachable
        statusCode = $ready.statusCode
        process = $process
        error = $ready.error
    }
}

function Ensure-Web {
    $initial = Test-Url $WebUrl
    if ($initial.reachable) {
        return [pscustomobject]@{
            url = $WebUrl
            started = $false
            reachable = $true
            statusCode = $initial.statusCode
            process = $null
            error = $null
        }
    }

    if ($SkipServerStart) {
        return [pscustomobject]@{
            url = $WebUrl
            started = $false
            reachable = $false
            statusCode = $null
            process = $null
            error = $initial.error
        }
    }

    $npm = Get-CommandPath @("npm.cmd", "npm")
    $process = Start-HiddenProcess `
        -FilePath $npm `
        -Arguments @("run", "dev") `
        -WorkingDirectory (Join-Path $RepoRoot "apps\web") `
        -LogName "web"

    $ready = Wait-Url $WebUrl 90
    return [pscustomobject]@{
        url = $WebUrl
        started = $true
        reachable = [bool]$ready.reachable
        statusCode = $ready.statusCode
        process = $process
        error = $ready.error
    }
}

function New-Skipped([string]$Reason) {
    return [pscustomobject]@{
        skipped = $true
        reason = $Reason
    }
}

function Write-Runbook($summary) {
    $path = [System.IO.Path]::GetFullPath($RunbookPath)
    Ensure-Directory (Split-Path -Parent $path)

    $generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $lines = @(
        "# Local Beta Run",
        "",
        "Generated at: $generatedAt",
        "",
        "## Services",
        "",
        "- Web: [$WebUrl]($WebUrl)",
        "- API health: [$ApiUrl/health]($ApiUrl/health)",
        "- API ready: [$ApiUrl/health/ready]($ApiUrl/health/ready)",
        "- Admin: [$WebUrl/admin]($WebUrl/admin)",
        "",
        "## Test Accounts",
        "",
        '- Learner: `learner@example.com / Pass123$`',
        '- Admin: `admin@example.com / Admin123$`',
        "",
        "## Acceptance Files",
        "",
        "- Dashboard: [open]($(ConvertTo-FileUri (Join-Path $RepoRoot 'acceptance\mvp-acceptance-dashboard.html')))",
        "- Task list: [open]($(ConvertTo-FileUri (Join-Path $RepoRoot 'acceptance\mvp-acceptance-tasks.md')))",
        "- Content precheck: [open]($(ConvertTo-FileUri (Join-Path $RepoRoot 'acceptance\content-precheck-report.md')))",
        "- Content review session: [open]($(ConvertTo-FileUri (Join-Path $RepoRoot 'acceptance\content-review-session.md')))",
        "- Beta feedback session: [open]($(ConvertTo-FileUri (Join-Path $RepoRoot 'acceptance\beta-feedback-session.md')))",
        "- Fix plan: [open]($(ConvertTo-FileUri (Join-Path $RepoRoot 'acceptance\mvp-fix-plan.md')))",
        "- Release gate: [open]($(ConvertTo-FileUri (Join-Path $RepoRoot 'acceptance\first-version-release-gate.md')))",
        "- First version handoff: [open]($(ConvertTo-FileUri (Join-Path $RepoRoot 'acceptance\first-version-handoff.md')))",
        "- Handoff validation: [open]($(ConvertTo-FileUri (Join-Path $RepoRoot 'acceptance\first-version-handoff-validation.md')))",
        "- First version progress: [open]($(ConvertTo-FileUri (Join-Path $RepoRoot 'acceptance\first-version-progress.md')))",
        "- Local beta readiness: [open]($(ConvertTo-FileUri (Join-Path $RepoRoot 'acceptance\local-beta-readiness.md')))",
        "- First version status: [open]($(ConvertTo-FileUri (Join-Path $RepoRoot 'acceptance\first-version-status.md')))",
        "- Content review packets: [open]($(ConvertTo-FileUri (Join-Path $RepoRoot 'content\review-packets\index.md')))",
        "- Beta feedback packets: [open]($(ConvertTo-FileUri (Join-Path $RepoRoot 'feedback\beta-feedback-packets\index.md')))",
        "",
        "## Next Commands",
        "",
        '```powershell',
        '.\scripts\export-content-precheck-report.ps1',
        '.\scripts\start-content-review-batch.ps1',
        '.\scripts\check-content-review-batch.ps1',
        '.\scripts\start-beta-feedback-session.ps1',
        '.\scripts\check-beta-feedback-session.ps1',
        '.\scripts\import-content-review-packets.ps1 -ValidateOnly',
        '.\scripts\import-content-review-packets.ps1 -RefreshArtifacts',
        '.\scripts\import-beta-feedback-packets.ps1 -ValidateOnly',
        '.\scripts\import-beta-feedback-packets.ps1 -RefreshArtifacts',
        '.\scripts\export-first-version-handoff.ps1',
        '.\scripts\validate-first-version-handoff.ps1 -AssertValid',
        '.\scripts\export-first-version-progress.ps1',
        '.\scripts\check-local-beta-readiness.ps1',
        '.\scripts\check-mvp-readiness.ps1 -IncludeBuild',
        '```'
    )

    Set-Content -LiteralPath $path -Value ($lines -join "`r`n") -Encoding UTF8
    return $path
}

$tooling = [ordered]@{}
$tooling.dotnet = Get-CommandPath @("dotnet")
$tooling.npm = Get-CommandPath @("npm.cmd", "npm")
$tooling.docker = if ($SkipInfrastructure) { "" } else { Get-CommandPath @("docker") }

$infrastructure = if ($SkipInfrastructure) {
    New-Skipped "SkipInfrastructure was set."
}
else {
    $dockerOutput = Invoke-NativeCommand `
        -FilePath $tooling.docker `
        -Arguments @("compose", "-f", "infra/docker-compose.yml", "up", "-d") `
        -WorkingDirectory $RepoRoot
    [pscustomobject]@{
        skipped = $false
        command = "docker compose -f infra/docker-compose.yml up -d"
        output = $dockerOutput
    }
}

if (-not $SkipInfrastructure) {
    Invoke-NativeCommand -FilePath $tooling.dotnet -Arguments @("tool", "restore") -WorkingDirectory $RepoRoot | Out-Null
    Invoke-NativeCommand `
        -FilePath $tooling.dotnet `
        -Arguments @("tool", "run", "dotnet-ef", "database", "update", "--project", "apps/api", "--startup-project", "apps/api") `
        -WorkingDirectory $RepoRoot | Out-Null
}

$api = Ensure-Api
$web = Ensure-Web

$contentValidation = Invoke-JsonScript -ScriptName "validate-mvp-content.ps1"
$contentAudit = Invoke-JsonScript -ScriptName "audit-mvp-content-quality.ps1"

$contentImport = if ($SkipContentImport) {
    New-Skipped "SkipContentImport was set."
}
else {
    Invoke-JsonScript -ScriptName "import-mvp-content.ps1"
}

$audio = if ($SkipAudio) {
    New-Skipped "SkipAudio was set."
}
else {
    Invoke-JsonScript -ScriptName "generate-missing-audio.ps1"
}

$acceptance = Invoke-JsonScript -ScriptName "prepare-mvp-acceptance.ps1" -Parameters @{ SkipReadiness = $true }
$releaseGate = Invoke-JsonScript -ScriptName "export-first-version-release-gate.ps1"
$statusReport = Invoke-JsonScript -ScriptName "export-first-version-status.ps1" -Parameters @{ SkipReadiness = $true }
$handoff = Invoke-JsonScript -ScriptName "export-first-version-handoff.ps1"
$handoffValidation = Invoke-JsonScript -ScriptName "validate-first-version-handoff.ps1"
$progress = Invoke-JsonScript -ScriptName "export-first-version-progress.ps1"
$localBetaReadiness = Invoke-JsonScript -ScriptName "check-local-beta-readiness.ps1"

$readiness = if ($SkipReadiness) {
    New-Skipped "SkipReadiness was set."
}
else {
    Invoke-JsonScript -ScriptName "check-mvp-readiness.ps1" -Parameters @{ SkipSmoke = $true; SkipUi = $true }
}

$smoke = if ($IncludeSmoke) {
    $apiSmoke = Invoke-JsonScript -ScriptName "smoke-test.ps1" -Parameters @{ IncludeTts = $true }
    $node = Get-CommandPath @("node.exe", "node")
    $uiOutput = Invoke-NativeCommand -FilePath $node -Arguments @(".\scripts\ui-smoke-test.mjs") -WorkingDirectory $RepoRoot
    [pscustomobject]@{
        skipped = $false
        api = $apiSmoke
        ui = $uiOutput
    }
}
else {
    New-Skipped "IncludeSmoke was not set."
}

$summary = [pscustomobject]@{
    tooling = [pscustomobject]$tooling
    infrastructure = $infrastructure
    api = $api
    web = $web
    contentValidation = $contentValidation
    contentAudit = $contentAudit
    contentImport = $contentImport
    audio = $audio
    acceptance = [pscustomobject]@{
        dashboard = $acceptance.dashboard.outputPath
        tasks = $acceptance.tasks.outputPath
        fixPlan = $acceptance.fixPlan.outputPath
        releaseGate = $releaseGate.outputPath
        handoff = $handoff.outputPath
        handoffValidation = $handoffValidation.outputPath
        progress = $progress.outputPath
        localBetaReadiness = $localBetaReadiness.outputPath
        statusReport = $statusReport.outputPath
        contentPackets = $acceptance.contentReview.packets.indexPath
        betaPackets = $acceptance.betaFeedback.packets.indexPath
        contentReviewSession = $acceptance.contentReview.session.outputPath
        betaFeedbackSession = $acceptance.betaFeedback.session.outputPath
    }
    readiness = if ($SkipReadiness) {
        $readiness
    }
    else {
        [pscustomobject]@{
            automatedReady = [bool]$readiness.automatedReady
            productReviewReady = [bool]$readiness.productReviewReady
            firstVersionReady = [bool]$readiness.firstVersionReady
        }
    }
    smoke = $smoke
}

$runbook = Write-Runbook $summary

if ($Open) {
    Start-Process -FilePath $runbook
    Start-Process -FilePath $acceptance.dashboard.outputPath
    Start-Process -FilePath $acceptance.tasks.outputPath
}

$summary | Add-Member -NotePropertyName runbookPath -NotePropertyValue $runbook
$summary | ConvertTo-Json -Depth 14
