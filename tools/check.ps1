# DGs Junk - pre-check. Run before committing or before a /reload.
#
#   powershell -ExecutionPolicy Bypass -File tools\check.ps1
#
# Two passes, cheapest first:
#   1. LuaJIT parses the file. LuaJIT is Lua 5.1, the same dialect the WoW client
#      runs, so "it parses here" means "it will load in game".
#   2. lua-language-server runs static diagnostics: undefined globals (a typo'd
#      variable name, or an upvalue used before it is declared), unused locals,
#      shadowing. Configured by .luarc.json, which declares the WoW API globals -
#      anything NOT in that list and not local is a real finding.
#
# Exit code 0 = clean. Anything else = do not commit.

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

$luajit = Join-Path $env:LOCALAPPDATA 'Programs\LuaJIT\bin\luajit.exe'
$lls    = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\LuaLS.lua-language-server_Microsoft.Winget.Source_8wekyb3d8bbwe\bin\lua-language-server.exe'

$failed = $false

Write-Host "== syntax (LuaJIT / Lua 5.1) ==" -ForegroundColor Cyan
if (-not (Test-Path $luajit)) {
    Write-Host "luajit.exe not found - winget install DEVCOM.LuaJIT" -ForegroundColor Yellow
} else {
    foreach ($f in Get-ChildItem $repo -Filter '*.lua' -File) {
        # No 2>&1 here: redirecting a native command's stderr in PowerShell 5.1
        # wraps every line in a NativeCommandError, which buries the one line that
        # matters (file:line: what is wrong). Let it print as-is and judge by the
        # exit code alone.
        & $luajit -bl $f.FullName NUL
        if ($LASTEXITCODE -ne 0) {
            Write-Host "FAIL $($f.Name)" -ForegroundColor Red
            $failed = $true
        } else {
            Write-Host "ok   $($f.Name)" -ForegroundColor Green
        }
    }
}

Write-Host ""
Write-Host "== diagnostics (lua-language-server) ==" -ForegroundColor Cyan
if (-not (Test-Path $lls)) {
    Write-Host "lua-language-server not found - winget install LuaLS.lua-language-server" -ForegroundColor Yellow
} else {
    $log = Join-Path $env:TEMP 'dgsjunk-lls'
    New-Item -ItemType Directory -Force $log | Out-Null
    & $lls --check $repo --checklevel=Warning --logpath=$log
    if ($LASTEXITCODE -ne 0) {
        Write-Host "FAIL - see the findings above" -ForegroundColor Red
        Write-Host "If a finding is a WoW global we simply have not declared yet, add it to .luarc.json." -ForegroundColor Yellow
        $failed = $true
    } else {
        Write-Host "ok   no diagnostics" -ForegroundColor Green
    }
}

Write-Host ""
if ($failed) {
    Write-Host "PRE-CHECK FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "PRE-CHECK PASSED" -ForegroundColor Green
exit 0
