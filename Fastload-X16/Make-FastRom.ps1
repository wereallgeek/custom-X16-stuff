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
   1. ROM1 image -> copied into the free bank (its "select cartridge bank 32" bytes are retargeted);
   2. a 9-byte stub is written in unused space ($AA fill) of the KERNAL bank:
          jsr jsrfar / .word $C004 / .byte <bank> / jmp boot_cartridge
   3. the one call "jsr boot_cartridge" in the KERNAL start-up is changed to call that stub.
  4. identification: the ROM's 7-character build id (the commit hash stored at the very start of the
     KERNAL ROM, which the CX16 update program compares together with the version number) is
     replaced by "FAST" + the first 3 characters of the original id.  The version number is NOT
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

# grow a 256 KB ROM to the full 512 KB (unused banks = $FF)
if ($sys.Length -lt 524288) {
    $big = New-Object byte[] 524288
    for ($i = 0; $i -lt $big.Length; $i++) { $big[$i] = 0xFF }
    [Array]::Copy($sys, $big, $sys.Length)
    $sys = $big
}

# the target bank must be empty
$base = $Bank * 16384
for ($i = 0; $i -lt 16384; $i++) {
    if ($sys[$base + $i] -ne 0xFF) { throw "ROM bank $Bank of ROM0 is not empty (not all `$FF). Pick another with -Bank." }
}

# ---- 1. ROM1: make it read its own bank instead of bank 32 --------------------------------
# rom_blob1/rom_blob2 contain:  ldy $01 / lda #32 / sta $01   =  A4 01 A9 20 85 01
$h = Find-Pattern $cart 0 0x3F0 @(0xA4, 0x01, 0xA9, 0x20, 0x85, 0x01)
if ($h.Length -ne 2) { throw "ROM1: expected 2 'select bank 32' sequences, found $($h.Length). Is this the right ROM1.BIN?" }
foreach ($o in $h) { $cart[$o + 3] = [byte]$Bank }

# ---- 2. locate things in the KERNAL (ROM bank 0, file offsets 0..$3FFF = CPU $C000..$FFFF) ---
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
$a = @($bootOff)
$bootAddr = 0xC000 + $bootOff

# the 'jsr jsrfar / .word $C004 / .byte 32' that starts the cartridge: gives us jsrfar's address
$b = Find-Pattern $sys $bootOff ([Math]::Min($bootOff + 200, $kEnd)) @(0x20, -1, -1, 0x04, 0xC0, 0x20)
if ($b.Length -ne 1) { throw "KERNAL: cartridge jsrfar call not found ($($b.Length) matches)." }
$jsrfarLo = $sys[$b[0] + 1]; $jsrfarHi = $sys[$b[0] + 2]

# the single call to boot_cartridge in the start-up code
$c = Find-Pattern $sys 0 $kEnd @(0x20, ($bootAddr -band 0xFF), ($bootAddr -shr 8))
if ($c.Length -ne 1) { throw "KERNAL: expected exactly 1 'jsr boot_cartridge', found $($c.Length)." }

# unused KERNAL space: the linker fills it with `$AA (between `$C010 and `$FEA7). Collect all runs.
$runs = @(); $i = 0x0010
while ($i -lt 0x3EA8) {
    if ($sys[$i] -eq 0xAA) {
        $j = $i
        while ($j -lt 0x3EA8 -and $sys[$j] -eq 0xAA) { $j++ }
        $runs += ,@($i, ($j - $i)); $i = $j
    } else { $i++ }
}

# ---- 3. the two stubs ------------------------------------------------------------------------
# (a) 9 bytes: start the fastload cartridge from its own bank, then continue into boot_cartridge.
# (b) 81 bytes: the LOAD vector (ILOAD) target. It lives in the KERNAL, so it survives a cartridge
#     that overwrites RAM `$0400-`$07FF: if the resident code is intact it jumps to it, otherwise it
#     copies it back from the ROM bank, restores the original LOAD address and jumps to it.
#     It switches ROM banks while running, so the SAME bytes must be at the SAME address in bank 0
#     and in the fastload bank: it needs a free run in the KERNAL ($AA) that is also free in ROM1 ($FF).
$big = 81
$cartEnd = 0
for ($k = 0; $k -lt 0x3FFA; $k++) { if ($cart[$k] -ne 0xFF) { $cartEnd = $k } }
$bestLo = -1; $bestLen = 0; $bestRunStart = -1; $bestRunLen = 0
foreach ($r in $runs) {
    $lo = [Math]::Max($r[0], $cartEnd + 1)
    $len = $r[0] + $r[1] - $lo
    if ($len -ge $big -and $len -gt $bestLen) { $bestLo = $lo; $bestLen = $len; $bestRunStart = $r[0]; $bestRunLen = $r[1] }
}
if ($bestLo -lt 0) { throw ("KERNAL: no free space of $big bytes that is also unused in ROM1 (ROM1 data ends at offset 0x{0:X})." -f $cartEnd) }
$ilOff = $bestLo
# room for the 9-byte stub: the largest free piece that remains
$pieces = @()
foreach ($r in $runs) { if ($r[0] -ne $bestRunStart) { $pieces += ,@($r[0], $r[1]) } }
$pieces += ,@($bestRunStart, ($ilOff - $bestRunStart))
$pieces += ,@(($ilOff + $big), ($bestRunStart + $bestRunLen - $ilOff - $big))
$stubOff = -1; $stubLen = 0
foreach ($p in $pieces) { if ($p[1] -gt $stubLen) { $stubOff = $p[0]; $stubLen = $p[1] } }
if ($stubLen -lt 9) { throw "KERNAL: no free space for the 9-byte stub." }
$stubAddr = 0xC000 + $stubOff
$ilAddr   = 0xC000 + $ilOff

# default LOAD vector: restor copies the table 'vectss' to CINV.., so nload = vectss + (ILOAD - CINV)
$rs = Find-Pattern $sys 0 $kEnd @(0xA2, -1, 0xA0, -1, 0x18, 0x86, -1, 0x84, -1, 0xA0, -1, 0xB9, -1, -1, 0xB0, 0x02, 0xB1, -1, 0x91, -1, 0x99, -1, -1, 0x88, 0x10, -1, 0x60)
if ($rs.Length -ne 1) { throw "KERNAL: restor (vector table copy) not found ($($rs.Length) matches). Not an unmodified R49 KERNAL?" }
$vectss = $sys[$rs[0] + 1] + 256 * $sys[$rs[0] + 3]
$cinv   = $sys[$rs[0] + 12] + 256 * $sys[$rs[0] + 13]
$tbl = $vectss + 0x330 - $cinv
if ($tbl -lt 0xC000 -or $tbl -ge 0xFFF9) { throw "KERNAL: vector table address looks wrong (" + ('{0:X4}' -f $tbl) + ")." }

# the resident block in ROM1:  jmp install / jmp hook_load / "FL" / iload target
$mg = Find-Pattern $cart 0 0x3FF0 @(0x4C, -1, -1, 0x4C, -1, -1, 0x46, 0x4C, -1, -1)
if ($mg.Length -ne 1) { throw "ROM1: resident block marker not found ($($mg.Length) matches). Is this the right ROM1.BIN?" }
$src = 0xC000 + $mg[0]
$cart[$mg[0] + 8] = [byte]($ilAddr -band 0xFF)
$cart[$mg[0] + 9] = [byte]($ilAddr -shr 8)

$il = New-Object System.Collections.Generic.List[byte]
$il.AddRange([byte[]]@(0x48, 0xAD, 0x06, 0x04, 0xC9, 0x46, 0xD0, 11, 0xAD, 0x07, 0x04, 0xC9, 0x4C, 0xD0, 4, 0x68, 0x4C, 0x03, 0x04,
                       0x08, 0x78, 0xDA, 0x5A, 0xA5, 0x01, 0x48, 0xA9, $Bank, 0x85, 0x01, 0xA2, 0x00))
for ($pg = 0; $pg -lt 4; $pg++) {
    $sa = $src + 256 * $pg
    $il.AddRange([byte[]]@(0xBD, ($sa -band 0xFF), ($sa -shr 8), 0x9D, 0x00, (4 + $pg)))
}
$il.AddRange([byte[]]@(0xE8, 0xD0, 0xE5, 0x68, 0x85, 0x01, 0xAD, ($tbl -band 0xFF), ($tbl -shr 8), 0x8D, 0x0A, 0x04,
                       0xAD, (($tbl + 1) -band 0xFF), (($tbl + 1) -shr 8), 0x8D, 0x0B, 0x04, 0x7A, 0xFA, 0x28, 0x68, 0x4C, 0x03, 0x04))
if ($il.Count -ne $big) { throw "internal error: stub length $($il.Count)" }
for ($k = 0; $k -lt $big; $k++) { $sys[$ilOff + $k] = $il[$k]; $cart[$ilOff + $k] = $il[$k] }

$stub = @(0x20, $jsrfarLo, $jsrfarHi, 0x04, 0xC0, $Bank, 0x4C, ($bootAddr -band 0xFF), ($bootAddr -shr 8))
for ($k = 0; $k -lt $stub.Length; $k++) { $sys[$stubOff + $k] = [byte]$stub[$k] }
$sys[$c[0] + 1] = [byte]($stubAddr -band 0xFF)
$sys[$c[0] + 2] = [byte]($stubAddr -shr 8)
[Array]::Copy($cart, 0, $sys, $base, 16384)

# ---- 4. build id: first 7 characters at $C000 (what the CX16 update tool compares) -----------
$old = ''
for ($k = 0; $k -lt 7; $k++) {
    $ch = $sys[$k]
    if (-not (($ch -ge 0x30 -and $ch -le 0x39) -or ($ch -ge 0x41 -and $ch -le 0x5A))) {
        throw "ROM0: the build id at the start of the KERNAL is not 7 letters/digits - unexpected ROM layout."
    }
    $old += [char]$ch
}
$new = 'FAST' + $old.Substring(0, 3)
for ($k = 0; $k -lt 7; $k++) { $sys[$k] = [byte][char]$new[$k] }

[System.IO.File]::WriteAllBytes($outPath, $sys)

$sha = [System.Security.Cryptography.SHA256]::Create()
$hash = ($sha.ComputeHash($sys) | ForEach-Object { $_.ToString('x2') }) -join ''
Write-Host ("OK  {0}  ({1} bytes)" -f $outPath, $sys.Length)
Write-Host ("    fastload stored in ROM bank {0}" -f $Bank)
Write-Host ("    boot stub at `${0:X4}, call patched at `${1:X4}, boot_cartridge = `${2:X4}" -f $stubAddr, (0xC000 + $c[0]), $bootAddr)
Write-Host ("    LOAD vector stub at `${0:X4} (survives cartridges that overwrite RAM), default LOAD vector read from `${1:X4}" -f $ilAddr, $tbl)
Write-Host ("    build id: {0} -> {1}   (version number unchanged)" -f $old, $new)
Write-Host ("    sha256 {0}" -f $hash)
