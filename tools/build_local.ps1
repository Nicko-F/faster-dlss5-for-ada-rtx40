[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$RuntimePath,
    [Parameter(Mandatory=$true)][string]$NgxInclude,
    [string]$CudaBin,
    [string]$Output
)
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if(-not $CudaBin){
    if(-not $env:CUDA_PATH){throw 'Provide -CudaBin pointing to the CUDA Toolkit bin folder, or set CUDA_PATH.'}
    $CudaBin=Join-Path $env:CUDA_PATH 'bin'
}
if(-not $Output){$Output=Join-Path $repo ('build/local-'+[DateTime]::Now.ToString('yyyyMMdd-HHmmss'))}
$Output=[IO.Path]::GetFullPath($Output)
if(Test-Path -LiteralPath $Output){throw 'Choose a new build output folder.'}
$RuntimePath=(Resolve-Path -LiteralPath $RuntimePath).Path
$NgxInclude=(Resolve-Path -LiteralPath $NgxInclude).Path
$CudaBin=(Resolve-Path -LiteralPath $CudaBin).Path
foreach($name in @('ptxas.exe','cuobjdump.exe')){if(-not (Test-Path -LiteralPath (Join-Path $CudaBin $name))){throw "CUDA tool missing: $name"}}
$ptx=Join-Path $Output 'input';$kernels=Join-Path $Output 'kernels';$addon=Join-Path $Output 'addon'
& python (Join-Path $PSScriptRoot 'extract_local_ptx.py') --runtime $RuntimePath --output $ptx --cuobjdump (Join-Path $CudaBin 'cuobjdump.exe')
if($LASTEXITCODE){throw 'Local PTX extraction failed'}
& python (Join-Path $PSScriptRoot 'build_kernels.py') --ptx-dir $ptx --output $kernels --ptxas (Join-Path $CudaBin 'ptxas.exe')
if($LASTEXITCODE){throw 'Kernel build failed'}
& (Join-Path $PSScriptRoot 'build_addon.ps1') -NgxInclude $NgxInclude -Bundle $kernels -Output $addon
& python (Join-Path $PSScriptRoot 'package_accelerator.py') --addon (Join-Path $addon 'ada-nr.addon64') --bundle $kernels --output (Join-Path $Output 'Faster-DLSS5-Ada.zip')
if($LASTEXITCODE){throw 'Local package assembly failed'}
Write-Output "READY: $Output\Faster-DLSS5-Ada.zip"
