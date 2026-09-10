[CmdletBinding()]
param(
    [ValidateSet('Menu','Check','Install','Launch','Status','Remove')][string]$Action='Menu',
    [string]$GamePath,
    [switch]$ForgetRecordOnly
)
$ErrorActionPreference='Stop'
$PackageRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

function Read-Json([string]$Path) { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
function Get-Sha([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
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
    if(-not $Path){throw 'Choose the Cyberpunk 2077 installation folder.'}
    $resolved=(Resolve-Path -LiteralPath $Path).Path
    $bin=if(Test-Path -LiteralPath (Join-Path $resolved 'Cyberpunk2077.exe')){$resolved}else{Join-Path $resolved 'bin/x64'}
    Assert-PlainPath $bin
    if(-not (Test-Path -LiteralPath (Join-Path $bin 'Cyberpunk2077.exe'))){throw 'Cyberpunk2077.exe was not found.'}
    return $bin
}
function Assert-GameClosed {
    if(Get-Process -Name 'Cyberpunk2077' -ErrorAction SilentlyContinue){throw 'Close Cyberpunk 2077 first.'}
}
function Assert-Baseline([string]$Bin) {
    $baseline=Read-Json (Join-Path $PackageRoot 'compatibility/baseline.json')
    $names=@('Cyberpunk2077.exe','dxgi.dll','renodx-dlss5.addon64','nvngx_dlssnr.dll')
    if(@($baseline.files.PSObject.Properties).Count -ne $names.Count){throw 'Invalid baseline file set.'}
    foreach($file in $baseline.files.PSObject.Properties) {
        if($file.Name -notin $names -or $file.Value -notmatch '^[a-f0-9]{64}$'){throw 'Invalid baseline identity.'}
        $path=Join-Path $Bin $file.Name
        if(-not (Test-Path -LiteralPath $path) -or (Get-Sha $path) -ne $file.Value) {
            throw "Baseline mismatch: $($file.Name). Use your existing matching community installation; no vendor files are downloaded."
        }
    }
}
function Assert-Hardware {
    $nvidia=Get-Command 'nvidia-smi.exe' -ErrorAction SilentlyContinue
    if(-not $nvidia){throw 'nvidia-smi was not found. This build requires the validated NVIDIA driver.'}
    $rows=@(& $nvidia.Source '--query-gpu=name,driver_version' '--format=csv,noheader')
    if($LASTEXITCODE -or $rows.Count -ne 1){throw 'This preview requires the validated single-GPU configuration.'}
    $parts=$rows[0].Split(',')
    if($parts[0].Trim() -ne 'NVIDIA GeForce RTX 4080' -or $parts[1].Trim() -ne '616.56') {
        throw 'Validated target: RTX 4080 / driver 616.56. Other RTX 40 GPUs and newer drivers need separate validation.'
    }
}
function Get-LegacyProfileLock([string]$Id) {
    if($Id -notin @('1920x1080','2560x1440','3840x2160')){throw 'Unsupported profile.'}
    $lock=Read-Json (Join-Path $PackageRoot 'compatibility/profiles.lock.json')
    $entry=$lock.profiles.$Id
    $count=if($Id -eq '3840x2160'){39}else{43}
    if($lock.schemaVersion -ne 1 -or -not $entry -or $entry.integratedCount -ne $count -or
       $entry.manifestSha256 -notmatch '^[a-f0-9]{64}$' -or $entry.addonSha256 -notmatch '^[a-f0-9]{64}$'){
        throw 'Invalid tested-profile lock.'
    }
    return $entry
}
function Get-ProfileLock {
    $lock=Read-Json (Join-Path $PackageRoot 'compatibility/automatic.lock.json')
    if($lock.schemaVersion -ne 2 -or $lock.profileId -ne 'native-dimension-v1' -or
       $lock.integratedCount -ne 45 -or $lock.manifestSha256 -notmatch '^[a-f0-9]{64}$' -or
       $lock.addonSha256 -notmatch '^[a-f0-9]{64}$'){throw 'Invalid automatic-payload lock.'}
    return $lock
}
function Get-Profile([bool]$VerifyPayload=$true) {
    $lock=Get-ProfileLock
    $dir=Join-Path $PackageRoot 'profiles/automatic'
    $path=Join-Path $dir 'manifest.json'
    if(-not (Test-Path -LiteralPath $path)) {
        throw 'Acceleration payload is not included in the public source preview. Install/Launch require the complete local package; this download alone does not accelerate DLSS5.'
    }
    Assert-PlainPath $dir
    if((Get-Sha $path) -ne $lock.manifestSha256){throw 'Profile manifest is not the pinned tested identity.'}
    $manifest=Read-Json $path
    if($manifest.schemaVersion -ne 2 -or $manifest.profileId -ne 'native-dimension-v1' -or $manifest.mode -ne 2){throw 'Invalid profile manifest.'}
    $names=@($manifest.files.PSObject.Properties.Name)
    $expected=@('ada-nr.addon64','bundle/mode.txt','bundle/frontback-pre.cubin','bundle/frontback-post.cubin')
    $expected+=@(0..($lock.integratedCount-1) | ForEach-Object {'bundle/integrated-{0:d2}.cubin' -f $_})
    if($names.Count -ne $expected.Count -or @(Compare-Object $names $expected).Count -or
       $manifest.files.'ada-nr.addon64' -ne $lock.addonSha256) {
        throw 'Profile file set or addon differs from the tested identity.'
    }
    foreach($file in $manifest.files.PSObject.Properties) {
        if($file.Name -notmatch '^(ada-nr\.addon64|bundle/(mode\.txt|integrated-\d{2}\.cubin|frontback-(pre|post)\.cubin))$' -or
           $file.Value -notmatch '^[a-f0-9]{64}$'){throw 'Invalid payload path or hash.'}
        if($VerifyPayload) {
            $target=Join-Path $dir $file.Name
            Assert-PlainPath $target
            if(-not (Test-Path -LiteralPath $target) -or (Get-Sha $target) -ne $file.Value){throw "Payload mismatch: $($file.Name)"}
        }
    }
    if($VerifyPayload -and (Get-Content -LiteralPath (Join-Path $dir 'bundle/mode.txt') -Raw).Trim() -ne '2'){throw 'Expected optimized mode 2.'}
    return @{root=$dir; manifest=$manifest; sha=$manifest.files.'ada-nr.addon64'}
}
function Install-Profile([string]$Bin) {
    Assert-GameClosed; Assert-Baseline $Bin; Assert-Hardware
    $profile=Get-Profile
    $target=Join-Path $Bin 'ada-nr.addon64'
    $statePath=Join-Path $Bin 'faster-dlss5-install.json'
    if((Test-Path -LiteralPath $target) -or (Test-Path -LiteralPath $statePath)) {
        throw 'An addon or installation record already exists. Remove this installation before installing this version. Unknown files are never overwritten.'
    }
    $state=[ordered]@{schemaVersion=2;profileId='native-dimension-v1';addonSha256=$profile.sha;packageRoot=$PackageRoot;installedUtc=[DateTime]::UtcNow.ToString('o')}
    # Persist intent first. CreateNew and File.Copy(overwrite=false) protect existing files.
    $stream=[IO.File]::Open($statePath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {$bytes=[Text.Encoding]::UTF8.GetBytes(($state | ConvertTo-Json));$stream.Write($bytes,0,$bytes.Length)} finally {$stream.Dispose()}
    [IO.File]::Copy((Join-Path $profile.root 'ada-nr.addon64'),$target,$false)
    if((Get-Sha $target) -ne $profile.sha){throw 'Installed addon hash mismatch; retain the record for recovery.'}
    Write-Host "Installed automatic dimension support. Keep this extracted package in place. Launch through this manager."
}
function Get-Installation([string]$Bin,[bool]$VerifyPayload=$true) {
    $state=Read-Json (Join-Path $Bin 'faster-dlss5-install.json')
    if($state.schemaVersion -ne 2 -or $state.profileId -ne 'native-dimension-v1' -or $state.packageRoot -ne $PackageRoot){throw 'Installation belongs to a different package location.'}
    $profile=Get-Profile $VerifyPayload
    if($state.addonSha256 -ne $profile.sha){throw 'Installation record does not match this package.'}
    return @{state=$state;profile=$profile}
}
function Remove-Profile([string]$Bin,[bool]$RecordOnly=$false) {
    Assert-GameClosed
    $statePath=Join-Path $Bin 'faster-dlss5-install.json'
    Assert-PlainPath $statePath
    $state=Read-Json $statePath
    if($state.schemaVersion -notin @(1,2) -or $state.addonSha256 -notmatch '^[a-f0-9]{64}$'){throw 'Invalid installation record.'}
    $lock=if($state.schemaVersion -eq 1){Get-LegacyProfileLock $state.resolution}else{
        if($state.profileId -ne 'native-dimension-v1'){throw 'Invalid installation record.'}
        Get-ProfileLock
    }
    if($state.addonSha256 -ne $lock.addonSha256){throw 'Installation record is not a known addon identity.'}
    $target=Join-Path $Bin 'ada-nr.addon64'
    Assert-PlainPath $target
    if($RecordOnly) {
        Remove-Item -LiteralPath $statePath
        Write-Host 'Forgot only the installation record. Any addon file is still present; it was not uninstalled.'
        return
    }
    if(Test-Path -LiteralPath $target) {
        if((Get-Sha $target) -ne $state.addonSha256){throw 'Addon changed since installation. Nothing was removed. Use Remove -ForgetRecordOnly only to forget our record and retain that unknown file.'}
        Remove-Item -LiteralPath $target
    }
    Remove-Item -LiteralPath $statePath
    Write-Host 'Removed our addon and installation record. The community installation is unchanged.'
}
function Show-Status([string]$Bin) {
    $install=Get-Installation $Bin
    if((Get-Sha (Join-Path $Bin 'ada-nr.addon64')) -ne $install.profile.sha){throw 'Installed addon identity mismatch.'}
    $bundle=Join-Path $install.profile.root 'bundle'
    $events=Join-Path $bundle 'ada-nr-events.log';$frames=Join-Path $bundle 'ada-nr-frames.csv'
    $stamp=Join-Path $bundle 'launch-time.txt'
    if(-not (Test-Path -LiteralPath $stamp) -or -not (Test-Path -LiteralPath $events) -or -not (Test-Path -LiteralPath $frames)) {
        throw 'No completed launch evidence. Installation alone does not prove acceleration.'
    }
    $launched=[DateTime]::Parse((Get-Content -LiteralPath $stamp -Raw)).ToUniversalTime()
    if((Get-Item -LiteralPath $events).LastWriteTimeUtc -lt $launched -or (Get-Item -LiteralPath $frames).LastWriteTimeUtc -lt $launched){throw 'Logs predate the latest launch.'}
    $log=Get-Content -LiteralPath $events -Raw
    if($log -notmatch 'hook,1,mode,2' -or $log -notmatch 'evaluate_hook,1' -or $log -match 'failed|sequence_fallback') {
        throw 'The latest launch has no clean optimizer hook evidence. See its event log.'
    }
    $rows=@(Import-Csv -LiteralPath $frames)
    $observed=@($rows | ForEach-Object {"$($_.width)x$($_.height)"} | Sort-Object -Unique)
    $bad=@($rows | Where-Object {
        $_.optimized -ne '1' -or $_.replaced -ne '145' -or $_.guard_failed -ne '0' -or $_.launch_errors -ne '0' -or
        $_.surface_failed -ne '0' -or $_.width -notmatch '^[1-9][0-9]{0,4}$' -or
        $_.height -notmatch '^[1-9][0-9]{0,4}$' -or [long]$_.width -gt 16384 -or [long]$_.height -gt 16384 -or
        $_.output_format -notin @('28','10') -or
        -not (($_.frontback -eq '2' -and $_.history_native -eq '0') -or ($_.frontback -eq '0' -and $_.history_native -eq '2'))
    })
    if(-not $rows.Count -or $bad.Count){throw "Incomplete or failed routing evidence: $($bad.Count) bad / $($rows.Count) complete graphs."}
    Write-Host "Latest launch: $($rows.Count) complete graphs passed routing checks (observed NR sizes: $($observed -join ", ")). This checks routing, not image quality or GPU time."
}
function Start-OptimizedGame([string]$Bin) {
    Assert-GameClosed; Assert-Baseline $Bin; Assert-Hardware
    $install=Get-Installation $Bin
    if((Get-Sha (Join-Path $Bin 'ada-nr.addon64')) -ne $install.profile.sha){throw 'Installed addon identity mismatch.'}
    $bundle=Join-Path $install.profile.root 'bundle'
    [IO.File]::WriteAllText((Join-Path $bundle 'launch-time.txt'),[DateTime]::UtcNow.ToString('o'))
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=Join-Path $Bin 'Cyberpunk2077.exe';$start.WorkingDirectory=$Bin;$start.UseShellExecute=$false
    $start.EnvironmentVariables['ADA_NR_BUNDLE']=$bundle
    $process=[Diagnostics.Process]::Start($start)
    Write-Host "Game started (PID $($process.Id)). Use SDR and the matching community NR settings. Dimensions follow the runtime automatically; there is no resolution profile to select."
    Write-Host 'After exiting the game, use Status to verify the optimizer actually ran.'
}
function Invoke-Manager {
    if($Action -eq 'Menu') {
        Write-Host 'Faster DLSS5 for Ada / RTX 40 - experimental package manager'
        Write-Host '1 Check compatibility  2 Install  3 Launch  4 Verify latest run  5 Remove'
        $choice=Read-Host 'Choose 1-5'
        $actions=@{'1'='Check';'2'='Install';'3'='Launch';'4'='Status';'5'='Remove'}
        if(-not $actions.ContainsKey($choice)){throw 'Invalid selection.'};$Action=$actions[$choice]
        $GamePath=Read-Host 'Cyberpunk 2077 installation folder (no quotes)'
    }
    $bin=Get-GameBin $GamePath
    switch($Action) {
        'Check' {Assert-Baseline $bin; Assert-Hardware; Write-Host 'The measured game baseline and hardware match.';Get-Profile | Out-Null;Write-Host 'Acceleration payload verified.'}
        'Install' {Install-Profile $bin}
        'Launch' {Start-OptimizedGame $bin}
        'Status' {Show-Status $bin}
        'Remove' {Remove-Profile $bin ([bool]$ForgetRecordOnly)}
    }
}
if($MyInvocation.InvocationName -ne '.') {
    try {Invoke-Manager} catch {Write-Host "Stopped: $($_.Exception.Message)" -ForegroundColor Red;exit 1}
}
