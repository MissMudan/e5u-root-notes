$ErrorActionPreference = 'Continue'
$work = "$env:USERPROFILE\Doubao\chats\2026-11-21\new-chat\E5U-root\patch"
$a = [System.IO.File]::ReadAllBytes("$work\splloader_orig.bin")
$b = [System.IO.File]::ReadAllBytes("$work\splloader.bin")
$u = [System.IO.File]::ReadAllBytes("$work\spl-unlock.bin")

Write-Host ("A=" + $a.Length + " B=" + $b.Length + " U=" + $u.Length)

for ($i = 0; $i -lt [math]::Min($u.Length, $b.Length); $i++) {
    if ($u[$i] -ne $b[$i]) {
        $o1 = $u[$i..([math]::Min($i + 7, $u.Length - 1))] | ForEach-Object { $_.ToString('X2') }
        $o2 = $b[$i..([math]::Min($i + 7, $b.Length - 1))] | ForEach-Object { $_.ToString('X2') }
        Write-Host ("首个 B/U 差异 0x{0:X}: U={1} B={2}" -f $i, ($o1 -join ' '), ($o2 -join ' '))
        break
    }
}

Write-Host "=== 扫描 0x34000060 (movz w0,#3) 出现位置 ==="
$hits = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt $a.Length - 4; $i++) {
    if ($a[$i] -eq 0x60 -and $a[$i+1] -eq 0x00 -and $a[$i+2] -eq 0x00 -and $a[$i+3] -eq 0x34) { [void]$hits.Add($i) }
}
Write-Host ("命中数=" + $hits.Count)
foreach ($h in $hits) {
    $lo = [math]::Max(0, $h - 8)
    $seg = $a[$lo..($h + 12)] | ForEach-Object { $_.ToString('X2') }
    $ctx = ($seg -join ' ')
    Write-Host ("0x{0:X}: {1}" -f $h, $ctx)
}

Write-Host "=== 扫描位的 mov 立即数模式 0x940000xx (BL) ==="
$bl = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt $a.Length - 4; $i++) {
    $hi = [uint32]$a[$i+3]
    if ($hi -eq 0x94) { [void]$bl.Add($i) }
}
Write-Host ("BL 指令数=" + $bl.Count)
