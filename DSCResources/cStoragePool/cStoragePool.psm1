function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String] $StoragePoolName,

        [parameter(Mandatory = $true)]
        [Uint64] $SizeofDisks,

        [parameter(Mandatory = $true)]
        [Uint32] $NumberOfDisksInPool,

        [ValidateSet('Present','Absent')]
        [ValidateNotNullOrEmpty()]
        [string] $Ensure
    )

    #Write-Verbose "Use this cmdlet to deliver information about command processing."

    #Write-Debug "Use this cmdlet to write debug information while troubleshooting."


    <#
    $returnValue = @{
    NameK = [System.String]
    Pair = [System.String]
    }

    $returnValue
    #>
}


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
    if ($Ensure -eq 'Present')
    {
        if ((Get-StorageSubSystem).count -gt 1)
        {
            $StorageSubSystem = Get-StorageSubSystem -FriendlyName "Storage Spaces *"
        }
        else
        {
            $StorageSubSystem = Get-StorageSubSystem
        }
        New-StoragePool -FriendlyName $StoragePoolName `
                        -StorageSubSystemUniqueId $StorageSubSystem.uniqueID `
                        -PhysicalDisks (Get-PhysicalDisk -CanPool $true | where size -eq $SizeofDisks | select -First $NumberOfDisksInPool)
        if ($VDSizeDistribution.Count -ne 0)
        {
            if ($VDSizeDistribution[0] -lt 1)
            {
                foreach ($VDsize in $VDSizeDistribution)
                {
                    $VDSizesSum += [double]$VDSize
                }
                if ($VDSizesSum -ne 1)
                {
                    throw "Sum of percentages for disk sizes is not equals to 1."
                }
            }
        }
        if ($VDsNames)
        {
            $array = Import-VDsFromUnparsedArray -StoragePoolName $StoragePoolName -VDsNames $VDsNames -VDSizeDistribution $VDSizeDistribution -VDsCreationOptions $VDsCreationOptions
            for ($i=0; $i -lt $VDsNames.Count; $i++)
            {
                if ($VDsNames.Count -eq 1)
                {
                    $Parameters = $array
                }
                else
                {
                    $Parameters = $array[$i]
                }
                New-VirtualDisk @Parameters
                Initialize-Disk -VirtualDisk (Get-VirtualDisk -FriendlyName $VDsNames[$i])
            }
            if ($PartsCreationOptions)
            {
                $array2 = Import-PartsFromUnparsedArray -VDsNames $VDsNames -PartsCreationOptions $PartsCreationOptions
                for ($i=0; $i -lt $VDsNames.Count; $i++)
                {
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
                        New-Partition @Parameters
                        Start-Sleep 10
                        if ($Format.FileSystem)
                        {
                            Format-Volume -DriveLetter $Parameters.DriveLetter -FileSystem $Format.FileSystem -NewFileSystemLabel $Format.NewFileSystemLabel
                        }
                        else
                        {
                            Format-Volume -DriveLetter $Parameters.DriveLetter -FileSystem "NTFS" -NewFileSystemLabel $Format.NewFileSystemLabel
                        }
                    }
                }
            }
        }
    }
    else
    {
        for ($i=0; $i -lt $VDsNames.Count; $i++)
        {
            Remove-VirtualDisk -FriendlyName $VDsNames[$i] -Confirm:$false
        }
        Remove-StoragePool -FriendlyName $StoragePoolName -Confirm:$false
    }
}


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
    if ($Ensure -eq 'Present')
    {
        if (Get-StoragePool -FriendlyName $StoragePoolName -ErrorAction Ignore)
        {
            return $true
        }
        else
        {
            return $false
        }
    }
    else
    {
        if (Get-StoragePool -FriendlyName $StoragePoolName -ErrorAction Ignore)
        {
            return $false
        }
        else
        {
            return $true
        }
    }
}

function Import-VDsFromUnparsedArray
{
    [CmdletBinding()]
    param
    (
        [parameter(Mandatory = $true)]
        [System.String] $StoragePoolName,

        [System.String[]] $VDsNames,

        [double[]] $VDSizeDistribution,

        [Microsoft.Management.Infrastructure.CimInstance[]]$VDsCreationOptions
    )
    $Script:VDPartsCount = @()
    $array = New-Object 'System.Object[]' -ArgumentList ($VDsNames.Count)
    for ($i=1; $i -le $VDsNames.Count; $i++)
    {
        $hash = @{}
    
        foreach($instance in $VDsCreationOptions) 
        {
            if ($instance.key -like "VD$i*")
            {
                [string] $key = $instance.key
                $key1 = $key.replace("VD$i",'')
                if ($key1 -eq "PartsCount")
                {
                    $Script:VDPartsCount += $instance.value
                }
                else
                {
                    if ($instance.value -eq "True")
                    {
                        $hash += @{
                            $key1 = $true
                        }
                    }
                    elseif ($instance.value -eq "False")
                    {
                        $hash += @{
                            $key1 = $false
                        }
                    }
                    else
                    {
                        $hash += @{
                            $key1 = $instance.value
                        }
                    }
                }
            }
        }
        if ($VDSizeDistribution.Count -ge $VDsNames.Count)
        {
            if ($VDSizeDistribution[($i-1)] -gt 0 -and $VDSizeDistribution[($i-1)] -le 1)
            {
                if ($i -eq $VDsNames.Count)
                {
                    $hash += @{
                        StoragePoolFriendlyName = $StoragePoolName
                        UseMaximumSize = $true
                        FriendlyName = $VDsNames[($i-1)]
                    }
                }
                else
                {
                    $StoragePool = Get-StoragePool -FriendlyName $StoragePoolName
                    $Size = ($VDSizeDistribution[($i-1)]*($StoragePool.Size - $StoragePool.AllocatedSize))/1GB
                    if (($Size % 2) -ne 0)
                    {
                        $Size = $Size - ($Size % 2)
                    }
                    $hash += @{
                        StoragePoolFriendlyName = $StoragePoolName
                        Size = Invoke-Expression -Command "${Size}GB"
                        FriendlyName = $VDsNames[($i-1)]
                    }
                }
            }
            else
            {
                $hash += @{
                    StoragePoolFriendlyName = $StoragePoolName
                    Size = $VDSizeDistribution[($i-1)]
                    FriendlyName = $VDsNames[($i-1)]
                }
            }
        }
        else
        {
            if (($VDsNames.Count - $VDSizeDistribution.Count) -eq 1)
            {
                if ($i -eq $VDsNames.Count)
                {
                    $hash += @{
                        StoragePoolFriendlyName = $StoragePoolName
                        UseMaximumSize = $True
                        FriendlyName = $VDsNames[($i-1)]
                    }
                }
                else
                {
                    $hash += @{
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
        $array[($i-1)] = $hash
    }
    return $array
}

function Import-PartsFromUnparsedArray
{
    [CmdletBinding()]
    param
    (
        [System.String[]] $VDsNames,

        [Microsoft.Management.Infrastructure.CimInstance[]]$PartsCreationOptions
    )
    
    $array2 = New-Object 'System.Object[]' -ArgumentList ($VDsNames.Count)
    $Script:FormatOptions = New-Object 'System.Object[]' -ArgumentList ($VDsNames.Count)
    for ($i=1; $i -le $VDsNames.Count; $i++)
    {
        $hash = @()
        $FormatOptionsTemp = @()
        for ($l=1; $l -le $Script:VDPartsCount[($i-1)]; $l++)
        {
            $hash1 = @{}
            $FormatTemp = @{}    
            foreach($instance in $PartsCreationOptions) {
                $pat = ("VD"+$i+"Part"+$l)
                if ($instance.key -like "$pat*" )
                {
                    [string] $key = $instance.key
                    $key1 = $key.replace("$pat",'')
                    if ($key1 -eq "NewFileSystemLabel")
                    {
                        $FormatTemp += @{
                            $key1 = $instance.value
                        }
                    }
                    elseif ($key1 -eq "FileSystem")
                    {
                        $FormatTemp += @{
                            $key1 = $instance.value
                        }
                    }
                    else
                    {
                        if ($instance.value -eq "True")
                        {
                            $hash1 += @{
                                $key1 = $true
                            }
                        }
                        elseif ($instance.value -eq "False")
                        {
                            $hash1 += @{
                                $key1 = $false
                            }
                        }
                        else
                        {
                            $hash1 += @{
                                $key1 = $instance.value
                            }
                        }
                    }
                }
            }
            $s = $i - 1
            $diskNumber = ((Get-VirtualDisk -FriendlyName $VDsNames[$s] | Get-Disk).Number)
            $hash1 += @{
                DiskNumber = $diskNumber
            }
            $FormatOptionsTemp += $FormatTemp
            $hash += $hash1
        }
        $Script:FormatOptions[$s] = $FormatOptionsTemp
        $array2[$s] = $hash
    }
    return $array2
}

Export-ModuleMember -Function *-TargetResource

