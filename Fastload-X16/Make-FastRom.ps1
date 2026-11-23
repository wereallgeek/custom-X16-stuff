<#
.SYNOPSIS
  Builds FASTROM-R49.BIN: the X16 R49 system ROM with the IEC FastLoad built in (no cartridge needed).

.DESCRIPTION
  Inputs : ROM-R49.BIN (the official R49 rom.bin, 256 KB or 512 KB) and EPYX16.BIN (the 16 KB FastLoad
           cartridge image).
  Output : a 512 KB image to flash on the motherboard ROM.

  The fastload code is stored in a free ROM bank of the system ROM (default 31) and run by the
  KERNAL itself at every boot, right before it looks for a cartridge.  The cartridge slot (ROM bank 32
  and up) is left completely alone, so any other cartridge still autoboots normally.

  Changes made to the ROM:
   1. the ROM1 image is copied into the free bank; its ROM-resident part ($E000..) runs straight from
      ROM: nothing is copied to RAM, so programs that use RAM $0400-$07FF (e.g. CONCERTO) are safe;
   2. a small block of shared stubs (identical bytes in the KERNAL bank and in the fastload bank, since
      the ROM bank is switched while they run) is written in unused space ($AA fill) of the KERNAL:
      the LOAD entry, the return paths and four KERNAL-call trampolines (LISTEN/SECOND/CIOUT/UNLSN);
   3. a 9-byte boot stub:  jsr jsrfar / .word $E004 / .byte <bank> / jmp boot_cartridge  and the one
      call "jsr boot_cartridge" in the KERNAL start-up is changed to call it (it hooks ILOAD at boot).
  4. identification: the ROM's 7-character build id (the commit hash stored at the very start of the
     KERNAL ROM, which the CX16 update program compares together with the version number) is
     replaced by "FAST" + the build letter ($BuildLetter below, edit it by hand for each build) + the first 2 characters of the original id.  The version number is NOT
     touched.  "FAST" contains non-hex letters, so it can never equal a real build id, and a future
     official release (different version number and different id) is always seen as different.
  Nothing else is modified.

.EXAMPLE
  .\Make-FastRom.ps1
      (uses ROM-R49.BIN and EPYX16.BIN from the current folder, writes FASTROM-R49.BIN)
  .\Make-FastRom.ps1 -Rom0 rom.bin -Rom1 ROM1.BIN -Out MYROM.BIN
#>
param(
    [string]$Rom0 = 'ROM-R49.BIN',
    [string]$Rom1 = 'EPYX16.BIN',
    [string]$Out  = 'FASTROM-R49.BIN',
    [ValidateRange(16, 31)] [int]$Bank = 31
)
# Build letter: shown as the 5th character of the ROM's build id (FAST<letter>xx).  Change it by hand
# before every build you flash (A, B, C, ...) so each test ROM is distinguishable in the CX16 update tool.
$BuildLetter = 'A'

$ErrorActionPreference = 'Stop'

function Get-FullPath([string]$p) {
    if ([System.IO.Path]::IsPathRooted($p)) { return $p }
    return [System.IO.Path]::GetFullPath((Join-Path $PWD.Path $p))
}

# Offsets in $data[$start .. $end-1] where $pat matches ($pat entries of -1 = any byte)
function Find-Pattern([byte[]]$data, [int]$start, [int]$end, [int[]]$pat) {
    $hits = New-Object System.Collections.Generic.List[int]
    for ($i = $start; $i -le $end - $pat.Length; $i++) {
        $ok = $true
        for ($j = 0; $j -lt $pat.Length; $j++) {
            if ($pat[$j] -ge 0 -and $data[$i + $j] -ne $pat[$j]) { $ok = $false; break }
        }
        if ($ok) { $hits.Add($i) }
    }
    return , $hits.ToArray()
}

$rom0Path = Get-FullPath $Rom0
$rom1Path = Get-FullPath $Rom1
$outPath  = Get-FullPath $Out

# default names: also look next to the script if they are not in the current folder
if ($PSScriptRoot) {
    if (-not (Test-Path -LiteralPath $rom0Path) -and -not [System.IO.Path]::IsPathRooted($Rom0) -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot $Rom0))) { $rom0Path = Join-Path $PSScriptRoot $Rom0 }
    if (-not (Test-Path -LiteralPath $rom1Path) -and -not [System.IO.Path]::IsPathRooted($Rom1) -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot $Rom1))) { $rom1Path = Join-Path $PSScriptRoot $Rom1 }
}
if (-not (Test-Path -LiteralPath $rom0Path)) { throw "ROM0 not found: $rom0Path (default name: ROM-R49.BIN, run from its folder or use -Rom0)" }
if (-not (Test-Path -LiteralPath $rom1Path)) { throw "ROM1 not found: $rom1Path (default name: EPYX16.BIN, run from its folder or use -Rom1)" }
$sys  = [System.IO.File]::ReadAllBytes($rom0Path)
$cart = [System.IO.File]::ReadAllBytes($rom1Path)

# ---- check the inputs --------------------------------------------------------------------
if ($sys.Length -ne 262144 -and $sys.Length -ne 524288) {
    throw "ROM0 must be 262144 or 524288 bytes (got $($sys.Length)). Is it the full R49 system ROM?"
}
if ($cart.Length -ne 16384) { throw "ROM1 must be 16384 bytes (got $($cart.Length))." }
if ($cart[0] -ne 0x43 -or $cart[1] -ne 0x58 -or $cart[2] -ne 0x31 -or $cart[3] -ne 0x36) {
    throw "ROM1 does not start with the 'CX16' cartridge signature."
}
if ($cart[0x2000] -ne 0x46 -or $cart[0x2001] -ne 0x4C -or $cart[0x2002] -ne 0x52 -or $cart[0x2003] -ne 0x4D) {
    throw "ROM1 has no ROM-resident part (old EPYX16.BIN?). Use the new one."
}

# grow a 256 KB ROM to the full 512 KB (unused banks = $FF)
if ($sys.Length -lt 524288) {
    $big = New-Object byte[] 524288
    for ($i = 0; $i -lt $big.Length; $i++) { $big[$i] = 0xFF }
    [Array]::Copy($sys, $big, $sys.Length)
    $sys = $big
}

# the target bank must be empty
$bankBase = $Bank * 16384
for ($i = 0; $i -lt 16384; $i++) {
    if ($sys[$bankBase + $i] -ne 0xFF) { throw "ROM bank $Bank of ROM0 is not empty (not all `$FF). Pick another with -Bank." }
}

# ---- 1. locate things in the KERNAL (ROM bank 0, file offsets 0..$3FFF = CPU $C000..$FFFF) ---
$kEnd = 0x4000
# boot_cartridge:  lda #tmp2 / sta fetvec / stz tmp2 / lda #$C0 / sta tmp2+1 / ldy #3 / ldx #32 /
#                  jsr fetch / cmp sig,y / bne / dey / bpl
# (fetvec lives in RAM so "sta fetvec" is 3 bytes, but accept the 2-byte form too)
$core = Find-Pattern $sys 0 $kEnd @(0xA0, 0x03, 0xA2, 0x20, 0x20, -1, -1, 0xD9, -1, -1, 0xD0, -1, 0x88, 0x10, -1)
if ($core.Length -ne 1) { throw "KERNAL: boot_cartridge signature loop not found ($($core.Length) matches). Not an unmodified R49 KERNAL?" }
$pre3 = @(0xA9, -1, 0x8D, -1, -1, 0x64, -1, 0xA9, 0xC0, 0x85, -1)
$pre2 = @(0xA9, -1, 0x85, -1, 0x64, -1, 0xA9, 0xC0, 0x85, -1)
$bootOff = -1
foreach ($pre in @($pre3, $pre2)) {
    $o = $core[0] - $pre.Length
    if ($o -ge 0) {
        $m = Find-Pattern $sys $o ($o + $pre.Length) $pre
        if ($m.Length -eq 1) { $bootOff = $o; break }
    }
}
if ($bootOff -lt 0) { throw "KERNAL: start of boot_cartridge not recognised (bytes before the signature loop: " + (($sys[($core[0]-12)..($core[0]-1)] | ForEach-Object { $_.ToString('X2') }) -join ' ') + ")." }
$bootAddr = 0xC000 + $bootOff

# the 'jsr jsrfar / .word $C004 / .byte 32' that starts the cartridge: gives us jsrfar's address
$b = Find-Pattern $sys $bootOff ([Math]::Min($bootOff + 200, $kEnd)) @(0x20, -1, -1, 0x04, 0xC0, 0x20)
if ($b.Length -ne 1) { throw "KERNAL: cartridge jsrfar call not found ($($b.Length) matches)." }
$jsrfarLo = $sys[$b[0] + 1]; $jsrfarHi = $sys[$b[0] + 2]

# the single call to boot_cartridge in the start-up code
$c = Find-Pattern $sys 0 $kEnd @(0x20, ($bootAddr -band 0xFF), ($bootAddr -shr 8))
if ($c.Length -ne 1) { throw "KERNAL: expected exactly 1 'jsr boot_cartridge', found $($c.Length)." }

# default LOAD vector: restor copies the table 'vectss' to CINV.., so nload = vectss + (ILOAD - CINV)
$rs = Find-Pattern $sys 0 $kEnd @(0xA2, -1, 0xA0, -1, 0x18, 0x86, -1, 0x84, -1, 0xA0, -1, 0xB9, -1, -1, 0xB0, 0x02, 0xB1, -1, 0x91, -1, 0x99, -1, -1, 0x88, 0x10, -1, 0x60)
if ($rs.Length -ne 1) { throw "KERNAL: restor (vector table copy) not found ($($rs.Length) matches). Not an unmodified R49 KERNAL?" }
$vectss = $sys[$rs[0] + 1] + 256 * $sys[$rs[0] + 3]
$cinv   = $sys[$rs[0] + 12] + 256 * $sys[$rs[0] + 13]
$tbl = $vectss + 0x330 - $cinv
if ($tbl -lt 0xC000 -or $tbl -ge 0xFFF9) { throw ("KERNAL: vector table address looks wrong (" + ('{0:X4}' -f $tbl) + ").") }

# ---- 2. free space -----------------------------------------------------------------------------
# Runs of equal bytes [start, end) in $data between $lo and $hi
function Get-Runs([byte[]]$data, [int]$val, [int]$lo, [int]$hi) {
    $r = @(); $i = $lo
    while ($i -lt $hi) {
        if ($data[$i] -eq $val) {
            $j = $i
            while ($j -lt $hi -and $data[$j] -eq $val) { $j++ }
            $r += ,@($i, $j); $i = $j
        } else { $i++ }
    }
    return , $r
}
$kr = Get-Runs $sys 0xAA 0x10 0x3EA8          # unused KERNAL space (linker fill $AA)
$cr = Get-Runs $cart 0xFF 0x10 0x3F90         # unused space in ROM1
$big = 73
$S = -1; $bestLen = 0
foreach ($k in $kr) { foreach ($q in $cr) {
    $lo = [Math]::Max($k[0], $q[0]); $hi = [Math]::Min($k[1], $q[1])
    if (($hi - $lo) -ge $big -and ($hi - $lo) -gt $bestLen) { $S = $lo; $bestLen = $hi - $lo }
} }
if ($S -lt 0) { throw "No space that is free both in the KERNAL (`$AA) and in ROM1 (`$FF): need $big bytes." }
# the 9-byte boot stub: the largest other free KERNAL piece
$sb = -1; $sbLen = 0
foreach ($k in $kr) {
    $pieces = @()
    if ($k[1] -le $S -or $k[0] -ge ($S + $big)) { $pieces += ,@($k[0], $k[1]) }
    else {
        if ($k[0] -lt $S) { $pieces += ,@($k[0], $S) }
        if ($k[1] -gt ($S + $big)) { $pieces += ,@(($S + $big), $k[1]) }
    }
    foreach ($p in $pieces) { if (($p[1] - $p[0]) -gt $sbLen) { $sb = $p[0]; $sbLen = $p[1] - $p[0] } }
}
if ($sbLen -lt 9) { throw "KERNAL: no free space for the 9-byte boot stub." }

# ---- 3. shared stubs (same bytes at the same address in bank 0 and in the fastload bank) --------
$base = 0xC000 + $S
$ent = $base; $tret = $base + 9; $tch = $base + 12; $tr = $base + 17
$blk = New-Object System.Collections.Generic.List[byte]
$blk.AddRange([byte[]]@(0x08, 0x48, 0xA9, $Bank, 0x85, 0x01))                 # php / pha / lda #bank / sta $01
$blk.AddRange([byte[]]@($sys[$S + 6], $sys[$S + 7], $sys[$S + 8]))             # (bank 0: unused filler)
$blk.AddRange([byte[]]@(0x64, 0x01, 0x60))                                     # return: stz $01 / rts
$blk.AddRange([byte[]]@(0x64, 0x01, 0x6C, ($tbl -band 0xFF), ($tbl -shr 8)))   # chain : stz $01 / jmp (default LOAD)
$kern = @(0xFF93, 0xFFA8, 0xFFAE, 0xFFB1)                                      # SECOND, CIOUT, UNLSN, LISTEN
foreach ($e in $kern) {
    $blk.AddRange([byte[]]@(0x64, 0x01, 0x20, ($e -band 0xFF), ($e -shr 8), 0x08, 0x48, 0xA9, $Bank, 0x85, 0x01, 0x68, 0x28, 0x60))
}
if ($blk.Count -ne $big) { throw "internal error: shared block length $($blk.Count)" }
for ($k = 0; $k -lt $big; $k++) { $sys[$S + $k] = $blk[$k]; $cart[$S + $k] = $blk[$k] }
for ($k = 0; $k -lt 3; $k++) { $cart[$S + 6 + $k] = $cart[0x3FD6 + $k] }       # bank side: continue into rom_hook
for ($i = 0; $i -lt 4; $i++) {
    $o = $kern[$i] - 0xC000
    if ($cart[$o] -ne 0x4C) { throw "ROM1: stub table missing at `$$('{0:X4}' -f $kern[$i])" }
    $t = $tr + 14 * $i
    $cart[$o + 1] = [byte]($t -band 0xFF); $cart[$o + 2] = [byte]($t -shr 8)
}
foreach ($pair in @(@(0x3FD0, $tret), @(0x3FD3, $tch))) {
    if ($cart[$pair[0]] -ne 0x4C) { throw "ROM1: stub table missing at offset $($pair[0])" }
    $cart[$pair[0] + 1] = [byte]($pair[1] -band 0xFF); $cart[$pair[0] + 2] = [byte]($pair[1] -shr 8)
}
if ($cart[0x2011] -ne 0xED -or $cart[0x2012] -ne 0xFE) { throw "ROM1: LOAD-vector placeholder not found." }
$cart[0x2011] = [byte]($ent -band 0xFF); $cart[0x2012] = [byte]($ent -shr 8)

# ---- 4a. boot stub + patch the call, copy the bank -----------------------------------------------
$stub = @(0x20, $jsrfarLo, $jsrfarHi, 0x04, 0xE0, $Bank, 0x4C, ($bootAddr -band 0xFF), ($bootAddr -shr 8))
for ($k = 0; $k -lt 9; $k++) { $sys[$sb + $k] = [byte]$stub[$k] }
$stubAddr = 0xC000 + $sb
$sys[$c[0] + 1] = [byte]($stubAddr -band 0xFF)
$sys[$c[0] + 2] = [byte]($stubAddr -shr 8)
[Array]::Copy($cart, 0, $sys, $bankBase, 16384)

# ---- 4. build id: first 7 characters at $C000 (what the CX16 update tool compares) -----------
$old = ''
for ($k = 0; $k -lt 7; $k++) {
    $ch = $sys[$k]
    if (-not (($ch -ge 0x30 -and $ch -le 0x39) -or ($ch -ge 0x41 -and $ch -le 0x5A))) {
        throw "ROM0: the build id at the start of the KERNAL is not 7 letters/digits - unexpected ROM layout."
    }
    $old += [char]$ch
}
if ($BuildLetter -notmatch '^[A-Z0-9]$') { throw "`$BuildLetter must be one letter or digit (A-Z, 0-9)." }
$new = 'FAST' + $BuildLetter + $old.Substring(0, 2)
for ($k = 0; $k -lt 7; $k++) { $sys[$k] = [byte][char]$new[$k] }

[System.IO.File]::WriteAllBytes($outPath, $sys)

$sha = [System.Security.Cryptography.SHA256]::Create()
$hash = ($sha.ComputeHash($sys) | ForEach-Object { $_.ToString('x2') }) -join ''
Write-Host ("OK  {0}  ({1} bytes)" -f $outPath, $sys.Length)
Write-Host ("    fastload stored in ROM bank {0}" -f $Bank)
Write-Host ("    boot stub at `${0:X4}, call patched at `${1:X4}, boot_cartridge = `${2:X4}" -f $stubAddr, (0xC000 + $c[0]), $bootAddr)
Write-Host ("    LOAD entry stub at `${0:X4}; default LOAD vector read from `${1:X4}; nothing is kept in RAM" -f $ent, $tbl)
Write-Host ("    build id: {0} -> {1}   (version number unchanged)" -f $old, $new)
Write-Host ("    sha256 {0}" -f $hash)
