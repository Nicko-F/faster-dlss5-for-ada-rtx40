# Windows PowerShell 5.1; isolated dummy files, never a game or GPU execution.
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $repo 'tools/Manage.ps1')
$testRoot=Join-Path $repo ('build/test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$PackageRoot=Join-Path $testRoot 'package'
$bin=Join-Path $testRoot 'game/bin/x64'
New-Item -ItemType Directory -Path $bin,(Join-Path $PackageRoot 'compatibility') -Force | Out-Null
function Assert-Hardware {} # Test doubles only: production guards are never bypassed.
function Assert-GameClosed {}
function Expect-Stop([scriptblock]$Code,[string]$Message) {
    $stopped=$false
    try {& $Code} catch {
        if($_.Exception.Message -notmatch $Message){throw "Wrong refusal ($Message): $($_.Exception.Message)"}
        $stopped=$true
    }
    if(-not $stopped){throw "Expected refusal: $Message"}
}
function Require([bool]$Condition,[string]$Message) {if(-not $Condition){throw $Message}}
function Save-FixtureManifest {
    $manifest|ConvertTo-Json|Set-Content (Join-Path $profile 'manifest.json')
    @{schemaVersion=2;profileId='native-dimension-v1';integratedCount=45;
        manifestSha256=(Get-Sha (Join-Path $profile 'manifest.json'));addonSha256=$files['ada-nr.addon64']} |
        ConvertTo-Json | Set-Content (Join-Path $PackageRoot 'compatibility/automatic.lock.json')
    @{schemaVersion=1;profiles=@{'1920x1080'=@{integratedCount=43;manifestSha256=('a'*64);
        addonSha256=$files['ada-nr.addon64']}}} | ConvertTo-Json -Depth 6 |
        Set-Content (Join-Path $PackageRoot 'compatibility/profiles.lock.json')
}
try {
    $baseFiles=@{}
    foreach($name in @('Cyberpunk2077.exe','dxgi.dll','renodx-dlss5.addon64','nvngx_dlssnr.dll')) {
        [IO.File]::WriteAllText((Join-Path $bin $name),"test fixture $name")
        $baseFiles[$name]=Get-Sha (Join-Path $bin $name)
    }
    @{files=$baseFiles}|ConvertTo-Json|Set-Content (Join-Path $PackageRoot 'compatibility/baseline.json')
    $profile=Join-Path $PackageRoot 'profiles/automatic'
    New-Item -ItemType Directory -Path (Join-Path $profile 'bundle') -Force | Out-Null
    $files=@{}
    $fixtureNames=@('ada-nr.addon64','bundle/frontback-pre.cubin','bundle/frontback-post.cubin','bundle/mode.txt')
    $fixtureNames+=@(0..44 | ForEach-Object {'bundle/integrated-{0:d2}.cubin' -f $_})
    foreach($name in $fixtureNames) {
        $content=if($name -eq 'bundle/mode.txt'){'2'}else{"test fixture $name"}
        [IO.File]::WriteAllText((Join-Path $profile $name),$content)
        $files[$name]=Get-Sha (Join-Path $profile $name)
    }
    $manifest=@{schemaVersion=2;profileId='native-dimension-v1';mode=2;files=$files}
    Save-FixtureManifest
    Require ((Get-GameBin (Split-Path (Split-Path $bin))) -eq $bin) 'Game root resolution failed'
    [IO.File]::Move((Join-Path $profile 'manifest.json'),(Join-Path $profile 'manifest.saved'))
    Expect-Stop {Get-Profile} 'payload is not included'
    [IO.File]::Move((Join-Path $profile 'manifest.saved'),(Join-Path $profile 'manifest.json'))
    Install-Profile $bin
    Expect-Stop {Install-Profile $bin} 'already exists'
    Require ((Get-Sha (Join-Path $bin 'ada-nr.addon64')) -eq $files['ada-nr.addon64']) 'Installed bytes differ'
    [IO.File]::WriteAllText((Join-Path $bin 'ada-nr.addon64'),'unknown replacement')
    Expect-Stop {Remove-Profile $bin} 'Addon changed'
    Require (Test-Path (Join-Path $bin 'ada-nr.addon64')) 'Changed addon was deleted'
    [IO.File]::Copy((Join-Path $profile 'ada-nr.addon64'),(Join-Path $bin 'ada-nr.addon64'),$true)
    $bundle=Join-Path $profile 'bundle'
    [IO.File]::WriteAllText((Join-Path $bundle 'launch-time.txt'),[DateTime]::UtcNow.AddSeconds(-10).ToString('o'))
    [IO.File]::WriteAllText((Join-Path $bundle 'ada-nr-events.log'),"hook,1,mode,2`nevaluate_hook,1`n")
    $header='graph,optimized,replaced,guard_failed,launch_errors,width,height,frontback,surface_failed,history_native,output_format'
    [IO.File]::WriteAllText((Join-Path $bundle 'ada-nr-frames.csv'),"$header`n0,1,145,0,0,1920,1080,0,0,2,28`n1,1,145,0,0,2560,1600,2,0,0,28`n2,1,145,0,0,3440,1440,2,0,0,28`n")
    Show-Status $bin
    [IO.File]::AppendAllText((Join-Path $bundle 'ada-nr-frames.csv'),"2,1,144,1,0,1920,1080,2,0,0,28`n")
    Expect-Stop {Show-Status $bin} 'failed routing evidence'
    [IO.File]::WriteAllText((Join-Path $bundle 'launch-time.txt'),[DateTime]::UtcNow.AddMinutes(1).ToString('o'))
    Expect-Stop {Show-Status $bin} 'Logs predate'
    [IO.File]::WriteAllText((Join-Path $bundle 'integrated-00.cubin'),'damaged')
    Expect-Stop {Get-Profile} 'Payload mismatch'
    Remove-Profile $bin # Damaged payload must not prevent removal of our intact addon.
    Require (-not (Test-Path (Join-Path $bin 'ada-nr.addon64'))) 'Addon remained after removal'
    Assert-Baseline $bin
    $saved=$files['bundle/integrated-44.cubin']
    $manifest.files.Remove('bundle/integrated-44.cubin')
    $manifest|ConvertTo-Json|Set-Content (Join-Path $profile 'manifest.json')
    Expect-Stop {Get-Profile $false} 'not the pinned tested identity'
    Save-FixtureManifest
    Expect-Stop {Get-Profile $false} 'Profile file set'
    $manifest.files['bundle/integrated-45.cubin']=$saved
    Save-FixtureManifest
    Expect-Stop {Get-Profile $false} 'Profile file set'
    $manifest.files['bundle/integrated-44.cubin']=$saved
    Save-FixtureManifest
    Expect-Stop {Get-Profile $false} 'Profile file set'
    $manifest.files.Remove('bundle/integrated-45.cubin')
    $manifest.files['../escape.cubin']='a'*64
    Save-FixtureManifest
    Expect-Stop {Get-Profile $false} 'Profile file set'
    $manifest.files.Remove('../escape.cubin');Save-FixtureManifest
    # Recover from an interrupted install or lost/moved package without payload access.
    $statePath=Join-Path $bin 'faster-dlss5-install.json'
    $record=@{schemaVersion=2;profileId='native-dimension-v1';addonSha256=$files['ada-nr.addon64'];packageRoot='old-moved-package'}
    $record|ConvertTo-Json|Set-Content $statePath
    [IO.File]::Move((Join-Path $profile 'manifest.json'),(Join-Path $profile 'manifest.saved'))
    Remove-Profile $bin
    Require (-not (Test-Path $statePath)) 'State-only recovery failed'
    $record|ConvertTo-Json|Set-Content $statePath
    [IO.File]::Copy((Join-Path $profile 'ada-nr.addon64'),(Join-Path $bin 'ada-nr.addon64'),$false)
    Remove-Profile $bin
    Require (-not (Test-Path (Join-Path $bin 'ada-nr.addon64'))) 'Removal depended on a lost manifest'
    $record.addonSha256='c'*64;$record|ConvertTo-Json|Set-Content $statePath
    Expect-Stop {Remove-Profile $bin} 'not a known addon identity'
    $record.schemaVersion=9;$record|ConvertTo-Json|Set-Content $statePath
    Expect-Stop {Remove-Profile $bin} 'Invalid installation record'
    $record.schemaVersion=2;$record.addonSha256=$files['ada-nr.addon64'];$record|ConvertTo-Json|Set-Content $statePath
    [IO.File]::WriteAllText((Join-Path $bin 'ada-nr.addon64'),'concurrent unknown file')
    Expect-Stop {Remove-Profile $bin} 'Addon changed'
    Remove-Profile $bin $true
    Require (Test-Path (Join-Path $bin 'ada-nr.addon64')) 'Record-only recovery removed an unknown file'
    # Legacy earlier fixed-size draft records remain removable without reinstalling the old package.
    [IO.File]::WriteAllText((Join-Path $bin 'ada-nr.addon64'),'test fixture ada-nr.addon64')
    @{schemaVersion=1;resolution='1920x1080';addonSha256=$files['ada-nr.addon64']} |
        ConvertTo-Json | Set-Content $statePath
    Remove-Profile $bin
    Require (-not (Test-Path (Join-Path $bin 'ada-nr.addon64'))) 'Legacy recovery failed'
    Assert-Baseline $bin
    Write-Host 'PASS: identity/file-set enforcement, install/collision/tamper checks, routing/stale logs, lost-package/interrupted-install recovery and baseline preservation.'
} finally {
    # Recursive removal is restricted to the exact freshly-created test directory.
    $resolved=[IO.Path]::GetFullPath($testRoot)
    $expected=[IO.Path]::GetFullPath((Join-Path $repo 'build'))+[IO.Path]::DirectorySeparatorChar
    if(-not $resolved.StartsWith($expected,[StringComparison]::OrdinalIgnoreCase) -or
       (Split-Path $resolved -Leaf) -notmatch '^test-[a-f0-9]{32}$'){throw 'Unsafe test cleanup target'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
