<#
.SYNOPSIS
Runs Cast Count in wow-ui-sim (https://github.com/Osso/wow-ui-sim), Forever build.

.DESCRIPTION
  test        Run tests/*.lua headless. Fails on a failed test or a Lua error raised in CastCount.lua.
  gui         Open the simulator window with Cast Count loaded and scripts/sim-demo.lua applied.
  screenshot  Render the same demo scene headless to a PNG (default .sim/screenshot.png).

The simulator is found through -Sim, then $env:WOW_SIM, then WOW_SIM=... in the repo's .env, then wow-sim on PATH.

.EXAMPLE
.\scripts\sim.ps1 test
.\scripts\sim.ps1 gui -Class Warrior
.\scripts\sim.ps1 screenshot -Output bar.png
#>
param(
    [Parameter(Position = 0)][ValidateSet("test", "gui", "screenshot")][string]$Command = "test",
    [string]$Sim = $env:WOW_SIM,
    [string]$Class = "Mage",
    [string]$Output,
    # screenshot only: WxH+X+Y region of the 1600x1200 render. "bar" is the main action bar, slots 1-12.
    [string]$Crop
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$demo = Join-Path $PSScriptRoot "sim-demo.lua"

$envFile = Join-Path $repo ".env"
if (-not $Sim -and (Test-Path $envFile)) {
    foreach ($line in Get-Content $envFile) {
        if ($line -match '^\s*WOW_SIM\s*=\s*"?([^"]*?)"?\s*$') { $Sim = $Matches[1] }
    }
}
if (-not $Sim) {
    $onPath = Get-Command wow-sim -ErrorAction SilentlyContinue
    if ($onPath) { $Sim = $onPath.Source }
}
if (-not $Sim -or -not (Test-Path $Sim)) {
    throw "wow-sim not found. Download wow-ui-sim-<version>-forever-windows-x86_64.zip from https://github.com/Osso/wow-ui-sim/releases, unzip it, and put WOW_SIM=<path to wow-sim.exe> in .env at the repo root (or set `$env:WOW_SIM, or pass -Sim)."
}

# The simulator loads an addon by folder name, and this checkout's folder may not be called CastCount.
$addonsRoot = Join-Path ([IO.Path]::GetTempPath()) "castcount-sim"
$link = Join-Path $addonsRoot "CastCount"
if ((Test-Path $link) -and ((Get-Item $link).Target -ne $repo)) { (Get-Item $link).Delete() }
if (-not (Test-Path $link)) {
    New-Item -ItemType Directory -Force $addonsRoot | Out-Null
    New-Item -ItemType Junction -Path $link -Target $repo | Out-Null
}

$common = @("--no-saved-vars", "--allow-ui-version-mismatch", "--addons-path", $addonsRoot, "--class", $Class)

switch ($Command) {
    "test" {
        $ErrorActionPreference = "Continue"
        $lines = & $Sim @common run-tests CastCount 2>&1 | ForEach-Object { "$_" }
        $code = $LASTEXITCODE
        $ErrorActionPreference = "Stop"

        $lines | Where-Object { $_ -match "\.lua > |^ +\S+\.lua:\d+: (?!in )|^\d+ tests?, " } | Write-Host

        # The test runner counts a test as passed even when an event handler in the addon raised.
        $addonErrors = $lines | ForEach-Object {
            if ($_ -match "(CastCount\.lua:\d+: (?!in ).*)") { $Matches[1] }
        } | Select-Object -Unique
        if ($addonErrors) {
            Write-Host "Lua errors from CastCount.lua:" -ForegroundColor Red
            $addonErrors | Write-Host
            if ($code -eq 0) { $code = 1 }
        }
        exit $code
    }
    "gui" {
        $ErrorActionPreference = "Continue"
        & $Sim @common --exec-lua "@$demo"
        exit $LASTEXITCODE
    }
    "screenshot" {
        if (-not $Output) { $Output = Join-Path $repo ".sim\screenshot.png" }
        $Output = [IO.Path]::GetFullPath($Output)
        New-Item -ItemType Directory -Force (Split-Path $Output) | Out-Null

        # Headless rendering does not tick timers, so run the demo on a manual clock and step past the 0.2 s rebuild.
        $scene = Join-Path $addonsRoot "screenshot-scene.lua"
        $body = @("pcall(A_Admin.SetManualClock, GetTime())", (Get-Content -Raw $demo), "A_Admin.AdvanceTime(0.3)")
        [IO.File]::WriteAllText($scene, ($body -join "`n"))

        $shotArgs = @("screenshot", "--allow-ui-version-mismatch", "--png", "-o", $Output)
        if ($Crop -eq "bar") { $Crop = "600x70+180+1130" }
        if ($Crop) { $shotArgs += @("--crop", $Crop) }

        $ErrorActionPreference = "Continue"
        $lines = & $Sim @common --exec-lua "@$scene" @shotArgs 2>&1 | ForEach-Object { "$_" }
        $code = $LASTEXITCODE
        $ErrorActionPreference = "Stop"
        if ($code -ne 0) { $lines | Select-Object -Last 30 | Write-Host; exit $code }
        Write-Host "Saved $Output"
    }
}
