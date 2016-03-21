# cStoragePool

The **cStoragePool** module contains a single DSC resource **cStoragePool**. 
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
  * *FriendlyName*: it is provided by **VDsNames* parameter.
  * *Size* or *UseMaximumSize*: it is provided by **VDSizeDistribution** parameter and dinamically decided
  which parameter to use.
2. You shouldn't use *DiskNumber* parameter of **New-Partition** cmdlet. It will be added on runtime.
3. You shouldn't use any parameters of **Format-Volume** cmdlet except: *FileSystem* and *NewFileSystemLabel*.
This is not implemented by design.