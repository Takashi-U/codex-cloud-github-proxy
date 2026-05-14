<#
.SYNOPSIS
  Pre-publication safety check for codex-github-proxy on Windows.

.DESCRIPTION
  This script checks that obvious secret files are not present and, when the
  current directory is a Git repository, that no secret-like files are tracked.

  It does not prove that the repository is safe. It is a final guardrail before
  publishing.

.USAGE
  PowerShell 7:
    pwsh -ExecutionPolicy Bypass -File .\scripts\pre-public-check.ps1

  Windows PowerShell:
    powershell -ExecutionPolicy Bypass -File .\scripts\pre-public-check.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $RepoRoot

Write-Host "== codex-github-proxy pre-public check =="
Write-Host "Repository root: $RepoRoot"
Write-Host ""

$forbiddenNamePatterns = @(
    "*.pem",
    "*.key",
    "*.secret",
    "generated-secrets.txt",
    ".env",
    ".env.*",
    "*private-key*",
    "*private_key*"
)

$ignoredDirs = @(
    ".git",
    ".venv",
    "venv",
    "__pycache__",
    "node_modules",
    ".idea",
    ".vscode"
)

function Test-IsIgnoredPath {
    param([string]$Path)

    $parts = @($Path -split '[\\/]+')
    foreach ($dir in $ignoredDirs) {
        if ($parts -contains $dir) {
            return $true
        }
    }
    return $false
}

Write-Host "1. Checking for forbidden local files..."

$foundForbiddenList = New-Object System.Collections.Generic.List[string]

foreach ($pattern in $forbiddenNamePatterns) {
    $matches = @(
        Get-ChildItem -Path . -Recurse -Force -File -Filter $pattern -ErrorAction SilentlyContinue |
            Where-Object { -not (Test-IsIgnoredPath $_.FullName) }
    )

    foreach ($m in $matches) {
        [void]$foundForbiddenList.Add($m.FullName)
    }
}

$foundForbidden = @($foundForbiddenList | Sort-Object -Unique)

if (@($foundForbidden).Count -gt 0) {
    Write-Host ""
    Write-Host "ERROR: Forbidden secret-like files were found:" -ForegroundColor Red
    foreach ($item in $foundForbidden) {
        Write-Host "  $item" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "Remove these files before publishing." -ForegroundColor Red
    exit 1
}

Write-Host "OK: No forbidden local files found."
Write-Host ""

Write-Host "2. Checking Git tracked files..."

$gitAvailable = $false
try {
    $null = git --version 2>$null
    $gitAvailable = $true
} catch {
    $gitAvailable = $false
}

if (-not $gitAvailable) {
    Write-Host "SKIP: git command was not found. Install Git for Windows if you want tracked-file checks." -ForegroundColor Yellow
} elseif (-not (Test-Path ".git")) {
    Write-Host "SKIP: .git directory was not found. This directory is not initialized as a Git repository." -ForegroundColor Yellow
} else {
    $trackedFiles = @(git ls-files)

    $trackedForbiddenList = New-Object System.Collections.Generic.List[string]

    foreach ($file in $trackedFiles) {
        $name = Split-Path $file -Leaf
        foreach ($pattern in $forbiddenNamePatterns) {
            if ($name -like $pattern -or $file -like $pattern) {
                [void]$trackedForbiddenList.Add($file)
                break
            }
        }
    }

    $trackedForbidden = @($trackedForbiddenList | Sort-Object -Unique)

    if (@($trackedForbidden).Count -gt 0) {
        Write-Host ""
        Write-Host "ERROR: Secret-like files are tracked by Git:" -ForegroundColor Red
        foreach ($item in $trackedForbidden) {
            Write-Host "  $item" -ForegroundColor Red
        }
        Write-Host ""
        Write-Host "Remove them from the index and rotate any exposed secrets if they were committed." -ForegroundColor Red
        Write-Host "Example:"
        Write-Host "  git rm --cached <file>"
        exit 1
    }

    Write-Host "OK: No forbidden tracked files found."
    Write-Host ""

    Write-Host "3. Git status summary:"
    git status --short
    Write-Host ""
}

Write-Host "4. Checking expected project files..."

$expectedFiles = @(
    "README.md",
    "SECURITY.md",
    ".gitignore",
    "Dockerfile",
    "main.py",
    "requirements.txt"
)

$missingList = New-Object System.Collections.Generic.List[string]
foreach ($file in $expectedFiles) {
    if (-not (Test-Path $file)) {
        [void]$missingList.Add($file)
    }
}

$missing = @($missingList)

if (@($missing).Count -gt 0) {
    Write-Host ""
    Write-Host "WARNING: Some expected files are missing:" -ForegroundColor Yellow
    foreach ($item in $missing) {
        Write-Host "  $item" -ForegroundColor Yellow
    }
    Write-Host ""
} else {
    Write-Host "OK: Expected project files are present."
    Write-Host ""
}

Write-Host "5. Reminder before publishing:"
Write-Host "  - Do not publish real Cloud Run URLs."
Write-Host "  - Do not publish real GCP project IDs."
Write-Host "  - Do not publish GitHub App IDs or installation IDs from your private environment."
Write-Host "  - Do not publish BOOTSTRAP_TOKEN, SESSION_SIGNING_KEY, or GitHub App private keys."
Write-Host ""
Write-Host "PASS: Pre-public check completed."
