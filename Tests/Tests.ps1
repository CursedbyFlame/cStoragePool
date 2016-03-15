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


$files = Get-ChildItem -Path $env:System_DefaultWorkingDirectory -Recurse -Include "cStoragePool*"

new-item -Path $env:System_DefaultWorkingDirectory\ready -ItemType Directory

Copy-Item $files -Destination $env:System_DefaultWorkingDirectory\ready -Recurse