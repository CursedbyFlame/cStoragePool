# cStoragePool

The **cStoragePool** module contains a single DSC resource **cStoragePool**. 
This module has been writen for specific purpose: creating Storage Pools (which is MS recommendation) on Azure VMs to achieve better performance of storage subsystem.
And it's designed to create Storage Pools with or without Virtual Disks and Partitions in it.

## Resources

### cStoragePool

This resource provide following parameters:
- **StoragePoolName**: the name of the Storage Pool you wish to create.
- **VDsNames**: names of the Virtual Disks you'd like to see in this Storage Pool.
- **SizeOfDisks**: size of disks wich to include in Storage Pool.
- **NumberOfDisksInPool**: quantity of disks in Storage Pool.
- **VDSizeDistribution**: Storage Pool size distribution between Virtual Disks in it. Can be of two types:
  1. ***Direct notation*** - it means that you specify size in **GB**'s.
  2. ***Percentage notation*** - it means that you specify size as percent of whole size of Storage Pool.
  Use **0.X** recording to do that. (*Example*: 0.5, 0.5)
- **VDsCreationOptions**: options to create Virtual Disks with. You need to pass an hashtable to this parameter.
You need to use the following syntax in here: *VDxSomeOption* = *SomeValue*, where
  * x is a Virtual Disk number, according to **VDsNames** Parameter (VD Name specified on first position,
  will have number 1, second - number 2, etc.)
  * SomeOption is the names of the ***New-VirtualDisk*** cmdlet parameters.
  * SomeValue is the values for those parameters. If this is the switch parameter, specify *True* or *False*.  
  **Example**: VD1InterLeave = 65536 .  
  There also important custom option on this parameter **VDxPartsCount**: it specifies the number of partitions
  that will be created on this Virtual Disks. It should be specified as following: *VD1PartsCount* = 2.
- **PartsCreationOptions**: options to create Partitions with. You need to pass an hashtable to this parameter.
You need to use the following syntax in here: *VDxPartYSomeOption* = *SomeValue*, where
  * x is the same as in **VDsCreationOptions**.
  * Y is a Partition number. It shouldn't more than **VDxPartsCount** option in **VDsCreationOptions** parameter.
  * SomeOption is the names of the **New-Partition** cmdlet parameters. Also you can specify two parameters from 
  **Format-Volume** cmdlet: *FileSystem* and *NewFileSystemLabel*.
  * SomeValue is the values for those parameters. If this is the switch parameter, specify *True* or *False*.
  
There also important notion on this parameters:
1. You shouldn't use next parameters of ***New-VirtualDisk*** cmdlet:
  * *StoragePoolFriendlyName*: it is provided by **StoragePoolName** parameter.
  * *FriendlyName*: it is provided by **VDsNames** parameter.
  * *Size* or *UseMaximumSize*: it is provided by **VDSizeDistribution** parameter and dinamically decided
  which parameter to use.
2. You shouldn't use *DiskNumber* parameter of **New-Partition** cmdlet. It will be added on runtime.
3. You shouldn't use any parameters of **Format-Volume** cmdlet except: *FileSystem* and *NewFileSystemLabel*.
This is not implemented by design.

## Versions

### 1.0
- Initial release with the following resources: 
  * **cStoragePool**
  
# Examples

Showing usage of the resource in different situations.
```sh
Configuration Examples
{
    Import-DscResource -module cStoragePool
    node localhost
    {
        # Creating single Storage Pool without VDs and Partitions.
        cStoragePool Example1
        {
            StoragePoolName = "ExampleStoragePool"
            NumberOfDisksInPool = 4
            SizeOfDisks = 100GB
            Ensure = 'Present'
        }
        # Creating Storage Pool with single VD, but without Partitions on it.        
        cStoragePool Example2
        {
            StoragePoolName = "ExampleStoragePool"
            VDsNames = "ExampleVD1"
            VDsCreationOptions = @{
                VD1InterLeave = 65536
                VD1NumberOfColumns = 4
                VD1ProvisioningType = "Fixed"
                VD1ResiliencySettingName = "Simple"
            }
            NumberOfDisksInPool = 4
            SizeOfDisks = 100GB
            Ensure = 'Present'
        }
        # Creating Storage Pool with single VD and two partitions on it.
        cStoragePool Example3
        {
            StoragePoolName = "ExampleStoragePool"
            VDsNames = "ExampleVD1"
            VDsCreationOptions = @{
                VD1InterLeave = 65536
                VD1NumberOfColumns = 2
                VD1ProvisioningType = "Fixed"
                VD1ResiliencySettingName = "Simple"
                VD1PartsCount = 2
            }
            PartsCreationOptions = @{
                VD1Part1DriveLetter = "F"
                VD1Part1Size = 10GB
                VD1Part1NewFileSystemLabel = "VD1 Part1"
                VD1Part2DriveLetter = "J"
                VD1Part2UseMaximumSize = $true
                VD1Part2NewFileSystemLabel = "VD1 Part2"
                VD1Part2FileSystem = "ReFS"
            }
            NumberOfDisksInPool = 4
            SizeOfDisks = 100GB
            Ensure = 'Present'
        }
        # Creating Storage Pool with 3 Virtual Disks in it, but without partitions.
        cStoragePool Example4
        {
            StoragePoolName = "ExampleStoragePool"
            VDsNames = "ExampleVD1", "ExampleVD2", "ExampleVD3"
            VDsCreationOptions = @{
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
            }
            VDSizeDistribution = 100GB, 100GB
            NumberOfDisksInPool = 4
            SizeOfDisks = 100GB
            Ensure = 'Present'
        }
        # Creating Storage Pool with 3 Virtual Disks with partitions.
        cStoragePool Example5
        {
            StoragePoolName = "ExampleStoragePool"
            VDsNames = "ExampleVD1", "ExampleVD2", "ExampleVD3"
            VDsCreationOptions = @{
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
            }
            PartsCreationOptions = @{
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
            }
            NumberOfDisksInPool = 4
            VDSizeDistribution = 0.33, 0.33, 0.34
            SizeOfDisks = 100GB
            Ensure = 'Present'
        }
    }
}
```