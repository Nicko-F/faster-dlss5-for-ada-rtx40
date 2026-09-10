# Windows PowerShell 5.1; isolated dummy files, never a game or GPU execution.
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
. (Join-Path $repo 'tools/Manage.ps1')
$testRoot=Join-Path $repo ('build/test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$PackageRoot=Join-Path $testRoot 'package'
$bin=Join-Path $testRoot 'game/bin/x64'
New-Item -ItemType Directory -Path $bin,$PackageRoot -Force | Out-Null
# Fixtures exercise filesystem behavior, without launching games or querying a GPU.
function Assert-Hardware {}
function Assert-GameClosed {}
function Get-CimInstance { [pscustomobject]@{Name='Fixture GPU';DriverVersion='1.0'} }
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

}
try {
    $baseFiles=@{}
    foreach($name in @('Cyberpunk2077.exe','dxgi.dll','renodx-dlss5.addon64','nvngx_dlssnr.dll')) {
        [IO.File]::WriteAllText((Join-Path $bin $name),"test fixture $name")
        $baseFiles[$name]=Get-Sha (Join-Path $bin $name)
    }
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
    foreach($name in @(Get-ManagerFiles)) {
        $dest=Join-Path $PackageRoot $name
        New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force|Out-Null
        Copy-Item -LiteralPath (Join-Path $repo $name) -Destination $dest
    }
    # No game-name, executable hash, runtime hash or host/plugin hash whitelist.
    Remove-Item -LiteralPath (Join-Path $bin 'Cyberpunk2077.exe')
    [IO.File]::WriteAllText((Join-Path $bin 'OtherGame.exe'),'another game')
    [IO.File]::AppendAllText((Join-Path $bin 'nvngx_dlssnr.dll'),' upstream packaging update')
    [IO.File]::AppendAllText((Join-Path $bin 'renodx-dlss5.addon64'),' upstream plugin update')
    [IO.File]::AppendAllText((Join-Path $bin 'dxgi.dll'),' newer ReShade')
    $before=@{};foreach($file in Get-ChildItem -LiteralPath $bin -File){$before[$file.Name]=Get-Sha $file.FullName}
    Assert-Baseline $bin
    Require ((Get-GameBin (Split-Path (Split-Path $bin))) -eq $bin) 'Game root resolution failed'
    Require ((Get-GameBin ($bin+'\')) -eq $bin) 'Trailing directory separator was not normalized'
    [IO.File]::Move((Join-Path $profile 'manifest.json'),(Join-Path $profile 'manifest.saved'))
    Expect-Stop {Get-Profile} 'complete acceleration package'
    [IO.File]::Move((Join-Path $profile 'manifest.saved'),(Join-Path $profile 'manifest.json'))
    Install-Profile ($bin+'\')
    # Updating preserves extra files and does not depend on hashes of the base.
    [IO.File]::WriteAllText((Join-Path $bin 'faster-dlss5/player-note.txt'),'keep me')
    Install-Profile $bin
    Require (Test-Path -LiteralPath (Join-Path $script:BackupPath 'faster-dlss5/player-note.txt')) 'Update lost player files'
    Require ((Get-AccelerationStatus $bin).code -eq 'installed') 'Update reused old session evidence'
    $originalState=Get-Sha (Join-Path $bin 'faster-dlss5-install.json')
    [IO.File]::WriteAllText((Join-Path $profile 'bundle/integrated-00.cubin'),'broken download')
    Expect-Stop {Install-Profile $bin} 'package file is damaged'
    Require ((Get-Sha (Join-Path $bin 'faster-dlss5-install.json')) -eq $originalState) 'Bad download altered installation'
    [IO.File]::WriteAllText((Join-Path $profile 'bundle/integrated-00.cubin'),'test fixture bundle/integrated-00.cubin')
    # Inject a failure during activation, after the old copy has been saved.
    function Move-Item {
        param($LiteralPath,$Destination)
        if($LiteralPath -match 'faster-dlss5-stage-[a-f0-9]+[\\/]ada-nr.addon64$'){throw 'Simulated activation failure'}
        Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination
    }
    Expect-Stop {Install-Profile $bin} 'Simulated activation failure'
    Remove-Item Function:\Move-Item
    Require ((Get-Sha (Join-Path $bin 'faster-dlss5-install.json')) -eq $originalState) 'Failed update did not restore installation'
    Require ((Get-AccelerationStatus $bin).code -eq 'installed') 'Restored installation is unusable'
    $downloadRoot=$PackageRoot
    $PackageRoot=Join-Path $bin 'faster-dlss5'
    Install-Profile $bin
    $PackageRoot=$downloadRoot
    Require ((Get-AccelerationStatus $bin).code -eq 'installed') 'Update from installed manager failed'
    # A separate process holds the same mutex while all mutation paths are tried.
    $job=Start-Job -ArgumentList $repo,$bin -ScriptBlock {
        param($repo,$bin)
        . (Join-Path $repo 'tools/Manage.ps1')
        $mutex=Enter-InstallationLock $bin
        try {Write-Output 'locked';Start-Sleep -Seconds 15} finally {$mutex.ReleaseMutex();$mutex.Dispose()}
    }
    try {
        $ready=$false
        for($attempt=0;$attempt -lt 50;$attempt++) {
            if(@(Receive-Job $job -Keep) -contains 'locked'){$ready=$true;break}
            Start-Sleep -Milliseconds 100
        }
        Require $ready 'Lock fixture did not start'
        Expect-Stop {Install-Profile $bin} 'Another installation'
        Expect-Stop {Install-Profile ($bin+'\')} 'Another installation'
        Expect-Stop {Remove-Profile ($bin+'\')} 'Another installation'
        Expect-Stop {Remove-Profile $bin} 'Another installation'
        Expect-Stop {Remove-Profile $bin $true} 'Another installation'
    } finally {Stop-Job $job;Remove-Job $job}
    Require ((Get-Sha (Join-Path $bin 'ada-nr.addon64')) -eq $files['ada-nr.addon64']) 'Installed bytes differ'
    [IO.File]::WriteAllText((Join-Path $bin 'ada-nr.addon64'),'unknown replacement')
    Expect-Stop {Remove-Profile $bin} 'Addon changed'
    Require (Test-Path (Join-Path $bin 'ada-nr.addon64')) 'Changed addon was deleted'
    [IO.File]::Copy((Join-Path $profile 'ada-nr.addon64'),(Join-Path $bin 'ada-nr.addon64'),$true)
    $bundle=Join-Path (Get-Installation $bin).profile.root 'bundle'
    [IO.File]::WriteAllText((Join-Path $bundle 'launch-time.txt'),[DateTime]::UtcNow.AddSeconds(-10).ToString('o'))
    [IO.File]::WriteAllText((Join-Path $bundle 'ada-nr-events.log'),"hook,1,mode,2`nevaluate_hook,1`n")
    Require ((Get-AccelerationStatus $bin).code -eq 'waiting') 'Loaded addon without frames was not shown as waiting'
    [IO.File]::AppendAllText((Join-Path $bundle 'ada-nr-events.log'),"load_failed`n")
    Require ((Get-AccelerationStatus $bin).code -eq 'partial') 'Failure before first frame was shown as waiting'
    [IO.File]::WriteAllText((Join-Path $bundle 'ada-nr-events.log'),"hook,1,mode,2`nevaluate_hook,1`n")
    $header='graph,optimized,replaced,guard_failed,launch_errors,width,height,frontback,surface_failed,history_native,output_format'
    [IO.File]::WriteAllText((Join-Path $bundle 'ada-nr-frames.csv'),"$header`n0,1,145,0,0,1920,1080,0,0,2,28`n1,1,145,0,0,2560,1600,2,0,0,28`n2,1,145,0,0,3440,1440,2,0,0,28`n")
    Require ((Get-AccelerationStatus $bin).code -eq 'active') 'Normal-launch evidence was not accepted'
    $privatePath=Join-Path $testRoot 'personal folder/secret.txt'
    [IO.File]::AppendAllText((Join-Path $bundle 'ada-nr-events.log'),"path,$privatePath`n")
    $exportPath=Join-Path $testRoot 'diagnostics.zip'
    Export-Diagnostics $bin $exportPath ('Token '+'ghp_'+('x'*30))|Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive=[IO.Compression.ZipFile]::OpenRead($exportPath)
    try {
        Require ($archive.Entries.Count -eq 4) 'Diagnostic export has unexpected files'
        foreach($entry in $archive.Entries) {
            Require ($entry.FullName -in @('summary.json','README.txt','ada-nr-events.log','ada-nr-frames.csv')) 'Binary or unexpected diagnostic file'
            $reader=New-Object IO.StreamReader($entry.Open())
            try {$text=$reader.ReadToEnd()} finally {$reader.Dispose()}
            Require (-not $text.Contains($privatePath) -and $text -notmatch '[A-Za-z]:\\' -and $text -notmatch 'ghp_') 'Diagnostic export leaked private text'
            if($entry.FullName -eq 'summary.json'){Require (($text|ConvertFrom-Json).status -eq 'active') 'Diagnostic summary is invalid'}
        }
    } finally {$archive.Dispose()}
    $exportSha=Get-Sha $exportPath
    Expect-Stop {Export-Diagnostics $bin $exportPath} 'already exists'
    Require ((Get-Sha $exportPath) -eq $exportSha) 'Export overwrote an existing file'
    Show-Status $bin
    $sessionRows=Get-Content -LiteralPath (Join-Path $bundle 'ada-nr-frames.csv')
    $qualificationCsv=$sessionRows[0]+",qualification,contract_qualified`n"+"0,0,0,0,0,1920,1080,0,0,2,28,1,0`n1,0,0,0,0,1920,1080,0,0,0,28,1,1`n2,1,145,0,0,1920,1080,2,0,0,28,0,1`n"
    [IO.File]::WriteAllText((Join-Path $bundle 'ada-nr-frames.csv'),$qualificationCsv)
    Require ((Get-AccelerationStatus $bin).code -eq 'active') 'Native qualification rows prevented active status'
    # A moved download does not affect the installed copy.
    [IO.Directory]::Move($profile,($profile+'.moved'))
    Require ((Get-Installation $bin).state.schemaVersion -eq 3) 'Installed payload depended on source folder'
    [IO.Directory]::Move(($profile+'.moved'),$profile)
    [IO.File]::AppendAllText((Join-Path $bundle 'ada-nr-frames.csv'),"2,1,144,1,0,1920,1080,2,0,0,28`n")
    Require ((Get-AccelerationStatus $bin).code -eq 'partial') 'Fallback status was concealed'
    [IO.File]::WriteAllText((Join-Path $bundle 'launch-time.txt'),[DateTime]::UtcNow.AddMinutes(1).ToString('o'))
    Require ((Get-AccelerationStatus $bin).code -eq 'partial') 'Steam status incorrectly depends on manager launch stamp'
    [IO.File]::WriteAllText((Join-Path $bundle 'integrated-00.cubin'),'damaged')
    Expect-Stop {Get-Installation $bin} 'package file is damaged'
    $installedManifest=Join-Path (Split-Path -Parent $bundle) 'manifest.json'
    $changed=Read-Json $installedManifest
    $changed.files.'bundle/integrated-00.cubin'=Get-Sha (Join-Path $bundle 'integrated-00.cubin')
    $changed|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $installedManifest
    Expect-Stop {Get-Installation $bin} 'Installed package changed'
    Remove-Profile $bin # Damaged payload must not prevent removal of our intact addon.
    Require (-not (Test-Path (Join-Path $bin 'ada-nr.addon64'))) 'Addon remained after removal'
    Assert-Baseline $bin
    foreach($name in $before.Keys){Require ((Get-Sha (Join-Path $bin $name)) -eq $before[$name]) 'Community file changed'}
    # Modified payload is preserved while the addon itself is removed.
    Require (Test-Path -LiteralPath (Join-Path $script:RecoveryPath 'profiles/automatic/bundle/integrated-00.cubin')) 'Modified payload was deleted'
    Install-Profile $bin
    Remove-Profile $bin
    Require (-not (Test-Path -LiteralPath (Join-Path $bin 'faster-dlss5'))) 'Clean reinstall/removal left an orphan'

    $saved=$files['bundle/integrated-44.cubin']
    $manifest.files.Remove('bundle/integrated-44.cubin')
    $manifest|ConvertTo-Json|Set-Content (Join-Path $profile 'manifest.json')
    Expect-Stop {Get-Profile $false} 'Profile file set'
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
    Remove-Profile $bin # An interrupted record without an addon can be removed.
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
    Write-Host 'PASS: game-agnostic installation, updated base files, self-contained bundle, normal-launch status, corruption/collision checks, legacy recovery and baseline preservation.'
} finally {
    # Recursive removal is restricted to the exact freshly-created test directory.
    $resolved=[IO.Path]::GetFullPath($testRoot)
    $expected=[IO.Path]::GetFullPath((Join-Path $repo 'build'))+[IO.Path]::DirectorySeparatorChar
    if(-not $resolved.StartsWith($expected,[StringComparison]::OrdinalIgnoreCase) -or
       (Split-Path $resolved -Leaf) -notmatch '^test-[a-f0-9]{32}$'){throw 'Unsafe test cleanup target'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
