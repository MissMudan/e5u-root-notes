$ErrorActionPreference = 'Continue'
$work = "$env:USERPROFILE\Doubao\chats\2026-11-21\new-chat\E5U-root\patch"
$a = [System.IO.File]::ReadAllBytes("$work\splloader_orig.bin")
$b = [System.IO.File]::ReadAllBytes("$work\splloader.bin")
$u = [System.IO.File]::ReadAllBytes("$work\spl-unlock.bin")

Write-Host ("原始长度=" + $a.Length + "  补丁后长度=" + $b.Length + "  spl-unlock长度=" + $u.Length)

$diffs = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt $b.Length; $i++) {
    if ($a[$i] -ne $b[$i]) { [void]$diffs.Add($i) }
}
Write-Host ("差异字节数=" + $diffs.Count)

if ($diffs.Count -gt 0) {
    Write-Host ("首个差异偏移=0x" + $diffs[0].ToString('X'))
    $runs = New-Object System.Collections.ArrayList
    $start = $diffs[0]; $prev = $diffs[0]
    foreach ($d in $diffs) {
        if ($d - $prev -gt 4) { [void]$runs.Add("0x{0:X} - 0x{1:X}" -f $start, $prev); $start = $d }
        $prev = $d
    }
    [void]$runs.Add("0x{0:X} - 0x{1:X}" -f $start, $prev)
    Write-Host ("差异区间: " + ($runs -join " | "))

    for ($k = 0; $k -lt [math]::Min(6, $diffs.Count); $k++) {
        $o = $diffs[$k]
        $orig = ($a[$o..($o + 3)] | ForEach-Object { $_.ToString('X2') }) -join ' '
        $pat = ($b[$o..($o + 3)] | ForEach-Object { $_.ToString('X2') }) -join ' '
        Write-Host ("offset 0x{0:X}: orig={1}  patched={2}" -f $o, $orig, $pat)
    }
}

$same = $true
for ($i = 0; $i -lt [math]::Min($u.Length, $b.Length); $i++) {
    if ($u[$i] -ne $b[$i]) { $same = $false; break }
}
Write-Host ("spl-unlock.bin 与补丁后 splloader 内容一致: " + $same)
Write-Host ("补丁文件 MD5: " + (Get-FileHash "$work\splloader.bin" -Algorithm MD5).Hash)
