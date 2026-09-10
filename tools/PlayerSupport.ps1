# Player-facing errors and an explicit text-only diagnostic export.
function Get-PlayerError($Failure,[string]$Language='en') {
    $message=$Failure.Exception.Message
    $rules=@(
        @('complete acceleration package','This is the source package. Open Downloads to check the available packages.','这是源码包。请点击“下载”查看可用的安装包。'),
        @('Close the game','Close the game, then click Install / update again.','请先关闭游戏，再点击“安装／更新”。'),
        @('Another installation','Another installer is working. Wait for it to finish, then retry.','另一个安装器正在工作，请等它完成后重试。'),
        @('Select the folder|Community DLSS5 file missing|Cannot find path|does not exist','Choose the folder containing the community DLSS5 addon. Install the community base first if needed.','请重新选择社区 DLSS5 插件所在目录；尚未安装底座时，点击“社区 base”。'),
        @('package file is damaged|Invalid profile|Profile file set|Invalid payload|Expected optimized|Copy incomplete|Addon copy incomplete','Extract a fresh copy of the complete acceleration package and retry.','请重新完整解压加速包，然后重试。'),
        @('Update interrupted; recovery','Automatic recovery could not finish. Keep the recovery folders shown in Details and export diagnostics for help.','自动恢复未能完成。请保留“详细信息”中的恢复目录，并导出诊断反馈。'),
        @('Installation record missing|Invalid installation record|Invalid installed file','The installation record needs attention. Export diagnostics and report the problem.','安装记录需要修复。请导出诊断并反馈问题。'),
        @('Addon changed since installation','The installed addon was changed. Use a complete package to Install / update, then remove the patch.','已安装的加速插件被修改。请使用完整包“安装／更新”后再卸载。'),
        @('Installed package changed|Installation record does not match|Installed addon is missing','Repair the patch by clicking Install / update from a complete acceleration package.','请打开完整加速包，点击“安装／更新”修复补丁。'),
        @('Linked paths','Choose the actual plugin folder instead of a linked folder.','请选择插件的实际目录，而不是链接目录。'),
        @('denied|UnauthorizedAccess|0x80070005','Windows could not write to the selected location. Check its folder permissions or choose a writable export location.','Windows 无法写入所选位置。请检查该目录的写入权限；导出诊断时可改选桌面等可写目录。'),
        @('used by another process|being used|0x80070020','A file is in use. Close the game and other installers, then retry.','文件正在使用中。请关闭游戏及其他安装器后重试。'),
        @('already exists','Choose a new filename or an empty destination, then retry.','请换一个未使用的文件名或空目录后重试。')
    )
    $friendly=if($Language -eq 'zh'){'操作未完成。可以重试，或导出诊断并反馈问题。'}else{'This step did not finish. Retry, or export diagnostics and report the problem.'}
    $signature=$message+' '+$Failure.Exception.ToString()
    foreach($rule in $rules){if($signature -match $rule[0]){$friendly=$rule[$(if($Language -eq 'zh'){2}else{1})];break}}
    return @{message=$friendly;details=$message}
}
function Protect-DiagnosticText([string]$Text,[string]$Bin) {
    foreach($path in @($Bin,$PackageRoot,$env:USERPROFILE) | Where-Object {$_} | Sort-Object Length -Descending) {
        $Text=[regex]::Replace($Text,[regex]::Escape($path),'<folder>',[Text.RegularExpressions.RegexOptions]::IgnoreCase)
    }
    # Strip remaining absolute Windows/UNC paths and credential-shaped strings.
    $Text=$Text -replace '(?i)(?:[a-z]:[\\/]|\\\\)[^\r\n,;|"<>]*','<path>'
    $Text=$Text -replace '(?i)(?:github_pat_|gh[pousr]_)[a-z0-9_]+','<redacted>'
    return $Text
}
function Export-Diagnostics([string]$Bin,[string]$OutputPath,[string]$LastError='') {
    Assert-PlainPath $Bin;Assert-PlainPath $OutputPath
    if([IO.Path]::GetExtension($OutputPath) -ne '.zip'){throw 'Choose a new filename ending in .zip.'}
    $summary=[ordered]@{collectedUtc=[DateTime]::UtcNow.ToString('o');os=[Environment]::OSVersion.VersionString;status='unavailable';lastError=$LastError}
    try {
        $status=Get-AccelerationStatus $Bin
        $summary.status=$status.code;$summary.acceleratedFrames=$status.graphs;$summary.lastRecordedRun=$status.lastRun
    } catch {$summary.statusError=$_.Exception.Message}
    $statePath=Join-Path $Bin 'faster-dlss5-install.json';Assert-PlainPath $statePath
    if(Test-Path -LiteralPath $statePath) {
        try {$state=Read-Json $statePath;$summary.profile=$state.profileId;$summary.installedUtc=$state.installedUtc;$summary.addonIdentity=$state.addonSha256}
        catch {$summary.recordError=$_.Exception.Message}
    }
    $summary.community=@()
    foreach($name in @('renodx-dlss5.addon64','nvngx_dlssnr.dll')) {
        $path=Join-Path $Bin $name;Assert-PlainPath $path
        if(Test-Path -LiteralPath $path -PathType Leaf) {
            $file=Get-Item -LiteralPath $path
            $summary.community+=@{file=$name;bytes=$file.Length;version=$file.VersionInfo.FileVersion}
        }
    }
    try {$summary.gpu=@(Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion)} catch {$summary.gpu='unavailable'}
    $summary.environmentOverridePresent=[bool]$env:ADA_NR_BUNDLE
    $contents=[ordered]@{'summary.json'=($summary|ConvertTo-Json -Depth 6)}
    $bundle=Join-Path $Bin 'faster-dlss5/profiles/automatic/bundle'
    foreach($name in @('ada-nr-events.log','ada-nr-frames.csv')) {
        $path=Join-Path $bundle $name;Assert-PlainPath $path
        if(Test-Path -LiteralPath $path -PathType Leaf) {
            $head=@(Get-Content -LiteralPath $path -TotalCount 1)
            $tail=@(Get-Content -LiteralPath $path -Tail 2000)
            # Keep a CSV header even when the beginning is outside the tail.
            if($name -like '*.csv' -and $tail.Count -and $tail[0] -ne $head[0]){$tail=$head+$tail}
            $contents[$name]=$tail -join "`r`n"
        }
    }
    $contents['README.txt']='Recent log tails and installation status. Absolute local paths are redacted. Review these text files before attaching the ZIP to an issue. GPU binaries and model data are not collected.'
    Add-Type -AssemblyName System.IO.Compression
    $stream=[IO.File]::Open($OutputPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {
        $zip=New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
        try {
            foreach($name in $contents.Keys) {
                $entry=$zip.CreateEntry($name)
                $writer=New-Object IO.StreamWriter($entry.Open(),(New-Object Text.UTF8Encoding($false)))
                try {$writer.Write((Protect-DiagnosticText $contents[$name] $Bin))} finally {$writer.Dispose()}
            }
        } finally {$zip.Dispose()}
    } finally {$stream.Dispose()}
    return $OutputPath
}
