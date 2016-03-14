$DSCModuleName = 'cStoragePool'
$DSCResourceName = 'cStoragePool'

$Splat = @{
    Path = $PSScriptRoot
    ChildPath = "..\..\DSCResources\$DSCResourceName\$DSCResourceName.psm1"
    Resolve = $true
    ErrorAction = 'Stop'
}
$DSCResourceModuleFile = Get-Item -Path (Join-Path @Splat)
Write-Host ($PSVersionTable.PSVersion)
if (Get-Module -Name $DSCResourceName)
{
    Remove-Module -Name $DSCResourceName
}
if (!(Get-Module -Name "Pester"))
{
    Install-Module -Name "Pester"
}

Import-Module -Name $DSCResourceModuleFile.FullName -Force
if (!($env:PSModulePath -like "*C:\PSModule\*"))
{
$env:PSModulePath += ";C:\PSModule\"
}


$ModuleRoot = "C:\PSModule\WindowsPowerShell\Modules\$DSCModuleName"

if (-not (Test-Path -Path $ModuleRoot -PathType Container))
{
    New-Item -Path $ModuleRoot -ItemType Directory | Out-Null
}

Copy-Item -Path "$PSScriptRoot\..\..\*" -Destination $ModuleRoot -Recurse -Force -Exclude '.git'

InModuleScope -ModuleName $DSCResourceName -ScriptBlock {

    Describe 'cStoragePool\Get-TargetResource' {
        $MockParameters = @{
            StoragePoolName = "MockStoragePool"
            VDsNames = 'MockVD1', 'MockVD2'
            NumberOfDisksInPool = 4
            SizeOfDisks = 100GB
        }
        $letter = 'F', 'J', 'H'
        $mockParts = @()
        for ($i=0; $i -lt $letter.Count; $i++)
        {
            $mockPart = [PSCustomObject]@{DriveLetter = $letter[$i]}
            $mockParts += $mockPart
        }

        Context 'Absent should return correctly.' {
            Mock -CommandName Get-StoragePool
            It 'should return Absent' {
                $Result = Get-TargetResource @MockParameters
                $Result.Ensure | Should Be 'Absent'
            }
        }

        Context 'Present should return correctly, as well as all another properties.' {
            Mock -CommandName Get-VirtualDisk -MockWith {
                [PSCustomObject]@{UniqueID = 'FDE00000000000000000000000000000'}
            }
            Mock -CommandName Get-Disk -MockWith {
                [PSCustomObject]@{Number = 4}
            }
            Mock -CommandName Get-StoragePool -MockWith {
                $true
            }
            Mock -CommandName Get-Partition -MockWith {
                $mockParts
            }
            It 'should return Present' {
                $Result = Get-TargetResource @MockParameters
                $Result.Ensure | Should Be 'Present'
                $Result.StoragePoolName | Should Be 'MockStoragePool'
                ($Result.VDsNames -contains 'MockVD1' -and $Result.VDsNames -contains 'MockVD2') | Should Be $true
                $Result.NumberOfDisksInPool | Should Be 4
                $Result.SizeOfDisks | Should Be 100
                ($Result.PartitionsInPool -contains 'F' -and $Result.PartitionsInPool -contains 'J' -and $Result.PartitionsInPool -contains 'H') | Should Be $true
            }
        }
    }

    Describe 'how cStoragePool\Test-TargetResource responds to Ensure = Absent' {
        $MockParameters = @{
            StoragePoolName = "MockStoragePool"
            VDsNames = 'MockVD1', 'MockVD2'
            NumberOfDisksInPool = 4
            SizeOfDisks = 100GB
            Ensure = 'Absent'
        }

        Context 'Storage Pool exist.' {
            Mock -CommandName Get-StoragePool -MockWith {
                $true
            }
            It 'should return false' {
                $Result = Test-TargetResource @MockParameters
                $Result | Should Be $false
            }
        }

        Context 'Storage Pool does not exist' {
            Mock -CommandName Get-StoragePool
            It 'should return true' {
                $Result = Test-TargetResource @MockParameters
                $Result | Should Be $true
            }
        }
    }

    Describe 'how cStoragePool\Test-TargetResource responds to Ensure = Present' {
        $MockParameters = @{
            StoragePoolName = "MockStoragePool"
            VDsNames = 'MockVD1', 'MockVD2'
            NumberOfDisksInPool = 4
            SizeOfDisks = 100GB
            Ensure = 'Present'
        }

        Context 'Storage Pool exist.' {
            Mock -CommandName Get-StoragePool -MockWith {
                $true
            }
            It 'should return true' {
                $Result = Test-TargetResource @MockParameters
                $Result | Should Be $true
            }
        }

        Context 'Storage Pool does not exist' {
            Mock -CommandName Get-StoragePool
            It 'should return false' {
                $Result = Test-TargetResource @MockParameters
                $Result | Should Be $false
            }
        }
    }

    Describe 'how cStoragePool\Set-TargetResource responds to Ensure = Present' {
        
        Context 'Creating just storage pool.' {
            $MockParameters = @{
                StoragePoolName = "MockStoragePool"
                NumberOfDisksInPool = 4
                SizeOfDisks = 100GB
                Ensure = 'Present'
            }
            $MockPhysicalDisk = [ciminstance]::new("MSFT_PhysicalDisk")
            Mock -CommandName Get-StorageSubSystem -MockWith {
                [PSCustomObject]@{UniqueID = '{00000000-0000-0000-0000-000000000000}:SS'}
            }
            Mock -CommandName Get-PhysicalDisk -MockWith {
                $MockPhysicalDisk
            }
            Mock -CommandName Select {
                $MockPhysicalDisk
            }
            Mock -CommandName Where {
                $MockPhysicalDisk
            }
            Mock -CommandName New-StoragePool
            It 'should call expected mocks.' {
                Set-TargetResource @MockParameters
                Assert-MockCalled Get-StorageSubSystem -Exactly 2
                Assert-MockCalled New-StoragePool -Exactly 1
            }
        }

        Context 'Creating storage pool with 1 VD without partitions.' {
            $MockVDsCreationOptions = New-CimInstance -ClassName MSFT_KeyValuePair -Property @{
                VD1InterLeave = 65536
                VD1NumberOfColumns = 4
                VD1ProvisioningType = "Fixed"
                VD1ResiliencySettingName = "Simple"
            } -ClientOnly
            $MockParameters = @{
                StoragePoolName = "MockStoragePool"
                VDsNames = "MockVD1"
                VDsCreationOptions = $MockVDsCreationOptions
                NumberOfDisksInPool = 4
                SizeOfDisks = 100GB
                Ensure = 'Present'
            }
            $MockArray = @{
                StoragePoolFriendlyName = $MockParameters.StoragePoolName
                FriendlyName = $MockParameters.VDsNames
                UseMaximumSize = $true
                InterLeave = 65536
                NumberOfColumns = 4
                ProvisioningType = "Fixed"
                ResiliencySettingName = "Simple"
            }
            $MockPhysicalDisk = [ciminstance]::new("MSFT_PhysicalDisk")
            $MockVirtualDisk = [ciminstance]::new("MSFT_VirtualDisk")
            Mock -CommandName Get-StorageSubSystem -MockWith {
                [PSCustomObject]@{UniqueID = '{00000000-0000-0000-0000-000000000000}:SS'}
            }
            Mock -CommandName Get-PhysicalDisk -MockWith {
                $MockPhysicalDisk
            }
            Mock -CommandName Select {
                $MockPhysicalDisk
            }
            Mock -CommandName Where {
                $MockPhysicalDisk
            }
            Mock -CommandName New-StoragePool
            Mock -CommandName Import-VDsFromUnparsedArray -MockWith {
                $MockArray
            }
            Mock -CommandName New-VirtualDisk
            Mock -CommandName Get-VirtualDisk -MockWith {
                $MockVirtualDisk
            }
            Mock -CommandName Initialize-Disk
            It 'should call expected mocks.' {
                Set-TargetResource @MockParameters
                Assert-MockCalled Get-StorageSubSystem -Exactly 2
                Assert-MockCalled New-StoragePool -Exactly 1
                Assert-MockCalled New-VirtualDisk -Exactly 1
                Assert-MockCalled Get-VirtualDisk -Exactly 1
                Assert-MockCalled Initialize-Disk -Exactly 1
            }
        }

        Context 'Creating storage pool with 2 VD without partitions.' {
            $MockVDsCreationOptions = New-CimInstance -ClassName MSFT_KeyValuePair -Property @{
                VD1InterLeave = 65536
                VD1NumberOfColumns = 4
                VD1ProvisioningType = "Fixed"
                VD1ResiliencySettingName = "Simple"
                VD2InterLeave = 32768
                VD2NumberOfColumns = 4
                VD2ProvisioningType = "Fixed"
                VD2ResiliencySettingName = "Simple"
            } -ClientOnly
            $MockParameters = @{
                StoragePoolName = "MockStoragePool"
                VDsNames = "MockVD1", "MockVD2"
                VDsCreationOptions = $MockVDsCreationOptions
                VDSizeDistribution = 0.5, 0.5
                NumberOfDisksInPool = 4
                SizeOfDisks = 100GB
                Ensure = 'Present'
            }
            $MockArray = @()
            $MockVD1 = @{
                StoragePoolFriendlyName = $MockParameters.StoragePoolName
                FriendlyName = $MockParameters.VDsNames[0]
                Size = 200GB
                InterLeave = 65536
                NumberOfColumns = 4
                ProvisioningType = "Fixed"
                ResiliencySettingName = "Simple"
            }
            $MockVD2 = @{
                StoragePoolFriendlyName = $MockParameters.StoragePoolName
                FriendlyName = $MockParameters.VDsNames[1]
                UseMaximumSize = $true
                InterLeave = 32768
                NumberOfColumns = 4
                ProvisioningType = "Fixed"
                ResiliencySettingName = "Simple"
            }
            $MockArray += $MockVD1
            $MockArray += $MockVD2
            $MockPhysicalDisk = [ciminstance]::new("MSFT_PhysicalDisk")
            $MockVirtualDisk = [ciminstance]::new("MSFT_VirtualDisk")
            Mock -CommandName Get-StorageSubSystem -MockWith {
                [PSCustomObject]@{UniqueID = '{00000000-0000-0000-0000-000000000000}:SS'}
            }
            Mock -CommandName Get-PhysicalDisk -MockWith {
                $MockPhysicalDisk
            }
            Mock -CommandName Select {
                $MockPhysicalDisk
            }
            Mock -CommandName Where {
                $MockPhysicalDisk
            }
            Mock -CommandName New-StoragePool
            Mock -CommandName Import-VDsFromUnparsedArray -MockWith {
                $MockArray
            }
            Mock -CommandName New-VirtualDisk
            Mock -CommandName Get-VirtualDisk -MockWith {
                $MockVirtualDisk
            }
            Mock -CommandName Initialize-Disk
            It 'should call expected mocks.' {
                Set-TargetResource @MockParameters
                Assert-MockCalled Get-StorageSubSystem -Exactly 2
                Assert-MockCalled New-StoragePool -Exactly 1
                Assert-MockCalled New-VirtualDisk -Exactly 2
                Assert-MockCalled Get-VirtualDisk -Exactly 2
                Assert-MockCalled Initialize-Disk -Exactly 2
            }
        }

        Context 'Creating storage pool with 3 VD without partitions.' {
            $MockVDsCreationOptions = New-CimInstance -ClassName MSFT_KeyValuePair -Property @{
                VD1InterLeave = 65536
                VD1NumberOfColumns = 4
                VD1ProvisioningType = "Fixed"
                VD1ResiliencySettingName = "Simple"
                VD2InterLeave = 32768
                VD2NumberOfColumns = 4
                VD2ProvisioningType = "Fixed"
                VD2ResiliencySettingName = "Simple"
                VD3InterLeave = 32768
                VD3NumberOfColumns = 4
                VD3ProvisioningType = "Fixed"
                VD3ResiliencySettingName = "Simple"
            } -ClientOnly
            $MockParameters = @{
                StoragePoolName = "MockStoragePool"
                VDsNames = "MockVD1", "MockVD2", "MockVD3"
                VDsCreationOptions = $MockVDsCreationOptions
                VDSizeDistribution = 100GB, 100GB
                NumberOfDisksInPool = 4
                SizeOfDisks = 100GB
                Ensure = 'Present'
            }
            $MockArray = @()
            $MockVD1 = @{
                StoragePoolFriendlyName = $MockParameters.StoragePoolName
                FriendlyName = $MockParameters.VDsNames[0]
                Size = 100GB
                InterLeave = 65536
                NumberOfColumns = 4
                ProvisioningType = "Fixed"
                ResiliencySettingName = "Simple"
            }
            $MockVD2 = @{
                StoragePoolFriendlyName = $MockParameters.StoragePoolName
                FriendlyName = $MockParameters.VDsNames[1]
                Size = 100GB
                InterLeave = 32768
                NumberOfColumns = 4
                ProvisioningType = "Fixed"
                ResiliencySettingName = "Simple"
            }
            $MockVD3 = @{
                StoragePoolFriendlyName = $MockParameters.StoragePoolName
                FriendlyName = $MockParameters.VDsNames[2]
                UseMaximumSize = $true
                InterLeave = 32768
                NumberOfColumns = 4
                ProvisioningType = "Fixed"
                ResiliencySettingName = "Simple"
            }
            $MockArray += $MockVD1
            $MockArray += $MockVD2
            $MockArray += $MockVD3
            $MockPhysicalDisk = [ciminstance]::new("MSFT_PhysicalDisk")
            $MockVirtualDisk = [ciminstance]::new("MSFT_VirtualDisk")
            $MockStoragePool = New-CimInstance -ClassName MSFT_StoragePool -Property @{
                Size = (($MockParameters.SizeOfDisks * $MockParameters.NumberOfDisksInPool)*0.99)
                AllocatedSize = 0.5GB
            } -ClientOnly
            Mock -CommandName Get-StorageSubSystem -MockWith {
                [PSCustomObject]@{UniqueID = '{00000000-0000-0000-0000-000000000000}:SS'}
            }
            Mock -CommandName Get-PhysicalDisk -MockWith {
                $MockPhysicalDisk
            }
            Mock -CommandName Select {
                $MockPhysicalDisk
            }
            Mock -CommandName Where {
                $MockPhysicalDisk
            }
            Mock -CommandName New-StoragePool
            Mock -CommandName Import-VDsFromUnparsedArray -MockWith {
                $MockArray
            }
            Mock -CommandName New-VirtualDisk
            Mock -CommandName Get-VirtualDisk -MockWith {
                $MockVirtualDisk
            }
            Mock -CommandName Initialize-Disk
            It 'should call expected mocks.' {
                Set-TargetResource @MockParameters
                Assert-MockCalled Get-StorageSubSystem -Exactly 2
                Assert-MockCalled New-StoragePool -Exactly 1
                Assert-MockCalled New-VirtualDisk -Exactly 3
                Assert-MockCalled Get-VirtualDisk -Exactly 3
                Assert-MockCalled Initialize-Disk -Exactly 3
            }
        }

        Context 'Creating storage pool with 1 VD and 2 partitions on it.' {
            $MockVDsCreationOptions = New-CimInstance -ClassName MSFT_KeyValuePair -Property @{
                VD1InterLeave = 65536
                VD1NumberOfColumns = 2
                VD1ProvisioningType = "Fixed"
                VD1ResiliencySettingName = "Simple"
                VD1PartsCount = 2
            } -ClientOnly 
            $MockPartsCreationOptions = New-CimInstance -ClassName MSFT_KeyValuePair -Property @{
                VD1Part1DriveLetter = "F"
                VD1Part1Size = 10GB
                VD1Part1NewFileSystemLabel = "VD1 Part1"
                VD1Part2DriveLetter = "J"
                VD1Part2UseMaximumSize = $true
                VD1Part2NewFileSystemLabel = "VD1 Part2"
                VD1Part2FileSystem = "ReFS"
            } -ClientOnly 
            $MockParameters = @{
                StoragePoolName = "MockStoragePool"
                VDsNames = "MockVD1"
                VDsCreationOptions = $MockVDsCreationOptions
                PartsCreationOptions = $MockPartsCreationOptions
                NumberOfDisksInPool = 4
                SizeOfDisks = 100GB
                Ensure = 'Present'
            }
            $MockParts = @()
            $MockPart1 = @{
                DiskNumber = 4
                DriveLetter = "F"
                Size = 10GB
            }
            $MockPart2 = @{
                DiskNumber = 4
                DriveLetter = "J"
                UseMaximumSize = $true
            }
            $MockParts += $MockPart1
            $MockParts += $MockPart2
            $MockArray = @{
                StoragePoolFriendlyName = "MockStoragePool"
                FriendlyName = "MockVD1"
                InterLeave = 65536
                NumberOfColumns = 4
                ProvisioningType = "Fixed"
                ResiliencySettingName = "Simple"
            }
            $MockPhysicalDisk = [ciminstance]::new("MSFT_PhysicalDisk")
            $Script:VDPartsCount = New-Object 'System.Object[]' -ArgumentList 1
            $Script:VDPartsCount[0] = 2
            $Script:FormatOptions = New-Object 'System.Object[]' -ArgumentList 1
            $FormatOptionsTemp = @()
            $FormatOptionsPart1 = @{
                NewFileSystemLabel = "VD1 Part1"
            }
            $FormatOptionsPart2 = @{
                NewFileSystemLabel = "VD1 Part2"
                FileSystem = "ReFS"
            }
            $FormatOptionsTemp += $FormatOptionsPart1
            $FormatOptionsTemp += $FormatOptionsPart2
            $Script:FormatOptions[0] = $FormatOptionsTemp
            $MockVirtualDisk = New-CimInstance -ClassName MSFT_VirtualDisk -Property @{
                Number = 4
            } -ClientOnly
            Mock -CommandName Get-StorageSubSystem -MockWith {
                [PSCustomObject]@{UniqueID = '{00000000-0000-0000-0000-000000000000}:SS'}
            }
            Mock -CommandName Get-PhysicalDisk -MockWith {
                $MockPhysicalDisk
            }
            Mock -CommandName Select {
                $MockPhysicalDisk
            }
            Mock -CommandName Where {
                $MockPhysicalDisk
            }
            Mock -CommandName New-StoragePool
            Mock -CommandName Import-VDsFromUnparsedArray -MockWith {
                $MockArray
            }
            Mock -CommandName Import-PartsFromUnparsedArray -MockWith {
                $MockParts
            }
            Mock -CommandName New-VirtualDisk
            Mock -CommandName Get-VirtualDisk -MockWith {
                $MockVirtualDisk
            }
            Mock -CommandName Initialize-Disk
            Mock -CommandName New-Partition
            Mock -CommandName Start-Sleep
            Mock -CommandName Format-Volume
            It 'should call expected mocks.' {
                Set-TargetResource @MockParameters
                Assert-MockCalled Get-StorageSubSystem -Exactly 2
                Assert-MockCalled New-StoragePool -Exactly 1
                Assert-MockCalled New-VirtualDisk -Exactly 1
                Assert-MockCalled Get-VirtualDisk -Exactly 1
                Assert-MockCalled Initialize-Disk -Exactly 1
                Assert-MockCalled New-Partition -Exactly 2
                Assert-MockCalled Format-Volume -Exactly 2
            }
        }

        Context 'Creating storage pool with 2 VDs: 2 partitions on first VD and 1 partition on second VD.' {
            $MockVDsCreationOptions = New-CimInstance -ClassName MSFT_KeyValuePair -Property @{
                VD1InterLeave = 65536
                VD1NumberOfColumns = 4
                VD1ProvisioningType = "Fixed"
                VD1ResiliencySettingName = "Simple"
                VD1PartsCount = 2
                VD2InterLeave = 32768
                VD2NumberOfColumns = 4
                VD2ProvisioningType = "Fixed"
                VD2ResiliencySettingName = "Simple"
                VD2PartsCount = 1
            } -ClientOnly 
            $MockPartsCreationOptions = New-CimInstance -ClassName MSFT_KeyValuePair -Property @{
                VD1Part1DriveLetter = "F"
                VD1Part1Size = 10GB
                VD1Part1NewFileSystemLabel = "VD1 Part1"
                VD1Part2DriveLetter = "J"
                VD1Part2UseMaximumSize = $true
                VD1Part2NewFileSystemLabel = "VD1 Part2"
                VD1Part2FileSystem = "ReFS"
                VD2Part1DriveLetter = "E"
                VD2Part1UseMaximumSize = $true
                VD2Part1NewFileSystemLabel = "VD2 Part1"
                VD2Part1FileSystem = "exFAT"
            } -ClientOnly 
            $MockParameters = @{
                StoragePoolName = "MockStoragePool"
                VDsNames = "MockVD1", "MockVD2"
                VDsCreationOptions = $MockVDsCreationOptions
                PartsCreationOptions = $MockPartsCreationOptions
                NumberOfDisksInPool = 4
                VDSizeDistribution = 0.5, 0.5
                SizeOfDisks = 100GB
                Ensure = 'Present'
            }
            $MockParts = New-Object 'System.Object[]' -ArgumentList 2
            $MockPartsVD1 = @()
            $MockPartsVD2 = @()
            $MockPart1 = @{
                DiskNumber = 4
                DriveLetter = "F"
                Size = 10GB
            }
            $MockPart2 = @{
                DiskNumber = 4
                DriveLetter = "J"
                UseMaximumSize = $true
            }
            $MockPart3 = @{
                DiskNumber = 5
                DriveLetter = "E"
                UseMaximumSize = $true
            }
            $MockPartsVD1 += $MockPart1
            $MockPartsVD1 += $MockPart2
            $MockPartsVD2 += $MockPart3
            $MockParts[0] = $MockPartsVD1
            $MockParts[1] = $MockPartsVD2
            $MockVD1 = @{
                StoragePoolFriendlyName = "MockStoragePool"
                FriendlyName = "MockVD1"
                InterLeave = 65536
                NumberOfColumns = 4
                ProvisioningType = "Fixed"
                ResiliencySettingName = "Simple"
            }
            $MockVD2 = @{
                StoragePoolFriendlyName = "MockStoragePool"
                FriendlyName = "MockVD2"
                InterLeave = 32768
                NumberOfColumns = 4
                ProvisioningType = "Fixed"
                ResiliencySettingName = "Simple"
            }
            $MockArray = New-Object 'System.Object[]' -ArgumentList 2
            $MockArray[0] = $MockVD1
            $MockArray[1] = $MockVD2
            $MockPhysicalDisk = [ciminstance]::new("MSFT_PhysicalDisk")
            $Script:VDPartsCount = New-Object 'System.Object[]' -ArgumentList 2
            $Script:VDPartsCount[0] = 2
            $Script:VDPartsCount[1] = 1
            $Script:FormatOptions = New-Object 'System.Object[]' -ArgumentList 2
            $FormatOptionsTemp = @()
            $FormatOptionsTemp2 = @()
            $FormatOptionsPart1 = @{
                NewFileSystemLabel = "VD1 Part1"
            }
            $FormatOptionsPart2 = @{
                NewFileSystemLabel = "VD1 Part2"
                FileSystem = "ReFS"
            }
            $FormatOptionsPart3 = @{
                NewFileSystemLabel = "VD2 Part1"
                FileSystem = "exFAT"
            }
            $FormatOptionsTemp += $FormatOptionsPart1
            $FormatOptionsTemp += $FormatOptionsPart2
            $FormatOptionsTemp2 += $FormatOptionsPart3
            $Script:FormatOptions[0] = $FormatOptionsTemp
            $Script:FormatOptions[1] = $FormatOptionsTemp2
            $MockVirtualDisk = New-CimInstance -ClassName MSFT_VirtualDisk -Property @{
                Number = 4
            } -ClientOnly
            Mock -CommandName Get-StorageSubSystem -MockWith {
                [PSCustomObject]@{UniqueID = '{00000000-0000-0000-0000-000000000000}:SS'}
            }
            Mock -CommandName Get-PhysicalDisk -MockWith {
                $MockPhysicalDisk
            }
            Mock -CommandName Select {
                $MockPhysicalDisk
            }
            Mock -CommandName Where {
                $MockPhysicalDisk
            }
            Mock -CommandName New-StoragePool
            Mock -CommandName Import-VDsFromUnparsedArray -MockWith {
                $MockArray
            }
            Mock -CommandName Import-PartsFromUnparsedArray -MockWith {
                $MockParts
            }
            Mock -CommandName New-VirtualDisk
            Mock -CommandName Get-VirtualDisk -MockWith {
                $MockVirtualDisk
            }
            Mock -CommandName Initialize-Disk
            Mock -CommandName New-Partition
            Mock -CommandName Start-Sleep
            Mock -CommandName Format-Volume
            It 'should call expected mocks.' {
                Set-TargetResource @MockParameters
                Assert-MockCalled Get-StorageSubSystem -Exactly 2
                Assert-MockCalled New-StoragePool -Exactly 1
                Assert-MockCalled New-VirtualDisk -Exactly 2
                Assert-MockCalled Get-VirtualDisk -Exactly 2
                Assert-MockCalled Initialize-Disk -Exactly 2
                Assert-MockCalled New-Partition -Exactly 3
                Assert-MockCalled Format-Volume -Exactly 3
            }
        }

        Context 'Creating storage pool with 3 VDs: 2 partitions on first VD, 1 partition on second VD and 1 partition on third VD.' {
            $MockVDsCreationOptions = New-CimInstance -ClassName MSFT_KeyValuePair -Property @{
                VD1InterLeave = 65536
                VD1NumberOfColumns = 4
                VD1ProvisioningType = "Fixed"
                VD1ResiliencySettingName = "Simple"
                VD1PartsCount = 2
                VD2InterLeave = 32768
                VD2NumberOfColumns = 4
                VD2ProvisioningType = "Fixed"
                VD2ResiliencySettingName = "Simple"
                VD2PartsCount = 1
                VD3InterLeave = 32768
                VD3NumberOfColumns = 2
                VD3ProvisioningType = "Fixed"
                VD3ResiliencySettingName = "Simple"
                VD3PartsCount = 1
            } -ClientOnly 
            $MockPartsCreationOptions = New-CimInstance -ClassName MSFT_KeyValuePair -Property @{
                VD1Part1DriveLetter = "F"
                VD1Part1Size = 10GB
                VD1Part1NewFileSystemLabel = "VD1 Part1"
                VD1Part2DriveLetter = "J"
                VD1Part2UseMaximumSize = $true
                VD1Part2NewFileSystemLabel = "VD1 Part2"
                VD1Part2FileSystem = "ReFS"
                VD2Part1DriveLetter = "E"
                VD2Part1UseMaximumSize = $true
                VD2Part1NewFileSystemLabel = "VD2 Part1"
                VD2Part1FileSystem = "exFAT"
                VD3Part1DriveLetter = "H"
                VD3Part1UseMaximumSize = $true
                VD3Part1NewFileSystemLabel = "VD3 Part1"
                VD3Part1FileSystem = "NTFS"
            } -ClientOnly 
            $MockParameters = @{
                StoragePoolName = "MockStoragePool"
                VDsNames = "MockVD1", "MockVD2", "MockVD3"
                VDsCreationOptions = $MockVDsCreationOptions
                PartsCreationOptions = $MockPartsCreationOptions
                NumberOfDisksInPool = 4
                VDSizeDistribution = 0.33, 0.33, 0.34
                SizeOfDisks = 100GB
                Ensure = 'Present'
            }
            $MockParts = New-Object 'System.Object[]' -ArgumentList 3
            $MockPartsVD1 = @()
            $MockPartsVD2 = @()
            $MockPartsVD3 = @()
            $MockPart1 = @{
                DiskNumber = 4
                DriveLetter = "F"
                Size = 10GB
            }
            $MockPart2 = @{
                DiskNumber = 4
                DriveLetter = "J"
                UseMaximumSize = $true
            }
            $MockPart3 = @{
                DiskNumber = 5
                DriveLetter = "E"
                UseMaximumSize = $true
            }
            $MockPart4 = @{
                DiskNumber = 6
                DriveLetter = "G"
                UseMaximumSize = $true
            }
            $MockPartsVD1 += $MockPart1
            $MockPartsVD1 += $MockPart2
            $MockPartsVD2 += $MockPart3
            $MockPartsVD3 += $MockPart4
            $MockParts[0] = $MockPartsVD1
            $MockParts[1] = $MockPartsVD2
            $MockParts[2] = $MockPartsVD3
            $MockVD1 = @{
                StoragePoolFriendlyName = "MockStoragePool"
                FriendlyName = "MockVD1"
                InterLeave = 65536
                NumberOfColumns = 4
                ProvisioningType = "Fixed"
                ResiliencySettingName = "Simple"
            }
            $MockVD2 = @{
                StoragePoolFriendlyName = "MockStoragePool"
                FriendlyName = "MockVD2"
                InterLeave = 32768
                NumberOfColumns = 4
                ProvisioningType = "Fixed"
                ResiliencySettingName = "Simple"
            }
            $MockVD3 = @{
                StoragePoolFriendlyName = "MockStoragePool"
                FriendlyName = "MockVD3"
                InterLeave = 32768
                NumberOfColumns = 4
                ProvisioningType = "Fixed"
                ResiliencySettingName = "Simple"
            }
            $MockArray = New-Object 'System.Object[]' -ArgumentList 3
            $MockArray[0] = $MockVD1
            $MockArray[1] = $MockVD2
            $MockArray[2] = $MockVD3
            $MockPhysicalDisk = [ciminstance]::new("MSFT_PhysicalDisk")
            $Script:VDPartsCount = New-Object 'System.Object[]' -ArgumentList 3
            $Script:VDPartsCount[0] = 2
            $Script:VDPartsCount[1] = 1
            $Script:VDPartsCount[2] = 1
            $Script:FormatOptions = New-Object 'System.Object[]' -ArgumentList 3
            $FormatOptionsTemp = @()
            $FormatOptionsTemp2 = @()
            $FormatOptionsTemp3 = @()
            $FormatOptionsPart1 = @{
                NewFileSystemLabel = "VD1 Part1"
            }
            $FormatOptionsPart2 = @{
                NewFileSystemLabel = "VD1 Part2"
                FileSystem = "ReFS"
            }
            $FormatOptionsPart3 = @{
                NewFileSystemLabel = "VD2 Part1"
                FileSystem = "exFAT"
            }
            $FormatOptionsPart4 = @{
                NewFileSystemLabel = "VD3 Part1"
                FileSystem = "NTFS"
            }
            $FormatOptionsTemp += $FormatOptionsPart1
            $FormatOptionsTemp += $FormatOptionsPart2
            $FormatOptionsTemp2 += $FormatOptionsPart3
            $FormatOptionsTemp3 += $FormatOptionsPart4
            $Script:FormatOptions[0] = $FormatOptionsTemp
            $Script:FormatOptions[1] = $FormatOptionsTemp2
            $Script:FormatOptions[2] = $FormatOptionsTemp3
            $MockVirtualDisk = New-CimInstance -ClassName MSFT_VirtualDisk -Property @{
                Number = 4
            } -ClientOnly
            Mock -CommandName Get-StorageSubSystem -MockWith {
                [PSCustomObject]@{UniqueID = '{00000000-0000-0000-0000-000000000000}:SS'}
            }
            Mock -CommandName Get-PhysicalDisk -MockWith {
                $MockPhysicalDisk
            }
            Mock -CommandName Select {
                $MockPhysicalDisk
            }
            Mock -CommandName Where {
                $MockPhysicalDisk
            }
            Mock -CommandName New-StoragePool
            Mock -CommandName Import-VDsFromUnparsedArray -MockWith {
                $MockArray
            }
            Mock -CommandName Import-PartsFromUnparsedArray -MockWith {
                $MockParts
            }
            Mock -CommandName New-VirtualDisk
            Mock -CommandName Get-VirtualDisk -MockWith {
                $MockVirtualDisk
            }
            Mock -CommandName Initialize-Disk
            Mock -CommandName New-Partition
            Mock -CommandName Start-Sleep
            Mock -CommandName Format-Volume
            It 'should call expected mocks.' {
                Set-TargetResource @MockParameters
                Assert-MockCalled Get-StorageSubSystem -Exactly 2
                Assert-MockCalled New-StoragePool -Exactly 1
                Assert-MockCalled New-VirtualDisk -Exactly 3
                Assert-MockCalled Get-VirtualDisk -Exactly 3
                Assert-MockCalled Initialize-Disk -Exactly 3
                Assert-MockCalled New-Partition -Exactly 4
                Assert-MockCalled Format-Volume -Exactly 4
            }
        }
    }

    Describe "how cStoragePool\Set-TargetResource responds to Ensure = Absent" {
        
        Context "Deleting Storage Pool with 3 Virtual Disks." {
            $MockParameters = @{
                StoragePoolName = "MockStoragePool"
                VDsNames = "MockVD1", "MockVD2", "MockVD3"
                NumberOfDisksInPool = 4
                SizeOfDisks = 100GB
                Ensure = 'Absent'
            }
            Mock -CommandName Remove-VirtualDisk
            Mock -CommandName Remove-StoragePool
            It 'should call expected mocks.' {
                Set-TargetResource @MockParameters
                Assert-MockCalled Remove-VirtualDisk -Exactly 3
                Assert-MockCalled Remove-StoragePool -Exactly 1
            }
        }
    }

    Describe "how cStoragePool\Import-VDsFromUnparsedArray parse options and parameters." {

        Context "Parsing array of 1 Virtual Disk creation options." {
            $MockVDsCreationOptions = @()
            $MockVDsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1InterLeave"
                value = 65536
            } -key key, value -ClientOnly
            $MockVDsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1NumberOfColumns"
                value = 4
            } -key key, value -ClientOnly
            $MockVDsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1ProvisioningType"
                value = "Fixed"
            } -key key, value -ClientOnly
            $MockVDsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1ResiliencySettingName"
                value = "Simple"
            } -key key, value -ClientOnly
            $MockVDsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1PartsCount"
                value = 2
            } -key key, value -ClientOnly
            $MockParameters = @{
                StoragePoolName = "MockStoragePool"
                VDsNames = "MockVD1"
                VDsCreationOptions = $MockVDsCreationOptions
            }
            $MockStoragePool = New-CimInstance -ClassName MSFT_StoragePool -Property @{
                Size = 396GB
                AllocatedSize = 0.5GB
            } -ClientOnly
            Mock -CommandName Get-StoragePool -MockWith {
                $MockStoragePool
            }
            It 'Resulting values should be right.' {
                $Result = Import-VDsFromUnparsedArray @MockParameters
                for ($i = 0; $i -lt 1; $i++)
                {
                    $Result[($i+1)].FriendlyName | Should Be $MockParameters.VDsNames
                    $Result[($i+1)].StoragePoolFriendlyName | Should Be $MockParameters.StoragePoolName
                    $Result[($i+1)].InterLeave | Should Be ($MockVDsCreationOptions | where key -eq ("VD"+($i+1)+"InterLeave")).value
                    $Result[($i+1)].ProvisioningType | Should Be ($MockVDsCreationOptions | where key -eq ("VD"+($i+1)+"ProvisioningType")).value
                    $Result[($i+1)].ResiliencySettingName | Should Be ($MockVDsCreationOptions | where key -eq ("VD"+($i+1)+"ResiliencySettingName")).value
                    $Result[($i+1)].NumberOfColumns | Should Be ($MockVDsCreationOptions | where key -eq ("VD"+($i+1)+"NumberOfColumns")).value
                }
                $Result[1].UseMaximumSize | Should Be $true
            }
        }
        
        Context "Parsing array of 2 Virtual Disks creation options." {
            $MockVDsCreationOptions = @()
            $MockVDsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1InterLeave"
                value = 65536
            } -key key, value -ClientOnly
            $MockVDsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1NumberOfColumns"
                value = 4
            } -key key, value -ClientOnly
            $MockVDsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1ProvisioningType"
                value = "Fixed"
            } -key key, value -ClientOnly
            $MockVDsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1ResiliencySettingName"
                value = "Simple"
            } -key key, value -ClientOnly
            $MockVDsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1PartsCount"
                value = 2
            } -key key, value -ClientOnly
            $MockVDsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD2InterLeave"
                value = 32768
            } -key key, value -ClientOnly
            $MockVDsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD2NumberOfColumns"
                value = 4
            } -key key, value -ClientOnly
            $MockVDsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD2ProvisioningType"
                value = "Fixed"
            } -key key, value -ClientOnly
            $MockVDsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD2ResiliencySettingName"
                value = "Simple"
            } -key key, value -ClientOnly
            $MockVDsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD2PartsCount"
                value = 1
            } -key key, value -ClientOnly
            $MockParameters = @{
                StoragePoolName = "MockStoragePool"
                VDsNames = "MockVD1", "MockVD2"
                VDsCreationOptions = $MockVDsCreationOptions
                VDSizeDistribution = 100GB
            }
            $MockStoragePool = New-CimInstance -ClassName MSFT_StoragePool -Property @{
                Size = 396GB
                AllocatedSize = 0.5GB
            } -ClientOnly
            Mock -CommandName Get-StoragePool -MockWith {
                $MockStoragePool
            }
            It 'Resulting values should be right.' {
                $Result = Import-VDsFromUnparsedArray @MockParameters
                for ($i = 0; $i -lt 2; $i++)
                {
                    $Result[($i+2)].FriendlyName | Should Be $MockParameters.VDsNames[$i]
                    $Result[($i+2)].StoragePoolFriendlyName | Should Be $MockParameters.StoragePoolName
                    $Result[($i+2)].InterLeave | Should Be ($MockVDsCreationOptions | where key -eq ("VD"+($i+1)+"InterLeave")).value
                    $Result[($i+2)].ProvisioningType | Should Be ($MockVDsCreationOptions | where key -eq ("VD"+($i+1)+"ProvisioningType")).value
                    $Result[($i+2)].ResiliencySettingName | Should Be ($MockVDsCreationOptions | where key -eq ("VD"+($i+1)+"ResiliencySettingName")).value
                    $Result[($i+2)].NumberOfColumns | Should Be ($MockVDsCreationOptions | where key -eq ("VD"+($i+1)+"NumberOfColumns")).value
                }
                $Result[2].Size | Should Be 100GB
                $Result[3].UseMaximumSize | Should Be $true
            }
        }

        Context "Parsing array of 3 Virtual Disks creation options." {
            $MockVDsCreationOptions = @()
            $MockVDsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1InterLeave"
                value = 65536
            } -key key, value -ClientOnly
            $MockVDsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1NumberOfColumns"
                value = 4
            } -key key, value -ClientOnly
            $MockVDsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1ProvisioningType"
                value = "Fixed"
            } -key key, value -ClientOnly
            $MockVDsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1ResiliencySettingName"
                value = "Simple"
            } -key key, value -ClientOnly
            $MockVDsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1PartsCount"
                value = 2
            } -key key, value -ClientOnly
            $MockVDsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD2InterLeave"
                value = 32768
            } -key key, value -ClientOnly
            $MockVDsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD2NumberOfColumns"
                value = 4
            } -key key, value -ClientOnly
            $MockVDsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD2ProvisioningType"
                value = "Fixed"
            } -key key, value -ClientOnly
            $MockVDsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD2ResiliencySettingName"
                value = "Simple"
            } -key key, value -ClientOnly
            $MockVDsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD2PartsCount"
                value = 1
            } -key key, value -ClientOnly
            $MockVDsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD3InterLeave"
                value = 32768
            } -key key, value -ClientOnly
            $MockVDsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD3NumberOfColumns"
                value = 4
            } -key key, value -ClientOnly
            $MockVDsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD3ProvisioningType"
                value = "Fixed"
            } -key key, value -ClientOnly
            $MockVDsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD3ResiliencySettingName"
                value = "Simple"
            } -key key, value -ClientOnly
            $MockVDsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD3PartsCount"
                value = 1
            } -key key, value -ClientOnly
            $MockParameters = @{
                StoragePoolName = "MockStoragePool"
                VDsNames = "MockVD1", "MockVD2", "MockVD3"
                VDsCreationOptions = $MockVDsCreationOptions
                VDSizeDistribution = 0.33, 0.33, 0.34
            }
            $MockStoragePool = New-CimInstance -ClassName MSFT_StoragePool -Property @{
                Size = 396GB
                AllocatedSize = 0.5GB
            } -ClientOnly
            Mock -CommandName Get-StoragePool -MockWith {
                $MockStoragePool
            }
            It 'Resulting values should be right.' {
                $Result = Import-VDsFromUnparsedArray @MockParameters
                for ($i = 0; $i -lt 3; $i++)
                {
                    $Result[($i+3)].FriendlyName | Should Be $MockParameters.VDsNames[$i]
                    $Result[($i+3)].StoragePoolFriendlyName | Should Be $MockParameters.StoragePoolName
                    $Result[($i+3)].InterLeave | Should Be ($MockVDsCreationOptions | where key -eq ("VD"+($i+1)+"InterLeave")).value
                    $Result[($i+3)].ProvisioningType | Should Be ($MockVDsCreationOptions | where key -eq ("VD"+($i+1)+"ProvisioningType")).value
                    $Result[($i+3)].ResiliencySettingName | Should Be ($MockVDsCreationOptions | where key -eq ("VD"+($i+1)+"ResiliencySettingName")).value
                    $Result[($i+3)].NumberOfColumns | Should Be ($MockVDsCreationOptions | where key -eq ("VD"+($i+1)+"NumberOfColumns")).value
                }
                $Result[3].Size | Should Be 130GB
                $Result[4].Size | Should Be 130GB
                $Result[5].UseMaximumSize | Should Be $true
            }
        }
    }

    Describe "how cStoragePool\Import-PartsFromUnparsedArray parse options and parameters" {
        
        Context "Parsing array of creation 1 VD with 2 partitions on it." {
            $MockPartsCreationOptions = @()
            $MockPartsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1Part1DriveLetter"
                value = "F"
            } -key key, value -ClientOnly
            $MockPartsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1Part1Size"
                value = 10GB
            } -key key, value -ClientOnly    
            $MockPartsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1Part1NewFileSystemLabel"
                value = "VD1 Part1"
            } -key key, value -ClientOnly   
            $MockPartsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1Part2DriveLetter"
                value = "J"
            } -key key, value -ClientOnly
            $MockPartsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1Part2UseMaximumSize"
                value = $true
            } -key key, value -ClientOnly
            $MockPartsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1Part2NewFileSystemLabel"
                value = "VD1 Part2"
            } -key key, value -ClientOnly
            $MockPartsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1Part2FileSystem"
                value = "ReFS"
            } -key key, value -ClientOnly
            $MockParameters = @{
                VDsNames = "MockVD1"
                PartsCreationOptions = $MockPartsCreationOptions
            }
            $Script:VDPartsCount = New-Object 'System.Object[]' -ArgumentList 1
            $Script:VDPartsCount[0] = 2
            $MockVirtualDisk = New-CimInstance -ClassName MSFT_VirtualDisk -Property @{
                Number = 4
            } -ClientOnly
            Mock -CommandName Get-VirtualDisk -MockWith {
                $MockVirtualDisk
            }
            Mock -CommandName Get-Disk -MockWith {
                $MockVirtualDisk
            }
            It 'Resulting values should be right.' {
                $Result = Import-PartsFromUnparsedArray @MockParameters
                for ($i=0; $i -lt 1; $i++)
                {
                    for ($l=0; $l -lt 2; $l++)
                    {
                        $Result[($i+2)][$l].DriveLetter | Should Be ($MockPartsCreationOptions | where key -eq ("VD"+($i+1)+"Part"+($l+1)+"DriveLetter")).value
                        $Result[($i+2)][$l].DiskNumber | Should Be 4
                        $Script:FormatOptions[$i][$l].NewFileSystemLabel | Should Be ($MockPartsCreationOptions | where key -eq ("VD"+($i+1)+"Part"+($l+1)+"NewFileSystemLabel")).value
                    }
                }
                $Result[2][0].Size | Should Be 10GB
                $Result[2][1].UseMaximumSize | Should Be $true
                $Script:FormatOptions[0][1].FileSystem | Should Be "ReFS"
            }
        }

        Context "Parsing array of creation 2 VDs: 2 partitions on first VD and 1 partition on second VD." {
            $MockPartsCreationOptions = @()
            $MockPartsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1Part1DriveLetter"
                value = "F"
            } -key key, value -ClientOnly
            $MockPartsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1Part1Size"
                value = 10GB
            } -key key, value -ClientOnly    
            $MockPartsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1Part1NewFileSystemLabel"
                value = "VD1 Part1"
            } -key key, value -ClientOnly   
            $MockPartsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1Part2DriveLetter"
                value = "J"
            } -key key, value -ClientOnly
            $MockPartsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1Part2UseMaximumSize"
                value = $true
            } -key key, value -ClientOnly
            $MockPartsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1Part2NewFileSystemLabel"
                value = "VD1 Part2"
            } -key key, value -ClientOnly
            $MockPartsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1Part2FileSystem"
                value = "ReFS"
            } -key key, value -ClientOnly
            $MockPartsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD2Part1DriveLetter"
                value = "E"
            } -key key, value -ClientOnly
            $MockPartsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD2Part1UseMaximumSize"
                value = $true
            } -key key, value -ClientOnly
            $MockPartsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD2Part1NewFileSystemLabel"
                value = "VD2 Part1"
            } -key key, value -ClientOnly
            $MockPartsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD2Part1FileSystem"
                value = "exFAT"
            } -key key, value -ClientOnly
            $MockParameters = @{
                VDsNames = "MockVD1", "MockVD2"
                PartsCreationOptions = $MockPartsCreationOptions
            }
            $Script:VDPartsCount = New-Object 'System.Object[]' -ArgumentList 2
            $Script:VDPartsCount[0] = 2
            $Script:VDPartsCount[1] = 1
            $MockVirtualDisk = New-CimInstance -ClassName MSFT_VirtualDisk -Property @{
                Number = 4
            } -ClientOnly
            Mock -CommandName Get-VirtualDisk -MockWith {
                $MockVirtualDisk
            }
            Mock -CommandName Get-Disk -MockWith {
                $MockVirtualDisk
            }
            It 'Resulting values should be right.' {
                $Result = Import-PartsFromUnparsedArray @MockParameters
                for ($i=0; $i -lt 1; $i++)
                {
                    for ($l=0; $l -lt $Script:VDPartsCount[$i]; $l++)
                    {
                        $Result[($i+3)][$l].DriveLetter | Should Be ($MockPartsCreationOptions | where key -eq ("VD"+($i+1)+"Part"+($l+1)+"DriveLetter")).value
                        $Result[($i+3)][$l].DiskNumber | Should Be 4
                        $Script:FormatOptions[$i][$l].NewFileSystemLabel | Should Be ($MockPartsCreationOptions | where key -eq ("VD"+($i+1)+"Part"+($l+1)+"NewFileSystemLabel")).value
                    }
                }
                $Result[3][0].Size | Should Be 10GB
                $Result[3][1].UseMaximumSize | Should Be $true
                $Result[4][0].UseMaximumSize | Should Be $true
                $Script:FormatOptions[0][1].FileSystem | Should Be "ReFS"
                $Script:FormatOptions[1][0].FileSystem | Should Be "exFAT"
            }
        }

        Context "Parsing array of creation 3 VDs: 2 partitions on first VD, 1 partition on second VD and 1 partition on thrid VD." {
            $MockPartsCreationOptions = @()
            $MockPartsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1Part1DriveLetter"
                value = "F"
            } -key key, value -ClientOnly
            $MockPartsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1Part1Size"
                value = 10GB
            } -key key, value -ClientOnly    
            $MockPartsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1Part1NewFileSystemLabel"
                value = "VD1 Part1"
            } -key key, value -ClientOnly   
            $MockPartsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1Part2DriveLetter"
                value = "J"
            } -key key, value -ClientOnly
            $MockPartsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1Part2UseMaximumSize"
                value = $true
            } -key key, value -ClientOnly
            $MockPartsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1Part2NewFileSystemLabel"
                value = "VD1 Part2"
            } -key key, value -ClientOnly
            $MockPartsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD1Part2FileSystem"
                value = "ReFS"
            } -key key, value -ClientOnly
            $MockPartsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD2Part1DriveLetter"
                value = "E"
            } -key key, value -ClientOnly
            $MockPartsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD2Part1UseMaximumSize"
                value = $true
            } -key key, value -ClientOnly
            $MockPartsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD2Part1NewFileSystemLabel"
                value = "VD2 Part1"
            } -key key, value -ClientOnly
            $MockPartsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD2Part1FileSystem"
                value = "exFAT"
            } -key key, value -ClientOnly
            $MockPartsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD3Part1DriveLetter"
                value = "G"
            } -key key, value -ClientOnly
            $MockPartsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD3Part1UseMaximumSize"
                value = $true
            } -key key, value -ClientOnly
            $MockPartsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD3Part1NewFileSystemLabel"
                value = "VD3 Part1"
            } -key key, value -ClientOnly
            $MockPartsCreationOptions += New-CimInstance -ClassName MSFT_KeyValuePair -Property @{ 
                key = "VD3Part1FileSystem"
                value = "NTFS"
            } -key key, value -ClientOnly
            $MockParameters = @{
                VDsNames = "MockVD1", "MockVD2", "MockVD2"
                PartsCreationOptions = $MockPartsCreationOptions
            }
            $Script:VDPartsCount = New-Object 'System.Object[]' -ArgumentList 3
            $Script:VDPartsCount[0] = 2
            $Script:VDPartsCount[1] = 1
            $Script:VDPartsCount[2] = 1
            $MockVirtualDisk = New-CimInstance -ClassName MSFT_VirtualDisk -Property @{
                Number = 4
            } -ClientOnly
            Mock -CommandName Get-VirtualDisk -MockWith {
                $MockVirtualDisk
            }
            Mock -CommandName Get-Disk -MockWith {
                $MockVirtualDisk
            }
            It 'Resulting values should be right.' {
                $Result = Import-PartsFromUnparsedArray @MockParameters
                for ($i=0; $i -lt 1; $i++)
                {
                    for ($l=0; $l -lt $Script:VDPartsCount[$i]; $l++)
                    {
                        $Result[($i+4)][$l].DriveLetter | Should Be ($MockPartsCreationOptions | where key -eq ("VD"+($i+1)+"Part"+($l+1)+"DriveLetter")).value
                        $Result[($i+4)][$l].DiskNumber | Should Be 4
                        $Script:FormatOptions[$i][$l].NewFileSystemLabel | Should Be ($MockPartsCreationOptions | where key -eq ("VD"+($i+1)+"Part"+($l+1)+"NewFileSystemLabel")).value
                    }
                }
                $Result[4][0].Size | Should Be 10GB
                $Result[4][1].UseMaximumSize | Should Be $true
                $Result[5][0].UseMaximumSize | Should Be $true
                $Result[6][0].UseMaximumSize | Should Be $true
                $Script:FormatOptions[0][1].FileSystem | Should Be "ReFS"
                $Script:FormatOptions[1][0].FileSystem | Should Be "exFAT"
                $Script:FormatOptions[2][0].FileSystem | Should Be "NTFS"
            }
        }
    }
}