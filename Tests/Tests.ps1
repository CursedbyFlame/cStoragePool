$DSCModuleName = 'cStoragePool'
$DSCResourceName = 'cStoragePool'

$Splat = @{
    Path = $PSScriptRoot
    ChildPath = "..\DSCResources\$DSCResourceName\$DSCResourceName.psm1"
    Resolve = $true
    ErrorAction = 'Stop'
}
$DSCResourceModuleFile = Get-Item -Path (Join-Path @Splat)

if (Get-Module -Name $DSCResourceName)
{
    Remove-Module -Name $DSCResourceName
}

Import-Module -Name $DSCResourceModuleFile.FullName -Force
if (!(Get-Module -Name Pester))
{
    Import-Module -Name "$env:System_DefaultWorkingDirectory\Pester\3.3.5\pester.psm1" -Force
}

Invoke-Pester -Script "$env:System_DefaultWorkingDirectory\tests\unit\cStoragePool.Tests.ps1" -EnableExit


$path = $env:System_DefaultWorkingDirectory

$DestinationDirectory = "$path\ready"
$files = Get-ChildItem -Path $path\* -Recurse

if (!(Test-Path -Path $DestinationDirectory))
{
    new-item -Path $DestinationDirectory -ItemType Directory
}
#comment
foreach ($file in $files)
{
    if ($file.FullName -notmatch "Pester" -and $file.FullName -notmatch "ready" -and $file.FullName -notmatch "ApplyVersionToAssemblies")
    {
       $CopyPath = Join-Path $DestinationDirectory $file.FullName.Substring($path.length)
       Copy-Item $file.FullName -Destination $CopyPath
    }
}
