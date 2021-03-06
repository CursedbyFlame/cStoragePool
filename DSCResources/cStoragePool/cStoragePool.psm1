# region Main.
#
# Get-TargetResource function.

function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String] $StoragePoolName,

        [System.String[]] $VDsNames,

        [parameter(Mandatory = $true)]
        [Uint64] $SizeofDisks,

        [parameter(Mandatory = $true)]
        [Uint32] $NumberOfDisksInPool     
    )

    $Configuration = @{
        StoragePoolName = $StoragePoolName
    }

    try
    {
        if (Get-StoragePool -FriendlyName $StoragePoolName)
        {
            $Configuration.Add('Ensure','Present')
            $Configuration.Add('SizeofDisks',($SizeofDisks/1GB))
            $Configuration.Add('NumberOfDisksInPool',$NumberOfDisksInPool)
            $Configuration.Add('VDsNames',$VDsNames)
            [String[]]$letters = @()

            for ($i=0; $i -lt $VDsNames.Count; $i++)
            {
                $VD = Get-VirtualDisk -FriendlyName $VDsNames[$i]
                $Disk = Get-Disk -UniqueId $VD.UniqueId
                $Parts = Get-Partition -DiskNumber $disk.Number | select -Property DriveLetter | where -FilterScript {$_.DriveLetter.ToString() -ne ""}

                foreach ($part in $Parts)
                {
                    $letters += $part.DriveLetter
                }

            }

            $Configuration.Add("PartitionsInPool",$letters)
        }
        else
        {
            $Configuration.Add('Ensure','Absent')
        }

        return $Configuration
    }
    catch
    {
        $exception = $_
        Write-Verbose "Error occurred while executing Get-TargetResource function"
        while ($exception.InnerException -ne $null)
        {
            $exception = $exception.InnerException
            Write-Verbose $exception.Message
        }
    }
}

#
# Set-TargetResource function.
#

function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String] $StoragePoolName,

        [System.String[]] $VDsNames,

        [parameter(Mandatory = $true)]
        [Uint64] $SizeofDisks,

        [parameter(Mandatory = $true)]
        [Uint32] $NumberOfDisksInPool,

        [double[]] $VDSizeDistribution,

        [Microsoft.Management.Infrastructure.CimInstance[]]$VDsCreationOptions,

        [Microsoft.Management.Infrastructure.CimInstance[]]$PartsCreationOptions,

        [ValidateSet('Present','Absent')]
        [ValidateNotNullOrEmpty()]
        [string] $Ensure
    )

    try
    {
        if ($Ensure -eq 'Present')
        {
            Write-Verbose "Creating a Storage Pool $StoragePoolName."

            # This check is done to make this resource compatible with AzureRM Deployment. It's workaround issue when system cannot find 
            # a storage sub system with, a default name. If there only sub system on OS then, it will use it.
            if ((Get-StorageSubSystem).count -gt 1)
            {
                $StorageSubSystem = Get-StorageSubSystem -FriendlyName "Storage Spaces *"
            }
            else
            {
                $StorageSubSystem = Get-StorageSubSystem
            }

            # Creates storage pool.
            New-StoragePool -FriendlyName $StoragePoolName `
                            -StorageSubSystemUniqueId $StorageSubSystem.uniqueID `
                            -PhysicalDisks (Get-PhysicalDisk -CanPool $true | where size -eq $SizeofDisks | select -First $NumberOfDisksInPool)
            Write-Verbose "Storage Pool $StoragePoolName has been created."

            if ($VDSizeDistribution.Count -ne 0)
            {

                if ($VDSizeDistribution[0] -lt 1)
                {
                    Write-Verbose "Size for the disks specified in a percentage format. Checking if sum is equals to 1."

                    foreach ($VDsize in $VDSizeDistribution)
                    {
                        $VDSizesSum += [double]$VDSize
                    }

                    if ($VDSizesSum -ne 1)
                    {
                        throw "Sum of percentages for disk sizes is not equals to 1."
                    }

                    Write-Verbose "Sum is equals to 1. Continue to script."
                }
            }

            if ($VDsNames)
            {
                Write-Verbose "Parameter VDsNames found. Virtual Disks will be created."
                $array = Import-VDsFromUnparsedArray -StoragePoolName $StoragePoolName -VDsNames $VDsNames -VDSizeDistribution $VDSizeDistribution -VDsCreationOptions $VDsCreationOptions

                for ($i=0; $i -lt $VDsNames.Count; $i++)
                {
                    Write-Verbose ("Creating Virtual Disk " + $VDsNames[$i])

                    if ($VDsNames.Count -eq 1)
                    {
                        $Parameters = $array
                    }
                    else
                    {
                        $Parameters = $array[$i]
                    }

                    New-VirtualDisk @Parameters
                    Write-Verbose ("Virtual Disk " + $VDsNames[$i] + " has been created. Disk will be initialized." )
                    Initialize-Disk -VirtualDisk (Get-VirtualDisk -FriendlyName $VDsNames[$i])
                    Write-Verbose "Disk has been initialized."
                }

                if ($PartsCreationOptions)
                {
                    Write-Verbose "Parameter PartsCreationOptions has been found. Partitions will be created."
                    $array2 = Import-PartsFromUnparsedArray -VDsNames $VDsNames -PartsCreationOptions $PartsCreationOptions

                    for ($i=0; $i -lt $VDsNames.Count; $i++)
                    {
                        Write-Verbose ("Creating partitions on disk "+$VDsNames[$i])

                        for ($l=0; $l -lt $Script:VDPartsCount[($i)];$l++)
                        {

                            if ($VDsNames.Count -eq 1)
                            {
                                $Parameters = $array2[$l]
                                $Format = $Script:FormatOptions[$i][$l]
                            }
                            else
                            {
                                $Parameters = $array2[$i][$l]
                                $Format = $Script:FormatOptions[$i][$l]
                            }

                            Write-Verbose ("Creating partition "+$Format.NewFileSystemLabel)
                            New-Partition @Parameters
                            Start-Sleep 10
                            Write-Verbose ("Partition  "+$Format.NewFileSystemLabel+" has been created. Formating it.")
                            # This check implements functionality not specify FileSystem, it will use NTFS as a default.

                            if ($Format.FileSystem)
                            {
                                Format-Volume -DriveLetter $Parameters.DriveLetter -FileSystem $Format.FileSystem -NewFileSystemLabel $Format.NewFileSystemLabel
                            }
                            else
                            {
                                Format-Volume -DriveLetter $Parameters.DriveLetter -FileSystem "NTFS" -NewFileSystemLabel $Format.NewFileSystemLabel
                            }

                            Write-Verbose "Partition has been formated."
                        }
                    }
                }
            }

            Write-Verbose "All actions has been completed successfully."
        }
        else
        {
            Write-Verbose "Deleting a Storage Pool $StoragePoolName."

            for ($i=0; $i -lt $VDsNames.Count; $i++)
            {
                Write-Verbose ("Deleting a Virtual Disk "+$VDsNames[$i])
                Remove-VirtualDisk -FriendlyName $VDsNames[$i] -Confirm:$false
                Write-Verbose "VD has been deleted."
            }

            Remove-StoragePool -FriendlyName $StoragePoolName -Confirm:$false
            Write-Verbose "Storage Pool has been deleted."
        }
    }
    catch
    {
        $exception = $_
        Write-Verbose "Error occurred while executing Set-TargetResource function"
        while ($exception.InnerException -ne $null)
        {
            $exception = $exception.InnerException
            Write-Verbose $exception.Message
        }
    }
}

#
# Test-TargetResource function.
#

function Test-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String] $StoragePoolName,

        [System.String[]] $VDsNames,

        [parameter(Mandatory = $true)]
        [Uint64] $SizeofDisks,

        [parameter(Mandatory = $true)]
        [Uint32] $NumberOfDisksInPool,

        [double[]] $VDSizeDistribution,

        [Microsoft.Management.Infrastructure.CimInstance[]]$VDsCreationOptions,

        [Microsoft.Management.Infrastructure.CimInstance[]]$PartsCreationOptions,

        [ValidateSet('Present','Absent')]
        [ValidateNotNullOrEmpty()]
        [string] $Ensure
    )

    Write-Verbose "Checking if Storage Pool $StoragePoolName exist."

    try
    {
        if ($Ensure -eq 'Present')
        {

            if (Get-StoragePool -FriendlyName $StoragePoolName -ErrorAction Ignore)
            {
                Write-Verbose "Storage Pool $StoragePoolName exist and Ensure set to Present. Nothing to configure."

                return $true
            }
            else
            {
                Write-Verbose "Storage Pool $StoragePoolName does not exist and Ensure set to Present. Storage Pool will be created."

                return $false
            }
        }
        else
        {

            if (Get-StoragePool -FriendlyName $StoragePoolName -ErrorAction Ignore)
            {
                Write-Verbose "Storage Pool $StoragePoolName exist and Ensure set to Absent. Storage Pool will be deleted."

                return $false
            }
            else
            {
                Write-Verbose "Storage Pool $StoragePoolName does not exist and Ensure set to Absent. Nothing to configure."
                
                return $true
            }
        }
    }
    catch
    {
        $exception = $_
        Write-Verbose "Error occurred while executing Get-TargetResource function"
        while ($exception.InnerException -ne $null)
        {
            $exception = $exception.InnerException
            Write-Verbose $exception.Message
        }
    }
}


#
# region Helpeing Functions.
#


function Import-VDsFromUnparsedArray
{
    <#
    .SYNOPSIS
        Receive an MSFT_KeyVailuePair object and distribute them in correct structure.
    .DESCRIPTION
        The Import-VDsFromUnparsedArray recieve an MSFT_KeyVailuePair as an input. Parse the hashtable and distributes VD creation options in a
        correct structure, which Set-TargetResource is expect to see.
    .PARAMETER StoragePoolName
        Specifies the name of the storage pool.
    .PARAMETER VDsNames
        Specifies the names of the Virtual Disks.
    .PARAMETER VDSizeDistribution
        Specifies the distribution of the Storage Pool size between Virtual Disks. It can accept direct notation, or percentage of a full size.
    .PARAMETER $VDsCreationOptions
        Specifies Virtual Disks creation options. Accept an MSFT_KeyVailurePair as an input.
    #>
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String] $StoragePoolName,

        [System.String[]] $VDsNames,

        [double[]] $VDSizeDistribution,

        [Microsoft.Management.Infrastructure.CimInstance[]]$VDsCreationOptions
    )
    # Initializing stucture vatiables.
    $Script:VDPartsCount = @()
    # Creating an empty array of constant deep.
    $VDsArray = New-Object 'System.Object[]' -ArgumentList ($VDsNames.Count)

    for ($i=1; $i -le $VDsNames.Count; $i++)
    {
        # Initializing empty hashtable.
        $VDCreationOptionsHash = @{}

        foreach($instance in $VDsCreationOptions) 
        {

            # Separates creation options for one VD from another using prefix.
            if ($instance.key -like "VD$i*")
            {
                # Clear an option name from parasite prefix.
                [string] $KeyName = $instance.key
                $ClearKeyName = $KeyName.replace("VD$i",'')

                # If option name is PartsCount it should be treated as separate option, that needs to included in script scope Variable.
                if ($ClearKeyName -eq "PartsCount")
                {
                    $Script:VDPartsCount += $instance.value
                }
                # Adding an key-value pairs to a hashtable.
                else
                {

                    # 'Cause of MSFT_KeyVailuePair object treat all values as a string, we should directly replace string True or False to boolean vailue.
                    if ($instance.value -eq "True")
                    {
                        $VDCreationOptionsHash += @{
                            $ClearKeyName = $true
                        }
                    }
                    elseif ($instance.value -eq "False")
                    {
                        $VDCreationOptionsHash += @{
                            $ClearKeyName = $false
                        }
                    }
                    else
                    {
                        $VDCreationOptionsHash += @{
                            $ClearKeyName = $instance.value
                        }
                    }
                }
            }
        }

        # This check implements possibility to not specify size for the last VD in storage pool.
        if ($VDSizeDistribution.Count -ge $VDsNames.Count)
        {

            # This check implements possibility to specify size in percentage notation.
            if ($VDSizeDistribution[($i-1)] -gt 0 -and $VDSizeDistribution[($i-1)] -le 1)
            {

                # If this is the last VD in storage pool it will use the UseMaximumSize option.
                if ($i -eq $VDsNames.Count)
                {
                    $VDCreationOptionsHash += @{
                        StoragePoolFriendlyName = $StoragePoolName
                        UseMaximumSize = $true
                        FriendlyName = $VDsNames[($i-1)]
                    }
                }
                # If this is not last we define VD Size as percentage multiplied on difference between full size and size that was already allocated.
                else
                {
                    $StoragePool = Get-StoragePool -FriendlyName $StoragePoolName
                    $Size = ($VDSizeDistribution[($i-1)]*($StoragePool.Size - $StoragePool.AllocatedSize))/1GB

                    # As New-VirtualDisks cmdlet rounds the Size vailue up to 2GBs, we should round the value to the closest even number.
                    if (($Size % 2) -ne 0)
                    {
                        $Size = $Size - ($Size % 2) # This rounds the number to lower even number.
                    }

                    $VDCreationOptionsHash += @{
                        StoragePoolFriendlyName = $StoragePoolName
                        Size = Invoke-Expression -Command "${Size}GB"
                        FriendlyName = $VDsNames[($i-1)]
                    }
                }
            }
            # If size discribed as a direct notation, this section just transit this value to a configuration hashtable.
            else
            {
                $VDCreationOptionsHash += @{
                    StoragePoolFriendlyName = $StoragePoolName
                    Size = $VDSizeDistribution[($i-1)]
                    FriendlyName = $VDsNames[($i-1)]
                }
            }
        }
        else
        {

            # It checks how much Virtual disks have no Size specified: if one UseMaximumSize, if more throw error.
            if (($VDsNames.Count - $VDSizeDistribution.Count) -eq 1)
            {

                if ($i -eq $VDsNames.Count)
                {
                    $VDCreationOptionsHash += @{
                        StoragePoolFriendlyName = $StoragePoolName
                        UseMaximumSize = $True
                        FriendlyName = $VDsNames[($i-1)]
                    }
                }
                else
                {
                    $VDCreationOptionsHash += @{
                        StoragePoolFriendlyName = $StoragePoolName
                        Size = $VDSizeDistribution[($i-1)]
                        FriendlyName = $VDsNames[($i-1)]
                    }
                }
            }
            else
            {
                throw "Sizes for two or more Virtual Disks not specified."
            }
        }

        #Adding an hashtable to an array.
        $VDsArray[($i-1)] = $VDCreationOptionsHash
    }

    return $VDsArray
}

function Import-PartsFromUnparsedArray
{
    <#
    .SYNOPSIS
        Receive an MSFT_KeyVailuePair object and distribute them in correct structure.
    .DESCRIPTION
        The Import-PartsFromUnparsedArray recieve an MSFT_KeyVailuePair as an input. Parse the hashtable and distributes Partitions creation options in a
        correct structure, which Set-TargetResource is expect to see.
    .PARAMETER VDsNames
        Specifies the names of the Virtual Disks.
    .PARAMETER $VDsCreationOptions
        Specifies Virtual Disks creation options. Accept an MSFT_KeyVailurePair as an input.
    #>
    [CmdletBinding()]
    param
    (
        [System.String[]] $VDsNames,

        [Microsoft.Management.Infrastructure.CimInstance[]]$PartsCreationOptions
    )
    # Initializing stucture vatiables.
    $PartsArray = New-Object 'System.Object[]' -ArgumentList ($VDsNames.Count)
    $Script:FormatOptions = New-Object 'System.Object[]' -ArgumentList ($VDsNames.Count)

    for ($i=1; $i -le $VDsNames.Count; $i++)
    {
        # Initializing stucture vatiables.
        $VDArray = @()
        $FormatOptionsTemp = @()

        for ($l=1; $l -le $Script:VDPartsCount[($i-1)]; $l++)
        {
            # Initializing empty hashtables.
            $PartCreationOptionsHash = @{}
            $FormatTemp = @{}    

            foreach($instance in $PartsCreationOptions) {
                $Pattern = ("VD"+$i+"Part"+$l)

                if ($instance.key -like "$Pattern*" )
                {
                    [string] $KeyName = $instance.key
                    $ClearKeyName = $KeyName.replace("$Pattern",'')

                    # If option name is one of the needed for Format-Volume cmdlet it should be assigned to a scriptscoped variable.
                    if ($ClearKeyName -eq "NewFileSystemLabel")
                    {
                        $FormatTemp += @{
                            $ClearKeyName = $instance.value
                        }
                    }
                    elseif ($ClearKeyName -eq "FileSystem")
                    {
                        $FormatTemp += @{
                            $ClearKeyName = $instance.value
                        }
                    }
                    else
                    {

                        # 'Cause of MSFT_KeyVailuePair object treat all values as a string, we should directly replace string True or False to boolean vailue.
                        if ($instance.value -eq "True")
                        {
                            $PartCreationOptionsHash += @{
                                $ClearKeyName = $true
                            }
                        }
                        elseif ($instance.value -eq "False")
                        {
                            $PartCreationOptionsHash += @{
                                $ClearKeyName = $false
                            }
                        }
                        else
                        {
                            $PartCreationOptionsHash += @{
                                $ClearKeyName = $instance.value
                            }
                        }
                    }
                }
            }

            $diskNumber = ((Get-VirtualDisk -FriendlyName $VDsNames[($i-1)] | Get-Disk).Number)
            $PartCreationOptionsHash += @{
                DiskNumber = $diskNumber
            }

            $FormatOptionsTemp += $FormatTemp
            $VDArray += $PartCreationOptionsHash
        }

        #Adding an hashtable to an array and script scoped variable.
        $Script:FormatOptions[($i-1)] = $FormatOptionsTemp
        $PartsArray[($i-1)] = $VDArray
    }

    return $PartsArray
}

Export-ModuleMember -Function *-TargetResource