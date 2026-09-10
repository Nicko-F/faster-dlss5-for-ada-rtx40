[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$NgxInclude,
    [Parameter(Mandatory=$true)][string]$Bundle,
    [string]$Output,
    [string]$VcVarsPath
)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if(-not $Output){$Output=Join-Path $repo 'build/addon'}
$Output=[IO.Path]::GetFullPath($Output)
if(Test-Path -LiteralPath $Output){throw 'Choose a new addon output folder so failed builds cannot reuse old receipts.'}
$NgxInclude=(Resolve-Path -LiteralPath $NgxInclude).Path
$Bundle=(Resolve-Path -LiteralPath $Bundle).Path
foreach($name in @('nvsdk_ngx_params.h','nvsdk_ngx_defs.h')) {
    if(-not (Test-Path -LiteralPath (Join-Path $NgxInclude $name))){throw "NGX header missing: $name"}
}
if(-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) {
    if(-not $VcVarsPath) {
        $vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
        if(-not (Test-Path -LiteralPath $vswhere)){throw 'Use an x64 Native Tools PowerShell prompt, or provide -VcVarsPath.'}
        $vs=& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if(-not $vs){throw 'Install the Visual Studio C++ desktop build tools.'}
        $VcVarsPath=Join-Path $vs 'VC/Auxiliary/Build/vcvarsall.bat'
    }
    $VcVarsPath=(Resolve-Path -LiteralPath $VcVarsPath).Path
    if($VcVarsPath -match '["\r\n%]'){throw 'Unsupported compiler setup path'}
    # Only import the compiler environment here; builds use argument arrays below.
    $lines=& $env:ComSpec /d /c "call `"$VcVarsPath`" x64 >nul && set"
    if($LASTEXITCODE){throw 'MSVC setup failed'}
    foreach($line in $lines){$i=$line.IndexOf('=');if($i -gt 0){Set-Item -LiteralPath "Env:$($line.Substring(0,$i))" -Value $line.Substring($i+1)}}
}
$generated=Join-Path $Output 'generated'
& python (Join-Path $PSScriptRoot 'generate_dispatch.py') --bundle $Bundle --output $generated
if($LASTEXITCODE){throw 'Dispatch generation failed'}
$flags=@('/nologo','/std:c++17','/EHsc','/O2','/MD','/W4','/utf-8',"/I$NgxInclude","/I$generated",('/I'+(Join-Path $repo 'include')))
Push-Location $Output
try {
    & cl.exe @flags /FAs /Faada-nr.asm /LD (Join-Path $repo 'src/integration/ada_nr_addon.cpp') /Fe:ada-nr.addon64 /link bcrypt.lib
    if($LASTEXITCODE){throw 'Addon build failed'}
    $assembly=Get-Content -LiteralPath 'ada-nr.asm' -Raw
    $body=[regex]::Match($assembly,'(?ms)^\?EvaluateFeature@ada_game@@.*? PROC.*?^\?EvaluateFeature@ada_game@@.*? ENDP').Value
    if(-not $body -or $body -notmatch '(?m)^\s*(rex_)?jmp\s+rax\s*$' -or $body -match '(?m)^\s*call\s+rax\s*$'){throw 'Evaluate forwarding must remain a tail jump'}
    & cl.exe @flags (Join-Path $repo 'tests/native/dynamic_route_test.cpp') /Fe:dynamic-routes.exe /link bcrypt.lib
    if($LASTEXITCODE){throw 'Route test build failed'}
    & .\dynamic-routes.exe
    if($LASTEXITCODE){throw 'Route tests failed'}
    $receipt=@{schemaVersion=1;addonSha256=(Get-FileHash -LiteralPath 'ada-nr.addon64' -Algorithm SHA256).Hash.ToLowerInvariant();contractSha256=(Get-FileHash -LiteralPath (Join-Path $repo 'config/network.json') -Algorithm SHA256).Hash.ToLowerInvariant();tailJumpVerified=$true;routeTestsPassed=$true}
    $receipt.bundleIdentitiesSha256=(Get-FileHash -LiteralPath (Join-Path $generated 'bundle-identities.json') -Algorithm SHA256).Hash.ToLowerInvariant()
    $receipt|ConvertTo-Json|Set-Content -LiteralPath 'build.json' -Encoding UTF8
} finally {Pop-Location}
Write-Output "BUILT: $Output\ada-nr.addon64"
