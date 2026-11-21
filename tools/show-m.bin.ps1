$ErrorActionPreference = 'Continue'
Get-Process spd_dump -ErrorAction SilentlyContinue | Stop-Process -Force
$patch = "$env:USERPROFILE\Doubao\chats\2026-11-21\new-chat\E5U-root\patch"
$f = "$patch\m.bin"
if (Test-Path $f) {
    $b = [System.IO.File]::ReadAllBytes($f)
    Write-Host ("长度=" + $b.Length)
    Write-Host (($b | ForEach-Object { $_.ToString('X2') }) -join ' ')
    $ascii = -join ($b | ForEach-Object { if ($_ -ge 32 -and $_ -lt 127) { [char]$_ } else { '.' } })
    Write-Host ("ASCII: " + $ascii)
    $zeros = ($b | Where-Object { $_ -eq 0 }).Count
    Write-Host ("零字节数=" + $zeros + " / " + $b.Length)
} else { Write-Host "m.bin 不存在" }
