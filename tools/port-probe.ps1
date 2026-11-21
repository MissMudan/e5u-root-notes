$ErrorActionPreference = 'Continue'
Add-Type -AssemblyName System.IO.Ports

function Get-SprdCom {
    $list = @()
    try {
        $list = Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
            Where-Object { $_.PNPDeviceID -match 'VID_1782&PID_4D00' -and $_.Name -match 'COM\d+' }
    } catch {}
    if (-not $list) {
        try {
            $list = Get-PnpDevice -PresentOnly -Class Ports -ErrorAction SilentlyContinue |
                Where-Object { $_.InstanceId -match 'VID_1782&PID_4D00' }
        } catch {}
    }
    foreach ($d in $list) {
        if ($d.Name -match '(COM\d+)') { return $matches[1] }
        if ($d.FriendlyName -match '(COM\d+)') { return $matches[1] }
    }
    return $null
}

Write-Host "等待 SPRD 端口出现（最多 120 秒）..."
$deadline = (Get-Date).AddSeconds(120)
$com = $null
while ((Get-Date) -lt $deadline) {
    $com = Get-SprdCom
    if ($com) { break }
    Start-Sleep -Milliseconds 400
}

if (-not $com) {
    Write-Host "未检测到 SPRD 端口"
    exit 1
}

Write-Host "发现端口: $com  时间: $(Get-Date -Format 'HH:mm:ss.fff')"
Start-Sleep -Milliseconds 300

foreach ($baud in @(115200, 921600)) {
    $p = $null
    try {
        $p = New-Object System.IO.Ports.SerialPort($com, $baud, 'None', 8, 'One')
        $p.ReadTimeout = 1500
        $p.WriteTimeout = 1500
        $p.DtrEnable = $true
        $p.RtsEnable = $true
        $p.Open()
        Start-Sleep -Milliseconds 200

        $tx = [byte[]](0x7E)
        $p.Write($tx, 0, 1)

        $rx = @()
        $end = (Get-Date).AddSeconds(2)
        while ((Get-Date) -lt $end) {
            try {
                $b = $p.ReadByte()
                if ($b -ge 0) { $rx += $b }
            } catch { }
            if ($rx.Count -ge 8) { break }
        }
        $hex = ($rx | ForEach-Object { $_.ToString('X2') }) -join ' '
        Write-Host "波特率 $baud : 收到 $($rx.Count) 字节 -> [$hex]"
        $p.Close()
    }
    catch {
        Write-Host "波特率 $baud : 异常 $($_.Exception.Message)"
        if ($p -and $p.IsOpen) { try { $p.Close() } catch {} }
    }
}
Write-Host "探测结束"
