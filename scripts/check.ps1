<#
.SYNOPSIS
Type-checks CastCount.lua with lua-language-server against Ketho's WoW API annotations.

.DESCRIPTION
Fetches both, at the pinned versions below, into .tools/ on first run. Fails on any diagnostic of Warning or worse.
The annotations follow the retail (Mainline) API, which Forever shares for the most part.
#>
$ErrorActionPreference = "Stop"
# A git hook sets these, and they would point the git calls below at this repo instead of the annotations clone.
Remove-Item Env:GIT_DIR, Env:GIT_INDEX_FILE, Env:GIT_WORK_TREE, Env:GIT_PREFIX -ErrorAction SilentlyContinue
$repo = Split-Path -Parent $PSScriptRoot
$tools = Join-Path $repo ".tools"

$luaLsVersion = "3.19.2"
$wowApiCommit = "d0b5b51fac4c52c493371b9b18e66ce604ea4326"

$luaLs = Join-Path $tools "lua-language-server-$luaLsVersion"
$luaLsExe = Join-Path $luaLs "bin\lua-language-server.exe"
if (-not (Test-Path $luaLsExe)) {
    New-Item -ItemType Directory -Force $tools | Out-Null
    $zip = Join-Path $tools "lua-language-server.zip"
    Invoke-WebRequest -UseBasicParsing -OutFile $zip `
        "https://github.com/LuaLS/lua-language-server/releases/download/$luaLsVersion/lua-language-server-$luaLsVersion-win32-x64.zip"
    Expand-Archive -Force $zip $luaLs
    Remove-Item $zip
}

$wowApi = Join-Path $tools "wow-api"
$haveCommit = if (Test-Path (Join-Path $wowApi ".git")) { git -C $wowApi rev-parse HEAD } else { "" }
if ($haveCommit -ne $wowApiCommit) {
    if (Test-Path $wowApi) { Remove-Item -Recurse -Force $wowApi }
    git init -q $wowApi
    git -C $wowApi remote add origin https://github.com/Ketho/vscode-wow-api.git
    git -C $wowApi sparse-checkout set Annotations/Core
    git -C $wowApi fetch -q --depth 1 origin $wowApiCommit
    git -C $wowApi checkout -q FETCH_HEAD
    if ($LASTEXITCODE -ne 0) { throw "Could not fetch Ketho/vscode-wow-api at $wowApiCommit" }
}

$log = Join-Path $tools "check-log"
& $luaLsExe --check $repo --checklevel=Warning --check_format=pretty --logpath $log
exit $LASTEXITCODE
