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

        [Uint64[]] $VDSizeDistribution,

        [Microsoft.Management.Infrastructure.CimInstance[]]$VDsCreationOptions,

        [Microsoft.Management.Infrastructure.CimInstance[]]$PartsCreationOptions,

        [ValidateSet('Present','Absent')]
        [ValidateNotNullOrEmpty()]
        [string] $Ensure
    )
    if ($Ensure -eq 'Present')
    {
        New-StoragePool -FriendlyName $StoragePoolName `
                        -StorageSubSystemUniqueId (Get-StorageSubSystem).uniqueID `
                        -PhysicalDisks (Get-PhysicalDisk -CanPool $true | where size -eq $SizeofDisks | select -First $NumberOfDisksInPool)
        if ($VDsNames)
        {
            $array = Import-VDsFromUnparsedArray -StoragePoolName $StoragePoolName -VDsNames $VDsNames -VDSizeDistribution $VDSizeDistribution -VDsCreationOptions $VDsCreationOptions
            for ($i=0; $i -lt $VDsNames.Count; $i++)
            {
                $Parameters = $array[$i]
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
                        $Parameters = $array2[$i][$l]
                        New-Partition @Parameters
                        Start-Sleep 10
                        Format-Volume -DriveLetter $Parameters.DriveLetter -FileSystem NTFS
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

        [Uint64[]] $VDSizeDistribution,

        [Microsoft.Management.Infrastructure.CimInstance[]]$VDsCreationOptions,

        [Microsoft.Management.Infrastructure.CimInstance[]]$PartsCreationOptions,

        [ValidateSet('Present','Absent')]
        [ValidateNotNullOrEmpty()]
        [string] $Ensure
    )
    if (Get-StoragePool -FriendlyName $StoragePoolName -ErrorAction Ignore)
    {
        return $true
    }
    else
    {
        return $false
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

        [Uint64[]] $VDSizeDistribution,

        [Microsoft.Management.Infrastructure.CimInstance[]]$VDsCreationOptions
    )
    $Script:VDPartsCount = @()
    $array = @()
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
            $hash += @{
                StoragePoolFriendlyName = $StoragePoolName
                Size = $VDSizeDistribution[($i-1)]
                FriendlyName = $VDsNames[($i-1)]
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
        $array += $hash
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
    
    $array2 = New-Object 'System.Object[]' -ArgumentList 3
    for ($i=1; $i -le $VDsNames.Count; $i++)
    {
        $hash = @()
        for ($l=1; $l -le $Script:VDPartsCount[($i-1)]; $l++)
        {
            $hash1 = @{}
    
            foreach($instance in $PartsCreationOptions) {
                $pat = ("VD"+$i+"Part"+$l)
                if ($instance.key -like "$pat*" )
                {
                    [string] $key = $instance.key
                    $key1 = $key.replace("$pat",'')
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
            $s = $i - 1
            $diskNumber = ((Get-VirtualDisk -FriendlyName $VDsNames[$s] | Get-Disk).Number)
            $hash1 += @{
                DiskNumber = $diskNumber
            }
            $hash += $hash1
        }
        
        $array2[$s] = $hash
    }
    return $array2
}

Export-ModuleMember -Function *-TargetResource

