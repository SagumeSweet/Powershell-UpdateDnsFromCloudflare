Param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$CloudflarePath,
    [Parameter(Mandatory=$true, Position=1)]
    [string]$DownloadUrl
)

# 获取新dns记录对象
function getNewDnsRecord {
    param (
        [hashtable]$getNewDnsRecordConf # 包含新旧ip、旧的dnsmanage对象
    )
    # 提取变量
    $newIP = $getNewDnsRecordConf["newIP"]
    $oldIP = $getNewDnsRecordConf["oldIP"]
    $allOldList = $getNewDnsRecordConf['allOldList']
    
    $allNewObjList = @{}
    # 获取需要修改的DNS记录对象
    foreach ($zone in $allOldList.Keys) {
        $allNewObjList[$zone] = @{}
        foreach ($hostName in $allOldList[$zone].Keys) {
            $allNewObjList[$zone][$hostName] = @{}
            foreach ($rrType in $allOldList[$zone][$hostName].Keys) {
                # DNS记录类型是A（IPv4） 并且 检测的新IP地址和旧的IP地址不同 并且 当前DNS记录和旧IP一样（即该IP是需要cloudflare加速的IP）
                if ($rrType -eq 'A' -and $newIP['ipv4'] -ne $oldIP['ipv4'] -and $allOldList[$zone][$hostName][$rrType].RecordData.IPv4Address.ToString() -eq $oldIP['ipv4']) {
                    $allNewObjList[$zone][$hostName][$rrType] = [ciminstance]::new($allOldList[$zone][$hostName][$rrType])
                # DNS记录类型是AAAA（IPv6） 并且 检测的新IP地址和旧的IP地址不同 并且 当前DNS记录和旧IP一样（即该IP是需要cloudflare加速的IP）
                } elseif ($rrType -eq 'AAAA' -and $newIP['ipv6'] -ne $oldIP['ipv6'] -and $allOldList[$zone][$hostName][$rrType].RecordData.IPv6Address.ToString() -eq $oldIP['ipv6']) {
                    $allNewObjList[$zone][$hostName][$rrType] = [ciminstance]::new($allOldList[$zone][$hostName][$rrType])
                }
            }
        }
    }
    # 更新IP
    foreach ($zone in $allNewObjList.Keys) {
        foreach ($hostName in $allNewObjList[$zone].Keys) {
            foreach ($rrType in $allNewObjList[$zone][$hostName].Keys) {
                if ($rrType -eq 'A') {
                    $allNewObjList[$zone][$hostName][$rrType].RecordData.IPv4Address = [Net.IPAddress]::Parse($newIP['ipv4'])
                } elseif ($rrType -eq 'AAAA') {
                    $allNewObjList[$zone][$hostName][$rrType].RecordData.IPv6Address = [Net.IPAddress]::Parse($newIP['ipv6'])
                }
            }
        }
    }

    return $allNewObjList
}

# 更新dns记录
function updateDnsRecord {
    param (
        [hashtable]$updateDnsRecordConf # 包含zone列表，新旧ip
    )
    # 提取变量
    $zoneList = $updateDnsRecordConf["zoneList"]
    $newIP = $updateDnsRecordConf["newIP"]
    $oldIP = $updateDnsRecordConf["oldIP"]
    
    $allOldObjList = getAllList -zoneList $zoneList

    $getNewDnsRecordConf = @{newIP = $newIP; oldIP = $oldIP; allOldList = $allOldObjList}
    $allNewObject = getNewDnsRecord -getNewDnsRecordConf $getNewDnsRecordConf

    foreach ($zone in $allNewObject.Keys) {
        foreach ($hostName in $allNewObject[$zone].Keys) {
            foreach ($rrType in $allNewObject[$zone][$hostName].Keys) {
                # 根据新记录的哈希表创建的循环，因此不需要单独筛选出与新记录对应的旧记录了
                Set-DnsServerResourceRecord -NewInputObject $allNewObject[$zone][$hostName][$rrType] -OldInputObject $allOldObjList[$zone][$hostName][$rrType] -ZoneName $zone
            }   
        }
    }
}

function getNewIP {
    # ipv4 输出的文件
    $path = "$CloudflarePath\result.csv"
    Get-Content $path | Select-Object -Skip 1 | Set-Content "$CloudflarePath\result1.csv"
    $ipTable = Import-Csv -Path "$CloudflarePath\result1.csv" -Header 'ipaddress'
    $bestIP = @{ipv4 = $ipTable.ipaddress[0]}
    # ipv6 输出的文件
    $path = "$CloudflarePath\ipv6result.csv"
    Get-Content $path | Select-Object -Skip 1 | Set-Content "$CloudflarePath\result1.csv"
    $ipTable = Import-Csv -Path "$CloudflarePath\result1.csv" -Header 'ipaddress'
    $bestIP["ipv6"] = $ipTable.ipaddress[0]

    Remove-Item "$CloudflarePath\result1.csv"
    return $bestIP
}

function getOldIP {
    $ipTable = Import-Csv -Path "$CloudflarePath\now_IP.csv" # 当前IP的文件
    $ipDic = @{ipv4 = $ipTable.IPv4; ipv6 = $ipTable.IPv6}
    return $ipDic
}

function updateOldIP {
    param(
        [hashtable]$ipDic
    )
    $ipv6 = $ipDic["ipv6"]
    $ipv4 = $ipDic["ipv4"]

    $path = "$CloudflarePath\now_IP.csv"
    $ipTable = Import-Csv -Path $path
    $ipTable.IPv6 = $ipv6
    $ipTable.IPv4 = $ipv4
    $ipTable | Format-Table
    $ipTable | Export-Csv -Path $path
}

# 获取一个包含所有文件的哈希表
function getAllList {
    param (
        [array]$zoneList
    )
    
    $allList = @{} # 结构如下
<# 
allList = @{
    zone = @{
        hostname = @{
            RRType = ciminstance object; 
            RRType = ciminstance object
        }; 
        hostname = @{
            RRType = ciminstance object; 
            RRType = ciminstance object
        }...
    };
    zone = @{
        hostname = @{
            RRType = ciminstance object; 
            RRType = ciminstance object
        }; 
        hostname = @{
            RRType = ciminstance object; 
            RRType = ciminstance object
        };...
    };...
}
#>


    foreach ($zone in $zoneList) {
        $oldObj = Get-DnsServerResourceRecord -ZoneName $zone -RRType A # 旧dnsmanage对象
        $allList[$zone] = @{}
        
        foreach ($i in $oldObj) {
            $allList[$zone][$i.HostName] = @{}
            $allList[$zone][$i.HostName][$i.RecordType] = [ciminstance]::new($i)
        }

        $oldObj = Get-DnsServerResourceRecord -ZoneName $zone -RRType AAAA # 旧dnsmanage对象
        foreach ($i in $oldObj) {
            # 区分有多个地址的域名和只有一个地址的域名
            if ($allList[$zone][$i.HostName] -is [hashtable]) {
                $allList[$zone][$i.HostName][$i.RecordType] = [ciminstance]::new($i)
            } else {
                $allList[$zone][$i.HostName] = @{}
                $allList[$zone][$i.HostName][$i.RecordType] = [ciminstance]::new($i)
            }
            
        }
    }
    return $allList
}

# 获取dns对象信息（调试用）
function getInfo {
    param (
        [hashtable]$allList
    )
    
    foreach ($zone in $allList.Keys) {
        foreach ($hostName in $allList[$zone].Keys) {
            foreach ($rrType in $allList[$zone][$hostName].Keys) {
                $nameInfo = $hostName + '.' + $zone
                $rrTyprInfo = 'RecordType: ' + $rrType
                if ($rrType -eq 'A') {
                    $recordDataInfo = 'RecordData: ' + $allList[$zone][$hostName][$rrType].RecordData.IPv4Address.ToString()
                } elseif ($rrType -eq 'AAAA') {
                    $recordDataInfo = 'RecorderData: ' + $allList[$zone][$hostName][$rrType].RecordData.IPv6Address.ToString()
                }
                Write-Host $nameInfo
                Write-Host $rrTyprInfo
                Write-Host $recordDataInfo
                Write-Host ---------------------------------------------------------------------------------------------------------------------
            }
        }
    }
}

# 获取区域列表
function getZoneList {
    $allZoneList = Get-DnsServerZone
    $zoneDic = @{}
    $count = 0
    foreach ($zone in $allZoneList) {
        if ($zone.IsAutoCreated -eq '' -and $zone.IsDsIntegrated -eq '' -and $zone.IsReverseLookupZone -eq '') {
            $count += 1
            $zoneDic[$count.ToString()] = $zone.ZoneName
        }
    }
    $zoneList = 1..$count
    for ($i = 0; $i -lt $zoneList.Length; $i +=1) {
        $zoneList[$i] = $zoneDic[($i + 1).ToString()]
    }
    return $zoneList
}

Start-Transcript -Path "$CloudflarePath\DnsUpdate.log"
# 执行cloudflareST
& "$CloudflarePath\cfst.exe" -f "$CloudflarePath\ip.txt" -o "$CloudflarePath\result.csv" -n 1000 -url $DownloadUrl -p 0
& "$CloudflarePath\cfst.exe" -f "$CloudflarePath\ipv6.txt" -o "$CloudflarePath\ipv6result.csv" -n 1000 -url $DownloadUrl -p 0

$zoneList = getZoneList
$bestIPDic = getNewIP
$oldIPDic = getOldIP
# 输出新旧IP
# $bestIPDic | Format-Table
# $oldIPDic | Format-Table

$updateDnsRecordConf = @{zoneList = $zoneList; oldIP = $oldIPDic; newIP = $bestIPDic}
updateDnsRecord -updateDnsRecordConf $updateDnsRecordConf

updateOldIP -ipDic $bestIPDic

# 清理dns缓存
Clear-DnsClientCache
Stop-Transcript
