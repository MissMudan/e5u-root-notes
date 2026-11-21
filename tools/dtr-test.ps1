$ErrorActionPreference = 'Continue'
function GetSprdCom {
    $d = Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { $_.PNPDeviceID -match 'VID_1782&PID_4D00' -and $_.Name -match 'COM\d+' } | Select-Object -First 1
    if ($d -and $d.Name -match '(COM\d+)') { return $matches[1] }
    return $null
}
$com = GetSprdCom
if (-not $com) { Write-Host "设备不在线"; exit 1 }
Write-Host "端口: $com"

function TestWrite($dtr, $rts, $label) {
    $p = New-Object System.IO.Ports.SerialPort($com, 115200, 'None', 8, 'One')
    $p.ReadTimeout = 1200; $p.WriteTimeout = 1200
    $p.DtrEnable = $dtr; $p.RtsEnable = $rts
    try {
        $p.Open()
        Start-Sleep -Milliseconds 150
        $n = $p.Write([byte[]](0x7E), 0, 1)
        Write-Host "$label : 写入返回 $n 字节"
        Start-Sleep -Milliseconds 300
        $rx = @()
        try { while ($p.BytesToRead -gt 0) { $rx += $p.ReadByte() } } catch {}
        $hex = ($rx | ForEach-Object { $_.ToString('X2') }) -join ' '
        Write-Host "$label : 读回 $($rx.Count) 字节 [$hex]"
        $p.Close()
    } catch {
        Write-Host "$label : 异常 $($_.Exception.Message)"
        if ($p.IsOpen) { try { $p.Close() } catch {} }
    }
}

TestWrite $false $false "DTR=0 RTS=0"
Start-Sleep -Milliseconds 500
TestWrite $true  $false "DTR=1 RTS=0"
