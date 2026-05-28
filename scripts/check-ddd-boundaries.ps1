param(
    [switch]$JsonOnly
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$apiRoot = Join-Path $repoRoot "apps\api"

if (-not (Test-Path -LiteralPath $apiRoot)) {
    throw "API project directory not found: $apiRoot"
}

$violations = New-Object System.Collections.Generic.List[object]

function Get-RelativePath([string]$path) {
    $fullPath = [System.IO.Path]::GetFullPath($path)
    return $fullPath.Substring($repoRoot.Length + 1).Replace("\", "/")
}

function Add-Violation(
    [string]$rule,
    [string]$file,
    [int]$lineNumber,
    [string]$line,
    [string]$reason
) {
    $violations.Add([pscustomobject]@{
        rule = $rule
        file = $file
        line = $lineNumber
        text = $line.Trim()
        reason = $reason
    })
}

function Test-BoundaryRule(
    [string]$name,
    [string]$directory,
    [object[]]$forbiddenUsings,
    [string]$excludePathRegex = ""
) {
    $targetDirectory = Join-Path $apiRoot $directory
    if (-not (Test-Path -LiteralPath $targetDirectory)) {
        throw "DDD boundary directory not found: $targetDirectory"
    }

    $files = Get-ChildItem -LiteralPath $targetDirectory -Recurse -Filter "*.cs" -File
    foreach ($file in $files) {
        $relativePath = Get-RelativePath $file.FullName
        if (-not [string]::IsNullOrWhiteSpace($excludePathRegex) -and $relativePath -match $excludePathRegex) {
            continue
        }

        $lines = Get-Content -LiteralPath $file.FullName -Encoding UTF8
        for ($index = 0; $index -lt $lines.Count; $index++) {
            foreach ($forbidden in $forbiddenUsings) {
                if ($lines[$index] -match $forbidden.Pattern) {
                    Add-Violation `
                        -rule $name `
                        -file $relativePath `
                        -lineNumber ($index + 1) `
                        -line $lines[$index] `
                        -reason $forbidden.Reason
                }
            }
        }
    }
}

$rules = @(
    [pscustomobject]@{
        Name = "domain-no-application-infrastructure-or-http"
        Directory = "Domain"
        ExcludePathRegex = ""
        ForbiddenUsings = @(
            [pscustomobject]@{
                Pattern = '^\s*using\s+Api\.(Application|Infrastructure|Controllers)\b'
                Reason = "Domain must not depend on upper layers."
            },
            [pscustomobject]@{
                Pattern = '^\s*using\s+Microsoft\.EntityFrameworkCore\b'
                Reason = "Domain must not depend on EF Core."
            },
            [pscustomobject]@{
                Pattern = '^\s*using\s+Microsoft\.AspNetCore\.Mvc\b'
                Reason = "Domain must not depend on ASP.NET Core MVC."
            },
            [pscustomobject]@{
                Pattern = '^\s*using\s+Microsoft\.Extensions\b'
                Reason = "Domain must not depend on hosting or DI infrastructure."
            },
            [pscustomobject]@{
                Pattern = '^\s*using\s+Minio\b'
                Reason = "Domain must not depend on MinIO."
            },
            [pscustomobject]@{
                Pattern = '^\s*using\s+System\.Net\.Http\b'
                Reason = "Domain must not depend on HTTP clients."
            }
        )
    },
    [pscustomobject]@{
        Name = "domain-aspnetcore-identity-is-contained"
        Directory = "Domain"
        ExcludePathRegex = '^apps/api/Domain/Identity/'
        ForbiddenUsings = @(
            [pscustomobject]@{
                Pattern = '^\s*using\s+Microsoft\.AspNetCore\b'
                Reason = "Only Domain/Identity may use ASP.NET Core Identity in the MVP compromise."
            }
        )
    },
    [pscustomobject]@{
        Name = "application-no-infrastructure-or-http-entry"
        Directory = "Application"
        ExcludePathRegex = ""
        ForbiddenUsings = @(
            [pscustomobject]@{
                Pattern = '^\s*using\s+Api\.(Infrastructure|Controllers)\b'
                Reason = "Application must not depend on Infrastructure or Controllers."
            },
            [pscustomobject]@{
                Pattern = '^\s*using\s+Microsoft\.AspNetCore\.Mvc\b'
                Reason = "Application must not depend on HTTP controller concerns."
            },
            [pscustomobject]@{
                Pattern = '^\s*using\s+Minio\b'
                Reason = "Application must use storage abstractions instead of MinIO directly."
            }
        )
    },
    [pscustomobject]@{
        Name = "infrastructure-no-controller-dependency"
        Directory = "Infrastructure"
        ExcludePathRegex = ""
        ForbiddenUsings = @(
            [pscustomobject]@{
                Pattern = '^\s*using\s+Api\.Controllers\b'
                Reason = "Infrastructure must not depend on API controllers."
            }
        )
    },
    [pscustomobject]@{
        Name = "controllers-no-infrastructure-or-database"
        Directory = "Controllers"
        ExcludePathRegex = ""
        ForbiddenUsings = @(
            [pscustomobject]@{
                Pattern = '^\s*using\s+Api\.Infrastructure\b'
                Reason = "Controllers should call Application services instead of Infrastructure directly."
            },
            [pscustomobject]@{
                Pattern = '^\s*using\s+Microsoft\.EntityFrameworkCore\b'
                Reason = "Controllers should not run database queries directly."
            },
            [pscustomobject]@{
                Pattern = '^\s*using\s+Minio\b'
                Reason = "Controllers should use Application services instead of MinIO directly."
            }
        )
    }
)

foreach ($rule in $rules) {
    Test-BoundaryRule `
        -name $rule.Name `
        -directory $rule.Directory `
        -forbiddenUsings $rule.ForbiddenUsings `
        -excludePathRegex $rule.ExcludePathRegex
}

$summary = [pscustomobject]@{
    checkedAt = (Get-Date).ToString("o")
    apiRoot = $apiRoot
    passed = $violations.Count -eq 0
    violationCount = $violations.Count
    violations = $violations
    allowedCompromises = @(
        "Domain/Identity may use ASP.NET Core Identity in the MVP phase.",
        "Application may use EF Core query extensions through IAppDbContext until a domain grows enough to justify repositories."
    )
}

$summary | ConvertTo-Json -Depth 8

if ($violations.Count -gt 0) {
    if (-not $JsonOnly) {
        $violations | ForEach-Object {
            Write-Error "$($_.file):$($_.line) violates $($_.rule): $($_.reason)"
        }
    }

    throw "DDD boundary check failed with $($violations.Count) violation(s)."
}

if (-not $JsonOnly) {
    Write-Host "DDD boundary check passed."
}
