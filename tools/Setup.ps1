# Built-in Windows interface; no Python, CUDA Toolkit or administrator launch required.
param([switch]$ValidateOnly,[string]$PreviewDirectory)
. (Join-Path $PSScriptRoot 'Manage.ps1')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$settingsPath=Join-Path $PackageRoot 'build/player-settings.json'
$script:language=if([Globalization.CultureInfo]::CurrentUICulture.Name -like 'zh*'){'zh'}else{'en'}
$remembered=''
if(Test-Path -LiteralPath $settingsPath) {
    try {$saved=Read-Json $settingsPath;$remembered=$saved.folder;if($saved.language -in @('en','zh')){$script:language=$saved.language}}catch{}
}
if(-not $remembered) {
    $near=Split-Path -Parent $PackageRoot
    if(Test-Path -LiteralPath (Join-Path $near 'renodx-dlss5.addon64')){$remembered=$near}
}
$script:lastError=''
$script:completePackage=Test-Path -LiteralPath (Join-Path $PackageRoot 'profiles/automatic/manifest.json')
$strings=@{
 en=@{intro='Install the acceleration patch over your working community DLSS5 setup.';folder='Game or community addon folder';browse='Browse...';install='Install / update';status='Check status';remove='Remove patch';logs='Open diagnostics';base='Community base / setup guide';ready='Choose your game folder, then click Install / update.';
 installed='Installed. Start your game from Steam or your usual launcher. You can delete the downloaded package.';
 active='Acceleration worked in the last recorded game session.';'not-installed'='Acceleration is not installed here.';
 waiting='Last recorded status: addon loaded, waiting for DLSS5 frames.';partial='The last recorded run used the community path for some work. Export diagnostics to report it.';
 first='Installed. Start the game and enable community DLSS5, then check here.';removed='Acceleration removed. Continue using your community DLSS5 setup.';
 error='Could not finish this step: ';select='Select a game folder or the folder containing renodx-dlss5.addon64.';
 override='An ADA_NR_BUNDLE environment setting is selecting another bundle: ';nodata='Run the game with DLSS5 first.';close='Close';frames='Accelerated frames: '}
 zh=@{intro='为已正常运行的社区 DLSS5 安装加速补丁。';folder='游戏目录或社区插件目录';browse='浏览…';install='安装／更新';status='检查生效状态';remove='卸载补丁';logs='打开诊断目录';base='社区 base / 安装说明';ready='选择游戏目录，然后点击“安装／更新”。';
 installed='安装完成。照常从 Steam 或原启动器开游戏即可；下载的解压目录可以删除。';
 active='最近记录的游戏运行中，加速已生效。';'not-installed'='此目录尚未安装加速补丁。';
 waiting='最近记录的状态：插件已加载，正在等待 DLSS5 画面。';partial='最近记录的运行中，部分计算使用了社区路径。可导出诊断反馈。';
 first='补丁已安装。进入游戏并开启社区 DLSS5 后，再来检查生效状态。';removed='加速补丁已卸载，可继续使用原社区 DLSS5。';
 error='这一步未完成：';select='请选择游戏目录，或包含 renodx-dlss5.addon64 的目录。';
 override='检测到 ADA_NR_BUNDLE 环境设置，它会选择另一份内核包：';nodata='请先运行游戏并开启 DLSS5。';close='关闭';frames='已加速帧数：'}
}
$extra=@{
    source=@('Source tools loaded. Open Downloads for available packages. Installation uses the complete acceleration package.','当前打开的是源码工具。点击“下载”查看可用包，安装需使用完整加速包。')
    downloads=@('Downloads','下载')
    export=@('Export diagnostics','导出诊断')
    report=@('Report a problem','反馈问题')
    details=@('Show / hide details','展开／收起详细信息')
    saved=@('Diagnostics saved. Review the ZIP and attach it using Report a problem.','诊断已保存。查看 ZIP 内容后，可通过“反馈问题”附上文件。')
    backup=@('Previous installation saved to: ','旧安装已保存至：')
    timestamp=@('Last record (local time): ','最近记录时间（本地）：')
    preference=@('The folder preference could not be saved; the operation succeeded.','目录偏好未能保存，本次操作已完成。')
}
foreach($key in $extra.Keys){$strings.en[$key]=$extra[$key][0];$strings.zh[$key]=$extra[$key][1]}
function T([string]$Key){$strings[$script:language][$Key]}
function Save-PlayerSettings {
    [IO.Directory]::CreateDirectory((Split-Path -Parent $settingsPath))|Out-Null
    [IO.File]::WriteAllText($settingsPath,(@{folder=$pathBox.Text;language=$script:language}|ConvertTo-Json),[Text.Encoding]::UTF8)
}
$form=New-Object Windows.Forms.Form
$form.Text='Faster DLSS5 for Ada / RTX 40';$form.ClientSize=New-Object Drawing.Size(700,480)
$form.StartPosition='CenterScreen';$form.FormBorderStyle='FixedDialog';$form.MaximizeBox=$false
$form.Font=New-Object Drawing.Font('Segoe UI',10)
$intro=New-Object Windows.Forms.Label;$intro.SetBounds(22,24,550,48)
$lang=New-Object Windows.Forms.ComboBox;$lang.SetBounds(572,22,108,28);$lang.DropDownStyle='DropDownList'
[void]$lang.Items.AddRange(@('English','简体中文'));$lang.SelectedIndex=if($script:language -eq 'zh'){1}else{0}
$folder=New-Object Windows.Forms.Label;$folder.SetBounds(22,82,600,23)
$pathBox=New-Object Windows.Forms.TextBox;$pathBox.SetBounds(22,110,544,29);$pathBox.Text=$remembered
$browse=New-Object Windows.Forms.Button;$browse.SetBounds(576,108,104,32)
$install=New-Object Windows.Forms.Button;$install.SetBounds(22,158,208,42)
$status=New-Object Windows.Forms.Button;$status.SetBounds(244,158,208,42)
$remove=New-Object Windows.Forms.Button;$remove.SetBounds(466,158,214,42)
$output=New-Object Windows.Forms.TextBox;$output.SetBounds(22,216,658,110);$output.Multiline=$true;$output.ReadOnly=$true;$output.ScrollBars='Vertical';$output.BackColor=[Drawing.SystemColors]::Window
$detailLink=New-Object Windows.Forms.LinkLabel;$detailLink.SetBounds(22,336,400,26)
$detailBox=New-Object Windows.Forms.TextBox;$detailBox.SetBounds(22,368,658,130);$detailBox.Multiline=$true;$detailBox.ReadOnly=$true;$detailBox.ScrollBars='Both';$detailBox.Visible=$false
$footer=New-Object Windows.Forms.Panel;$footer.SetBounds(22,382,658,85);$footer.Anchor='Left,Right,Bottom'
$base=New-Object Windows.Forms.LinkLabel;$base.SetBounds(0,0,340,26)
$downloads=New-Object Windows.Forms.LinkLabel;$downloads.SetBounds(445,0,208,26)
$logs=New-Object Windows.Forms.Button;$logs.SetBounds(0,36,208,36)
$export=New-Object Windows.Forms.Button;$export.SetBounds(222,36,208,36)
$report=New-Object Windows.Forms.Button;$report.SetBounds(444,36,214,36)
$footer.Controls.AddRange(@($base,$downloads,$logs,$export,$report))
$form.Controls.AddRange(@($intro,$lang,$folder,$pathBox,$browse,$install,$status,$remove,$output,$detailLink,$detailBox,$footer))
function Update-Labels {
    $intro.Text=T 'intro';$folder.Text=T 'folder';$browse.Text=T 'browse';$install.Text=T 'install'
    $status.Text=T 'status';$remove.Text=T 'remove';$base.Text=T 'base';$logs.Text=T 'logs'
    $export.Text=T 'export';$report.Text=T 'report';$downloads.Text=T 'downloads';$detailLink.Text=T 'details'
    $install.Enabled=$script:completePackage
    $output.Text=if($script:completePackage){T 'ready'}else{T 'source'}
}
function Show-PlayerFailure($Failure) {
    $errorText=Get-PlayerError $Failure $script:language
    $output.Text=$errorText.message;$detailBox.Text=$errorText.details;$script:lastError=$errorText.details
}
function Show-PlayerStatus([string]$Bin) {
    $result=Get-AccelerationStatus $Bin
    $key=if($result.code -eq 'installed'){'first'}else{$result.code}
    $output.Text=T $key
    if($result.graphs){$output.AppendText("`r`n"+(T 'frames')+$result.graphs)}
    if($result.lastRun){$output.AppendText("`r`n"+(T 'timestamp')+$result.lastRun.ToString('yyyy-MM-dd HH:mm:ss'))}
}
function Invoke-PlayerAction([string]$Kind) {
    $form.UseWaitCursor=$true
    foreach($button in @($install,$status,$remove,$export)){$button.Enabled=$false}
    try {
        $bin=Get-GameBin $pathBox.Text;$pathBox.Text=$bin
        switch($Kind) {
            'Install' {
                Install-Profile $bin;$output.Text=T 'installed'
                if($script:BackupPath){$output.AppendText("`r`n"+(T 'backup')+$script:BackupPath)}
            }
            'Remove' {$script:RecoveryPath=$null;Remove-Profile $bin;$output.Text=T 'removed';if($script:RecoveryPath){$output.AppendText("`r`n"+$script:RecoveryPath)}}
            'Status' {
                Show-PlayerStatus $bin
            }
        }
        $detailBox.Text='';$script:lastError=''
        if($Kind -ne 'Remove') {
            try {Save-PlayerSettings} catch {$output.AppendText("`r`n"+(T 'preference'))}
        }
        if($env:ADA_NR_BUNDLE){$output.AppendText("`r`n"+(T 'override')+$env:ADA_NR_BUNDLE)}
    } catch {Show-PlayerFailure $_}
    finally {$form.UseWaitCursor=$false;foreach($button in @($status,$remove,$export)){$button.Enabled=$true};$install.Enabled=$script:completePackage}
}
$lang.Add_SelectedIndexChanged({$script:language=if($lang.SelectedIndex -eq 1){'zh'}else{'en'};Update-Labels})
$browse.Add_Click({
    $picker=New-Object Windows.Forms.FolderBrowserDialog;$picker.Description=T 'select';$picker.ShowNewFolderButton=$false
    if(Test-Path -LiteralPath $pathBox.Text -PathType Container){$picker.SelectedPath=$pathBox.Text}
    if($picker.ShowDialog($form) -eq 'OK'){$pathBox.Text=$picker.SelectedPath}
    $picker.Dispose()
})
$install.Add_Click({Invoke-PlayerAction 'Install'});$status.Add_Click({Invoke-PlayerAction 'Status'});$remove.Add_Click({Invoke-PlayerAction 'Remove'})
$base.Add_LinkClicked({[Diagnostics.Process]::Start('https://github.com/RankFTW/rhi-repo')|Out-Null})
$downloads.Add_LinkClicked({[Diagnostics.Process]::Start('https://github.com/Nicko-F/faster-dlss5-for-ada-rtx40/releases/latest')|Out-Null})
$report.Add_Click({[Diagnostics.Process]::Start('https://github.com/Nicko-F/faster-dlss5-for-ada-rtx40/issues/new?template=problem.yml')|Out-Null})
$detailLink.Add_LinkClicked({$detailBox.Visible=-not $detailBox.Visible;$form.ClientSize=New-Object Drawing.Size(700,$(if($detailBox.Visible){630}else{480}))})
$export.Add_Click({
    $picker=New-Object Windows.Forms.SaveFileDialog
    $picker.Filter='ZIP (*.zip)|*.zip';$picker.FileName='Faster-DLSS5-diagnostics-'+[DateTime]::Now.ToString('yyyyMMdd-HHmmss')+'.zip'
    try {
        $bin=Get-GameBin $pathBox.Text
        if($picker.ShowDialog($form) -eq 'OK') {
            $form.UseWaitCursor=$true
            Export-Diagnostics $bin $picker.FileName $script:lastError|Out-Null
            $output.Text=(T 'saved')+"`r`n"+$picker.FileName
        }
    } catch {Show-PlayerFailure $_} finally {$picker.Dispose();$form.UseWaitCursor=$false}
})
$logs.Add_Click({
    try {
        $bin=Get-GameBin $pathBox.Text;$result=Get-AccelerationStatus $bin
        if($result.bundle -and (Test-Path -LiteralPath $result.bundle)){Start-Process explorer.exe -ArgumentList ('"'+$result.bundle+'"')|Out-Null}
        else {$output.Text=T 'nodata'}
    }catch{Show-PlayerFailure $_}
})
Update-Labels
if($ValidateOnly){
    foreach($language in @('en','zh')) {
        $lang.SelectedIndex=if($language -eq 'zh'){1}else{0}
        $script:language=$language;Update-Labels
        if(-not $install.Text -or -not $intro.Text -or -not $export.Text){throw 'Missing UI translation'}
        if($PreviewDirectory) {
            [IO.Directory]::CreateDirectory($PreviewDirectory)|Out-Null
            $form.ShowInTaskbar=$false;$form.Opacity=0;$form.Show()
            [Windows.Forms.Application]::DoEvents()
            $bitmap=New-Object Drawing.Bitmap($form.Width,$form.Height)
            try {$form.DrawToBitmap($bitmap,(New-Object Drawing.Rectangle(0,0,$form.Width,$form.Height)));$bitmap.Save((Join-Path $PreviewDirectory ($language+'.png')))} finally {$bitmap.Dispose()}
        }
    }
    Write-Output 'PASS: bilingual form construction and labels.';$form.Dispose();return
}
[void]$form.ShowDialog();$form.Dispose()
