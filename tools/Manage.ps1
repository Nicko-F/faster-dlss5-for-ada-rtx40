[CmdletBinding()]
param(
    [ValidateSet('Menu','Check','Install','Launch','Status','Remove')][string]$Action='Menu',
    [string]$GamePath,
    [switch]$ForgetRecordOnly
)
$ErrorActionPreference='Stop'
$PackageRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

function Read-Json([string]$Path) { Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
function Get-Sha([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Get-NormalDirectory([string]$Path) {
    $full=[IO.Path]::GetFullPath($Path);$root=[IO.Path]::GetPathRoot($full)
    if($full.Length -gt $root.Length){return $full.TrimEnd([char[]]'\/')}
    return $root
}
function Assert-PlainPath([string]$Path) {
    $cursor=[IO.Path]::GetFullPath($Path)
    while($cursor) {
        if(Test-Path -LiteralPath $cursor) {
            if((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Linked paths are not supported: $cursor"
            }
        }
        $parent=Split-Path -Parent $cursor
        if($parent -eq $cursor){break};$cursor=$parent
    }
}
function Get-GameBin([string]$Path) {
    if(-not $Path){throw 'Select the folder containing your community DLSS5 addon.'}
    $resolved=(Resolve-Path -LiteralPath $Path.Trim('"')).Path
    if(Test-Path -LiteralPath $resolved -PathType Leaf){$resolved=Split-Path -Parent $resolved}
    $resolved=Get-NormalDirectory $resolved
    $direct=Join-Path $resolved 'renodx-dlss5.addon64'
    if(Test-Path -LiteralPath $direct){Assert-PlainPath $resolved;return $resolved}
    # Search only inside the folder selected by the player, without following links.
    $queue=New-Object 'Collections.Generic.Queue[string]';$queue.Enqueue($resolved)
    $found=@()
    while($queue.Count) {
        $dir=$queue.Dequeue()
        foreach($child in Get-ChildItem -LiteralPath $dir -Directory -ErrorAction SilentlyContinue) {
            if($child.Attributes -band [IO.FileAttributes]::ReparsePoint){continue}
            if(Test-Path -LiteralPath (Join-Path $child.FullName 'renodx-dlss5.addon64')){$found+=$child.FullName}
            else {$queue.Enqueue($child.FullName)}
        }
    }
    if($found.Count -ne 1){throw 'Select the folder containing renodx-dlss5.addon64 (one community installation at a time).'}
    Assert-PlainPath $found[0];return $found[0]
}
function Assert-GameClosed([string]$Bin) {
    foreach($process in Get-Process -ErrorAction SilentlyContinue) {
        try {$path=$process.Path} catch {continue}
        if($path -and (Split-Path -Parent $path) -eq $Bin){throw 'Close the game before changing its acceleration patch.'}
    }
}
function Assert-Baseline([string]$Bin) {
    foreach($name in @('renodx-dlss5.addon64','nvngx_dlssnr.dll')) {
        if(-not (Test-Path -LiteralPath (Join-Path $Bin $name) -PathType Leaf)){throw "Community DLSS5 file missing: $name. Select its plugin folder."}
    }

}
function Assert-Hardware {
    # Hardware information is diagnostic. CUDA module loading negotiates device/driver support.
    $nvidia=Get-Command 'nvidia-smi.exe' -ErrorAction SilentlyContinue
    if($nvidia) {
        $rows=@(& $nvidia.Source '--query-gpu=name,driver_version' '--format=csv,noheader' 2>$null)
        if($LASTEXITCODE -eq 0){Write-Host ($rows -join '; ')}
    }
}
function Get-Profile([bool]$VerifyPayload=$true,[string]$Root=$PackageRoot) {
    $dir=Join-Path $Root 'profiles/automatic'
    $path=Join-Path $dir 'manifest.json'
    if(-not (Test-Path -LiteralPath $path)) {
        throw 'Open the complete acceleration package to install. The source archive contains the tools and documentation.'
    }
    Assert-PlainPath $dir
    $manifest=Read-Json $path
    if($manifest.schemaVersion -ne 2 -or $manifest.profileId -ne 'native-dimension-v1' -or $manifest.mode -ne 2){throw 'Invalid profile manifest.'}
    $names=@($manifest.files.PSObject.Properties.Name)
    $expected=@('ada-nr.addon64','bundle/mode.txt','bundle/frontback-pre.cubin','bundle/frontback-post.cubin')
    $expected+=@(0..44 | ForEach-Object {'bundle/integrated-{0:d2}.cubin' -f $_})
    if($names.Count -ne $expected.Count -or @(Compare-Object $names $expected).Count) {
        throw 'Profile file set or addon differs from the tested identity.'
    }
    foreach($file in $manifest.files.PSObject.Properties) {
        if($file.Name -notmatch '^(ada-nr\.addon64|bundle/(mode\.txt|integrated-\d{2}\.cubin|frontback-(pre|post)\.cubin))$' -or
           $file.Value -notmatch '^[a-f0-9]{64}$'){throw 'Invalid payload path or hash.'}
        if($VerifyPayload) {
            $target=Join-Path $dir $file.Name
            Assert-PlainPath $target
            if(-not (Test-Path -LiteralPath $target) -or (Get-Sha $target) -ne $file.Value){throw "Acceleration package file is damaged or missing: $($file.Name). Extract the package again."}
        }
    }
    if($VerifyPayload -and (Get-Content -LiteralPath (Join-Path $dir 'bundle/mode.txt') -Raw).Trim() -ne '2'){throw 'Expected optimized mode 2.'}
    return @{root=$dir; manifest=$manifest; sha=(Get-Sha (Join-Path $dir 'ada-nr.addon64'))}
}
function Get-ManagerFiles {
    @('Start.cmd','tools/Manage.ps1','tools/Setup.ps1','tools/PlayerSupport.ps1')
}
function Get-OwnedTarget([string]$Root,[string]$Name) {
    $allowed=($Name -in @(Get-ManagerFiles)) -or $Name -eq 'profiles/automatic/manifest.json' -or
        $Name -match '^profiles/automatic/(ada-nr\.addon64|bundle/(mode\.txt|integrated-\d{2}\.cubin|frontback-(pre|post)\.cubin))$'
    if(-not $allowed){throw 'Invalid installed file path.'}
    $target=Join-Path $Root $Name;Assert-PlainPath $target;return $target
}
function Write-NewInstallation([string]$Bin) {
    $profile=Get-Profile
    $target=Join-Path $Bin 'ada-nr.addon64';$statePath=Join-Path $Bin 'faster-dlss5-install.json'
    $root=Join-Path $Bin 'faster-dlss5'
    if((Test-Path -LiteralPath $target) -or (Test-Path -LiteralPath $statePath) -or (Test-Path -LiteralPath $root)) {
        throw 'An acceleration installation already exists. Use Remove before installing again.'
    }
    $owned=[ordered]@{}
    $names=@(Get-ManagerFiles)+@('profiles/automatic/manifest.json')+@($profile.manifest.files.PSObject.Properties.Name | ForEach-Object {"profiles/automatic/$_"})
    foreach($name in $names){$owned[$name]=Get-Sha (Get-OwnedTarget $PackageRoot $name)}
    $state=[ordered]@{schemaVersion=3;profileId='native-dimension-v1';addonSha256=$profile.sha;installedUtc=[DateTime]::UtcNow.ToString('o');files=$owned}
    $intent=Join-Path $Bin ('faster-dlss5-install-'+[guid]::NewGuid().ToString('N')+'.tmp')
    $bytes=[Text.Encoding]::UTF8.GetBytes(($state|ConvertTo-Json -Depth 5))
    $stream=[IO.File]::Open($intent,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)} finally {$stream.Dispose()}
    try {[IO.File]::Move($intent,$statePath)}finally{if(Test-Path -LiteralPath $intent){Remove-Item -LiteralPath $intent}}
    foreach($name in $names) {
        $dest=Get-OwnedTarget $root $name
        [IO.Directory]::CreateDirectory((Split-Path -Parent $dest)) | Out-Null
        [IO.File]::Copy((Join-Path $PackageRoot $name),$dest,$false)
        if((Get-Sha $dest) -ne $owned[$name]){throw "Copy incomplete: $name. Use Remove and install again."}
    }
    [IO.File]::Copy((Join-Path $profile.root 'ada-nr.addon64'),$target,$false)
    if((Get-Sha $target) -ne $profile.sha){throw 'Addon copy incomplete. Use Remove and install again.'}
}
function Enter-InstallationLock([string]$Bin) {
    $Bin=Get-NormalDirectory $Bin
    $hasher=[Security.Cryptography.SHA256]::Create()
    try {$key=[BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($Bin).ToLowerInvariant()))).Replace('-','')}
    finally {$hasher.Dispose()}
    $mutex=New-Object Threading.Mutex($false,('Local\FasterDLSS5-'+$key))
    try {
        try {$locked=$mutex.WaitOne(0)} catch [Threading.AbandonedMutexException] {$locked=$true}
        if(-not $locked){throw 'Another installation is running. Wait for it to finish and retry.'}
        return $mutex
    } catch {$mutex.Dispose();throw}
}
function Install-Profile([string]$Bin) {
    $Bin=Get-NormalDirectory $Bin
    Assert-PlainPath $Bin;Assert-GameClosed $Bin;Assert-Baseline $Bin
    $script:BackupPath=$null
    $mutex=Enter-InstallationLock $Bin
    $locked=$false;$stage=$null;$backup=$null;$oldMoved=@();$newMoved=@();$rollbackFailed=$false
    try {
        $locked=$true
        $names=@('faster-dlss5','faster-dlss5-install.json','ada-nr.addon64')
        foreach($name in $names){Assert-PlainPath (Join-Path $Bin $name)}
        $existing=@($names | Where-Object {Test-Path -LiteralPath (Join-Path $Bin $_)})
        if($existing.Count) {
            $recordPath=Join-Path $Bin 'faster-dlss5-install.json'
            if(-not (Test-Path -LiteralPath $recordPath)){throw 'Installation record missing. Move the existing patch files aside, then retry.'}
            $record=Read-Json $recordPath
            if($record.schemaVersion -notin @(1,2,3) -or $record.addonSha256 -notmatch '^[a-f0-9]{64}$') {throw 'Invalid installation record.'}
            if($record.schemaVersion -ne 1 -and $record.profileId -ne 'native-dimension-v1'){throw 'Invalid installation record.'}
        }
        # Prepare and verify every new file before touching the installed copy.
        $stage=Join-Path $Bin ('faster-dlss5-stage-'+[guid]::NewGuid().ToString('N'))
        [IO.Directory]::CreateDirectory($stage)|Out-Null
        Write-NewInstallation $stage
        $settings=Join-Path $Bin 'faster-dlss5/build/player-settings.json'
        Assert-PlainPath $settings
        if(Test-Path -LiteralPath $settings) {
            $settingsDir=Join-Path $stage 'faster-dlss5/build'
            [IO.Directory]::CreateDirectory($settingsDir)|Out-Null
            [IO.File]::Copy($settings,(Join-Path $settingsDir 'player-settings.json'))
        }
        Assert-GameClosed $Bin
        $backup=Join-Path $Bin ('faster-dlss5-backup-'+[guid]::NewGuid().ToString('N'))
        [IO.Directory]::CreateDirectory($backup)|Out-Null
        foreach($name in $existing) {
            Move-Item -LiteralPath (Join-Path $Bin $name) -Destination (Join-Path $backup $name)
            $oldMoved+=$name
        }
        # Addon is activated last, after the bundle and installation record exist.
        foreach($name in $names) {
            Move-Item -LiteralPath (Join-Path $stage $name) -Destination (Join-Path $Bin $name)
            $newMoved+=$name
        }
        if($existing.Count){$script:BackupPath=$backup;Write-Host "Previous installation saved to: $backup"}
        else {Remove-Item -LiteralPath $backup}
    } catch {
        $failure=$_
        try {
            [array]::Reverse($newMoved)
            foreach($name in $newMoved) {
                Move-Item -LiteralPath (Join-Path $Bin $name) -Destination (Join-Path $stage $name)
            }
            foreach($name in $oldMoved) {
                Move-Item -LiteralPath (Join-Path $backup $name) -Destination (Join-Path $Bin $name)
            }
            if($backup -and (Test-Path -LiteralPath $backup) -and -not @(Get-ChildItem -LiteralPath $backup -Force).Count){Remove-Item -LiteralPath $backup}
        } catch {
            $rollbackFailed=$true
            throw "Update interrupted; recovery files are in $backup and $stage. $($_.Exception.Message)"
        }
        throw $failure
    } finally {
        try {
            if($stage -and -not $rollbackFailed -and (Test-Path -LiteralPath $stage)) {
                $resolved=[IO.Path]::GetFullPath($stage)
                if((Split-Path -Parent $resolved) -ne [IO.Path]::GetFullPath($Bin) -or (Split-Path -Leaf $resolved) -notmatch '^faster-dlss5-stage-[a-f0-9]{32}$'){throw 'Invalid staging folder.'}
                Assert-PlainPath $resolved
                Remove-Item -LiteralPath $resolved -Recurse -Force
            }
        } finally {if($locked){$mutex.ReleaseMutex()};$mutex.Dispose()}
    }
}
function Get-Installation([string]$Bin,[bool]$VerifyPayload=$true) {
    $statePath=Join-Path $Bin 'faster-dlss5-install.json';Assert-PlainPath $statePath
    $state=Read-Json $statePath
    if($state.schemaVersion -notin @(2,3) -or $state.profileId -ne 'native-dimension-v1'){throw 'Invalid installation record.'}
    $root=if($state.schemaVersion -eq 3){Join-Path $Bin 'faster-dlss5'}else{$state.packageRoot}
    if($state.schemaVersion -eq 3 -and $VerifyPayload) {
        $manifestPath=Get-OwnedTarget $root 'profiles/automatic/manifest.json'
        $recorded=$state.files.'profiles/automatic/manifest.json'
        if($recorded -notmatch '^[a-f0-9]{64}$' -or -not (Test-Path -LiteralPath $manifestPath) -or
           (Get-Sha $manifestPath) -ne $recorded){throw 'Installed package changed. Remove and reinstall the acceleration package.'}
    }
    $profile=Get-Profile $VerifyPayload $root
    if($state.addonSha256 -ne $profile.sha){throw 'Installation record does not match its payload.'}
    return @{state=$state;profile=$profile}
}
function Remove-Profile([string]$Bin,[bool]$RecordOnly=$false) {
    $Bin=Get-NormalDirectory $Bin
    Assert-PlainPath $Bin
    $mutex=Enter-InstallationLock $Bin
    try {Remove-InstalledFiles $Bin $RecordOnly}
    finally {$mutex.ReleaseMutex();$mutex.Dispose()}
}
function Remove-InstalledFiles([string]$Bin,[bool]$RecordOnly=$false) {
    Assert-GameClosed $Bin
    $statePath=Join-Path $Bin 'faster-dlss5-install.json';Assert-PlainPath $statePath
    $state=Read-Json $statePath
    if($state.schemaVersion -notin @(1,2,3) -or $state.addonSha256 -notmatch '^[a-f0-9]{64}$'){throw 'Invalid installation record.'}
    if($state.schemaVersion -ne 1 -and $state.profileId -ne 'native-dimension-v1'){throw 'Invalid installation record.'}
    $target=Join-Path $Bin 'ada-nr.addon64';Assert-PlainPath $target
    if($RecordOnly){Remove-Item -LiteralPath $statePath;Write-Host 'Installation record removed; addon files remain.';return}
    if(Test-Path -LiteralPath $target) {
        if((Get-Sha $target) -ne $state.addonSha256){throw 'Addon changed since installation. Restore the original patch addon before removing it.'}
    }
    $root=Join-Path $Bin 'faster-dlss5';$owned=@()
    if($state.schemaVersion -eq 3) {
        foreach($file in $state.files.PSObject.Properties) {
            $dest=Get-OwnedTarget $root $file.Name
            if($file.Value -notmatch '^[a-f0-9]{64}$'){throw 'Invalid installed file hash.'}
            $owned+=@{path=$dest;sha=$file.Value}
        }
    }
    if(Test-Path -LiteralPath $target){Remove-Item -LiteralPath $target}
    # Delete only recorded files with matching bytes. Keep any user-added or modified files.
    foreach($file in $owned){if((Test-Path -LiteralPath $file.path) -and (Get-Sha $file.path) -eq $file.sha){Remove-Item -LiteralPath $file.path}}
    if($state.schemaVersion -eq 3) {
        foreach($name in @('profiles/automatic/bundle/ada-nr-events.log','profiles/automatic/bundle/ada-nr-frames.csv','profiles/automatic/bundle/launch-time.txt','build/player-settings.json')) {
            $path=Join-Path $root $name;Assert-PlainPath $path
            if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path}
        }
        $dirs=@($owned | ForEach-Object {Split-Path -Parent $_.path})+@((Join-Path $root 'profiles'),(Join-Path $root 'build'),$root)
        foreach($dir in ($dirs | Sort-Object -Unique | Sort-Object { $_.Length } -Descending)) {
            if((Test-Path -LiteralPath $dir) -and -not @(Get-ChildItem -LiteralPath $dir -Force).Count){Remove-Item -LiteralPath $dir}
        }
    }
    if($state.schemaVersion -eq 3 -and (Test-Path -LiteralPath $root)) {
        $resolved=[IO.Path]::GetFullPath($root);$parent=[IO.Path]::GetFullPath($Bin)
        $recovery=Join-Path $parent ('faster-dlss5-recovered-'+[guid]::NewGuid().ToString('N'))
        if((Split-Path -Parent $resolved) -ne $parent -or (Split-Path -Leaf $resolved) -ne 'faster-dlss5' -or
           (Split-Path -Parent $recovery) -ne $parent){throw 'Invalid recovery folder.'}
        Assert-PlainPath $resolved
        Move-Item -LiteralPath $resolved -Destination $recovery
        Write-Host "Modified or additional files saved to: $recovery"
        $script:RecoveryPath=$recovery
    }
    Remove-Item -LiteralPath $statePath
    Write-Host 'Acceleration removed. Your community DLSS5 installation is ready to use.'
}
function Get-AccelerationStatus([string]$Bin) {
    if(-not (Test-Path -LiteralPath (Join-Path $Bin 'faster-dlss5-install.json'))){return @{code='not-installed';graphs=0}}
    $install=Get-Installation $Bin
    $addon=Join-Path $Bin 'ada-nr.addon64'
    if(-not (Test-Path -LiteralPath $addon) -or (Get-Sha $addon) -ne $install.profile.sha){throw 'Installed addon is missing or changed. Remove and reinstall the patch.'}
    $bundle=Join-Path $install.profile.root 'bundle'
    $events=Join-Path $bundle 'ada-nr-events.log';$frames=Join-Path $bundle 'ada-nr-frames.csv'
    $installed=[DateTime]::Parse($install.state.installedUtc).ToUniversalTime()
    if(-not (Test-Path -LiteralPath $events) -or (Get-Item -LiteralPath $events).LastWriteTimeUtc -lt $installed){return @{code='installed';graphs=0;bundle=$bundle}}
    $log=Get-Content -LiteralPath $events -Raw
    if(-not (Test-Path -LiteralPath $frames) -or (Get-Item -LiteralPath $frames).LastWriteTimeUtc -lt $installed) {
        $code=if($log -match 'failed|sequence_fallback'){'partial'}else{'waiting'}
        return @{code=$code;graphs=0;bundle=$bundle;lastRun=(Get-Item -LiteralPath $events).LastWriteTime}
    }
    $rows=@(Import-Csv -LiteralPath $frames)
    $qualifiedRows=@($rows | Where-Object {
        $_.qualification -eq '1' -and $_.optimized -eq '0' -and $_.replaced -eq '0' -and
        $_.frontback -eq '0' -and $_.guard_failed -eq '0' -and $_.launch_errors -eq '0' -and $_.surface_failed -eq '0'
    })
    $good=@($rows | Where-Object {
        $_.optimized -eq '1' -and $_.replaced -eq '145' -and $_.guard_failed -eq '0' -and $_.launch_errors -eq '0' -and
        $_.surface_failed -eq '0' -and $_.width -match '^[1-9][0-9]{0,4}$' -and $_.height -match '^[1-9][0-9]{0,4}$' -and
        [long]$_.width -le 16384 -and [long]$_.height -le 16384 -and $_.output_format -in @('28','10') -and
        (($_.frontback -eq '2' -and $_.history_native -eq '0') -or ($_.frontback -eq '0' -and $_.history_native -eq '2'))
    })
    $hook=$log -match 'hook,1,mode,2' -and $log -match 'evaluate_hook,1'
    if($rows.Count -and ($rows[0].PSObject.Properties.Name -contains 'qualification')) {
        $hook=$hook -and @($rows | Where-Object {$_.contract_qualified -eq '1'}).Count -gt 0
    }
    $code=if($hook -and $good.Count -gt 0 -and ($good.Count+$qualifiedRows.Count) -eq $rows.Count -and $log -notmatch 'failed|sequence_fallback'){'active'}
          elseif(($rows.Count -gt $qualifiedRows.Count) -or $log -match 'failed|sequence_fallback'){'partial'}else{'waiting'}
    return @{code=$code;graphs=$good.Count;total=$rows.Count;bundle=$bundle;lastRun=(Get-Item -LiteralPath $events).LastWriteTime}
}
function Show-Status([string]$Bin) {
    $status=Get-AccelerationStatus $Bin
    $messages=@{'not-installed'='Not installed.';installed='Installed. Start the game and enable community DLSS5.';
        active='Acceleration worked in the last recorded game session.';partial='Some work used the community path. Open the diagnostic folder for details.';
        waiting='The addon started; waiting for DLSS5 frames.'}
    Write-Host $messages[$status.code]
    if($status.graphs){Write-Host "Accelerated frames: $($status.graphs)"}
    if($env:ADA_NR_BUNDLE){Write-Host "ADA_NR_BUNDLE overrides the installed bundle: $env:ADA_NR_BUNDLE"}
}
function Invoke-Manager {
    if($Action -eq 'Menu'){& (Join-Path $PSScriptRoot 'Setup.ps1');return}
    $bin=Get-GameBin $GamePath
    switch($Action) {
        'Check' {Assert-Baseline $bin;Assert-Hardware;Get-Profile|Out-Null;Write-Host 'Ready to install.'}
        'Install' {Install-Profile $bin}
        'Launch' {Write-Host 'Start the game through your usual launcher; the installed patch loads automatically.'}
        'Status' {Show-Status $bin}
        'Remove' {Remove-Profile $bin ([bool]$ForgetRecordOnly)}
    }
}
. (Join-Path $PSScriptRoot 'PlayerSupport.ps1')
if($MyInvocation.InvocationName -ne '.') {
    try {Invoke-Manager} catch {Write-Host $_.Exception.Message -ForegroundColor Red;exit 1}
}
