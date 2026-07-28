# Point git at the version-controlled hooks in .githooks.
#
#   powershell -ExecutionPolicy Bypass -File tools\install-hooks.ps1
#
# core.hooksPath is a local git setting, so it does NOT travel with a clone - run
# this once per clone. Everything it enables (the hook itself) IS version
# controlled, which is the point: .git/hooks would only ever exist on one machine.

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

Push-Location $repo
try {
    git config core.hooksPath .githooks
    Write-Host "core.hooksPath = $(git config core.hooksPath)" -ForegroundColor Green

    # Git for Windows honours the executable bit from the index, so make sure it
    # is set - otherwise the hook is silently never run.
    git update-index --chmod=+x .githooks/pre-push 2>$null | Out-Null

    Write-Host "pre-push hook active: pushes now run tools\check.ps1 first." -ForegroundColor Green
} finally {
    Pop-Location
}
