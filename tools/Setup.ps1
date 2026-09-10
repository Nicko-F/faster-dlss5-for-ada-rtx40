# Built-in Windows interface; no Python, CUDA Toolkit or administrator launch required.
param([switch]$ValidateOnly)
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
$strings=@{
 en=@{intro='Install the acceleration patch over your working community DLSS5 setup.';folder='Game or community addon folder';browse='Browse...';install='Install acceleration';status='Check status';remove='Remove patch';logs='Open diagnostics';base='Community base / setup guide';ready='Choose your game folder, then click Install acceleration.';
 installed='Installed. Start your game from Steam or your usual launcher. You can delete the downloaded package.';
 active='Acceleration worked in the last recorded game session.';'not-installed'='Acceleration is not installed here.';
 waiting='The addon has loaded and is waiting for DLSS5 frames.';partial='Some work used the community path. Open diagnostics for details.';
 first='Installed. Start the game and enable community DLSS5, then check here.';removed='Acceleration removed. Continue using your community DLSS5 setup.';
 error='Could not finish this step: ';select='Select a game folder or the folder containing renodx-dlss5.addon64.';
 override='An ADA_NR_BUNDLE environment setting is selecting another bundle: ';nodata='Run the game with DLSS5 first.';close='Close';frames='Accelerated frames: '}
 zh=@{intro='为已正常运行的社区 DLSS5 安装加速补丁。';folder='游戏目录或社区插件目录';browse='浏览…';install='安装加速补丁';status='检查生效状态';remove='卸载补丁';logs='打开诊断目录';base='社区 base / 安装说明';ready='选择游戏目录，然后点击“安装加速补丁”。';
 installed='安装完成。照常从 Steam 或原启动器开游戏即可；下载的解压目录可以删除。';
 active='最近记录的游戏运行中，加速已生效。';'not-installed'='此目录尚未安装加速补丁。';
 waiting='插件已加载，正在等待 DLSS5 画面。';partial='部分计算走了社区路径，可打开诊断目录查看原因。';
 first='补丁已安装。进入游戏并开启社区 DLSS5 后，再来检查生效状态。';removed='加速补丁已卸载，可继续使用原社区 DLSS5。';
 error='这一步未完成：';select='请选择游戏目录，或包含 renodx-dlss5.addon64 的目录。';
 override='检测到 ADA_NR_BUNDLE 环境设置，它会选择另一份内核包：';nodata='请先运行游戏并开启 DLSS5。';close='关闭';frames='已加速帧数：'}
}
function T([string]$Key){$strings[$script:language][$Key]}
function Save-PlayerSettings {
    [IO.Directory]::CreateDirectory((Split-Path -Parent $settingsPath))|Out-Null
    [IO.File]::WriteAllText($settingsPath,(@{folder=$pathBox.Text;language=$script:language}|ConvertTo-Json),[Text.Encoding]::UTF8)
}
$form=New-Object Windows.Forms.Form
$form.Text='Faster DLSS5 for Ada / RTX 40';$form.ClientSize=New-Object Drawing.Size(700,390)
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
$output=New-Object Windows.Forms.TextBox;$output.SetBounds(22,216,658,98);$output.Multiline=$true;$output.ReadOnly=$true;$output.ScrollBars='Vertical';$output.BackColor=[Drawing.SystemColors]::Window
$base=New-Object Windows.Forms.LinkLabel;$base.SetBounds(22,330,360,27)
$logs=New-Object Windows.Forms.Button;$logs.SetBounds(466,330,214,34)
$form.Controls.AddRange(@($intro,$lang,$folder,$pathBox,$browse,$install,$status,$remove,$output,$base,$logs))
function Update-Labels {
    $intro.Text=T 'intro';$folder.Text=T 'folder';$browse.Text=T 'browse';$install.Text=T 'install'
    $status.Text=T 'status';$remove.Text=T 'remove';$base.Text=T 'base';$logs.Text=T 'logs';$output.Text=T 'ready'
}
function Invoke-PlayerAction([string]$Kind) {
    $form.UseWaitCursor=$true
    foreach($button in @($install,$status,$remove)){$button.Enabled=$false}
    try {
        $bin=Get-GameBin $pathBox.Text;$pathBox.Text=$bin
        if($Kind -ne 'Remove'){Save-PlayerSettings}
        switch($Kind) {
            'Install' {Install-Profile $bin;$output.Text=T 'installed'}
            'Remove' {$script:RecoveryPath=$null;Remove-Profile $bin;$output.Text=T 'removed';if($script:RecoveryPath){$output.AppendText("`r`n"+$script:RecoveryPath)}}
            'Status' {
                $result=Get-AccelerationStatus $bin
                $key=if($result.code -eq 'installed'){'first'}else{$result.code}
                $output.Text=T $key
                if($result.graphs){$output.AppendText("`r`n"+(T 'frames')+$result.graphs)}
                if($result.lastRun){$output.AppendText("`r`n"+$result.lastRun.ToString())}
            }
        }
        if($env:ADA_NR_BUNDLE){$output.AppendText("`r`n"+(T 'override')+$env:ADA_NR_BUNDLE)}
    } catch {$output.Text=(T 'error')+$_.Exception.Message}
    finally {$form.UseWaitCursor=$false;foreach($button in @($install,$status,$remove)){$button.Enabled=$true}}
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
$logs.Add_Click({
    try {
        $bin=Get-GameBin $pathBox.Text;$result=Get-AccelerationStatus $bin
        if($result.bundle -and (Test-Path -LiteralPath $result.bundle)){Start-Process explorer.exe -ArgumentList ('"'+$result.bundle+'"')|Out-Null}
        else {$output.Text=T 'nodata'}
    }catch{$output.Text=(T 'error')+$_.Exception.Message}
})
Update-Labels
if($ValidateOnly){
    foreach($language in @('en','zh')){$script:language=$language;Update-Labels;if(-not $install.Text -or -not $intro.Text){throw 'Missing UI translation'}}
    Write-Output 'PASS: bilingual form construction and labels.';$form.Dispose();return
}
[void]$form.ShowDialog();$form.Dispose()
