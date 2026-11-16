# makebinsmb3.ps1
# Builds a Commander X16 cartridge image that runs SMB3-X16.PRG with TANOOKI.BIN stored inside the cartridge.
# Put this script, SMB3-X16.PRG and TANOOKI.BIN (compiled from https://github.com/mooinglemur/smb3) 
# in the same folder and run it. 
#                    Output: ROM1.BIN.
#
# How it works:
#  1) At power-on the cartridge boot code copies the program to $0801 and copies TANOOKI.BIN
#     into banked RAM (banks 1+, $A000), exactly where the program's own LOAD would put it.
#  2) The program's routine that loads TANOOKI.BIN from disk is replaced (inside the ROM image only;
#     the .PRG file on disk is not touched) by code that reports a successful load.
#  3) Just before starting, the boot code clears its own traces and marks the KERNAL's keyboard joystick
#     as present ($A899 = 0), like the first key press would do.
#  4) The program is started directly at $080D.
# The SD card is not needed anymore.

$prgFile   = "$pwd\SMB3-X16.PRG"
$binFile   = "$pwd\TANOOKI.BIN"
$outFile   = "$pwd\ROM1.BIN"
$forceSize = 0   # 0 = automatic (smallest power of two that fits); or force e.g. 524288

# Boot code executed from RAM at $0500 (assembled and tested separately).
# Data follows the code: a list of 8-byte job records (source lo/hi, destination lo/hi, length lo/hi,
# cartridge bank, RAM bank), ended by a record of eight zero bytes.
$bootCode = [byte[]]@(
    0xA2, 0x00,                       # $0500: LDX #$00
    0x20, 0x4A, 0x05,                 # $0502: JSR setjob
    0xA5, 0x34,                       # $0505: LDA $34
    0x05, 0x35,                       # $0507: ORA $35
    0xF0, 0x0D,                       # $0509: BEQ jdone
    0x20, 0x73, 0x05,                 # $050B: JSR docopy
    0xE8,                             # $050E: INX
    0xE8,                             # $050F: INX
    0xE8,                             # $0510: INX
    0xE8,                             # $0511: INX
    0xE8,                             # $0512: INX
    0xE8,                             # $0513: INX
    0xE8,                             # $0514: INX
    0xE8,                             # $0515: INX
    0x80, 0xEA,                       # $0516: BRA jl
    0xA9, 0x00,                       # $0518: LDA #$00
    0x85, 0x01,                       # $051A: STA $01
    0xA2, 0x1F,                       # $051C: LDX #31
    0xBD, 0x2A, 0x05,                 # $051E: LDA tail,X
    0x9D, 0x40, 0x01,                 # $0521: STA $0140,X
    0xCA,                             # $0524: DEX
    0x10, 0xF7,                       # $0525: BPL cp
    0x4C, 0x40, 0x01,                 # $0527: JMP $0140
    0xA9, 0x00, 0xAA, 0x9D, 0x00, 0x05, 0x9D, 0x00, 0x06, 0x9D, 0x00, 0x07, 0xE8, 0xD0, 0xF4, 0xA2, 0x08, 0x9D, 0x30, 0x00, 0xCA, 0x10, 0xFA, 0x85, 0x00, 0x8D, 0x99, 0xA8, 0x58, 0x4C, 0x0D, 0x08, # $052A: .byte $A9,$00,$AA,$9D,$00,$05,$9D,$00,$06,$9D,$00,$07,$E8,$D0,$F4,$A2,$08,$9D,$30,$00,$CA,$10,$FA,$85,$00,$8D,$99,$A8,$58,$4C,$0D,$08
    0xBD, 0xAC, 0x05,                 # $054A: LDA job,X
    0x85, 0x30,                       # $054D: STA $30
    0xBD, 0xAD, 0x05,                 # $054F: LDA job+1,X
    0x85, 0x31,                       # $0552: STA $31
    0xBD, 0xAE, 0x05,                 # $0554: LDA job+2,X
    0x85, 0x32,                       # $0557: STA $32
    0xBD, 0xAF, 0x05,                 # $0559: LDA job+3,X
    0x85, 0x33,                       # $055C: STA $33
    0xBD, 0xB0, 0x05,                 # $055E: LDA job+4,X
    0x85, 0x34,                       # $0561: STA $34
    0xBD, 0xB1, 0x05,                 # $0563: LDA job+5,X
    0x85, 0x35,                       # $0566: STA $35
    0xBD, 0xB2, 0x05,                 # $0568: LDA job+6,X
    0x85, 0x38,                       # $056B: STA $38
    0xBD, 0xB3, 0x05,                 # $056D: LDA job+7,X
    0x85, 0x00,                       # $0570: STA $00
    0x60,                             # $0572: RTS
    0xA0, 0x00,                       # $0573: LDY #$00
    0xA5, 0x38,                       # $0575: LDA $38
    0x85, 0x01,                       # $0577: STA $01
    0xB1, 0x30,                       # $0579: LDA ($30),Y
    0x91, 0x32,                       # $057B: STA ($32),Y
    0xE6, 0x30,                       # $057D: INC $30
    0xD0, 0x0A,                       # $057F: BNE nosrc
    0xE6, 0x31,                       # $0581: INC $31
    0xD0, 0x06,                       # $0583: BNE nosrc
    0xA9, 0xC0,                       # $0585: LDA #$C0
    0x85, 0x31,                       # $0587: STA $31
    0xE6, 0x01,                       # $0589: INC $01
    0xE6, 0x32,                       # $058B: INC $32
    0xD0, 0x0E,                       # $058D: BNE nodst
    0xE6, 0x33,                       # $058F: INC $33
    0xA5, 0x33,                       # $0591: LDA $33
    0xC9, 0xC0,                       # $0593: CMP #$C0
    0xD0, 0x06,                       # $0595: BNE nodst
    0xA9, 0xA0,                       # $0597: LDA #$A0
    0x85, 0x33,                       # $0599: STA $33
    0xE6, 0x00,                       # $059B: INC $00
    0xA5, 0x34,                       # $059D: LDA $34
    0xD0, 0x02,                       # $059F: BNE declo
    0xC6, 0x35,                       # $05A1: DEC $35
    0xC6, 0x34,                       # $05A3: DEC $34
    0xA5, 0x34,                       # $05A5: LDA $34
    0x05, 0x35,                       # $05A7: ORA $35
    0xD0, 0xCE,                       # $05A9: BNE cloop
    0x60                              # $05AB: RTS
)

# ROM stub at $C000 (bank 32): the KERNAL jumps to $C004 when it finds "CX16" at $C000.
# It copies the 768-byte boot block from $C100 to $0500 in RAM and jumps there.
$romStub = [byte[]]@(
    0x43, 0x58, 0x31, 0x36,           # $C000: .ascii "CX16"
    0x78,                             # $C004: SEI
    0xA2, 0xFF,                       # $C005: LDX #$FF
    0x9A,                             # $C007: TXS
    0xA2, 0x00,                       # $C008: LDX #$00
    0xBD, 0x00, 0xC1,                 # $C00A: LDA $C100,X
    0x9D, 0x00, 0x05,                 # $C00D: STA $0500,X
    0xBD, 0x00, 0xC2,                 # $C010: LDA $C200,X
    0x9D, 0x00, 0x06,                 # $C013: STA $0600,X
    0xBD, 0x00, 0xC3,                 # $C016: LDA $C300,X
    0x9D, 0x00, 0x07,                 # $C019: STA $0700,X
    0xE8,                             # $C01C: INX
    0xD0, 0xEB,                       # $C01D: BNE cp
    0x4C, 0x00, 0x05                  # $C01F: JMP $0500
)

# ---- Load and check the inputs ----
if (-not (Test-Path $prgFile)) { Write-Host "ERROR: $prgFile not found."; exit 1 }
if (-not (Test-Path $binFile)) { Write-Host "ERROR: $binFile not found."; exit 1 }
$prg = [System.IO.File]::ReadAllBytes($prgFile)
$bin = [System.IO.File]::ReadAllBytes($binFile)

if ($prg.Length -lt 100 -or $prg[0] -ne 0x01 -or $prg[1] -ne 0x08) { Write-Host "ERROR: SMB3-X16.PRG must load at 0x0801."; exit 1 }
if ($bin.Length -lt 1) { Write-Host "ERROR: TANOOKI.BIN is empty."; exit 1 }

$payload = [byte[]]::new($prg.Length - 2)
[Array]::Copy($prg, 2, $payload, 0, $payload.Length)
if (0x0801 + $payload.Length -gt 0x9F00) { Write-Host "ERROR: the program is too large."; exit 1 }

# ---- Find the program's TANOOKI.BIN loader: LDA #1 / STA $00 / LDA #0 / LDX #0 / LDY #$A0 / JMP $FFD5 ----
$pattern = [byte[]]@(0xA9, 0x01, 0x85, 0x00, 0xA9, 0x00, 0xA2, 0x00, 0xA0, 0xA0, 0x4C, 0xD5, 0xFF)
$hits = @()
for ($i = 0; $i -le $payload.Length - $pattern.Length; $i++) {
    if ($payload[$i] -ne 0xA9) { continue }
    $same = $true
    for ($j = 1; $j -lt $pattern.Length; $j++) {
        if ($payload[$i + $j] -ne $pattern[$j]) { $same = $false; break }
    }
    if ($same) { $hits += $i }
}
if ($hits.Count -ne 1) { Write-Host "ERROR: expected exactly one TANOOKI.BIN loader in the program, found $($hits.Count). This script is made for SMB3-X16.PRG."; exit 1 }
$pos = $hits[0]

# ---- Where the program expects to be after LOAD: end bank and end address in banked RAM ----
# LOAD starts at bank 1, address $A000; each bank holds 8192 bytes.
$binLen = $bin.Length
$endBank = 1 + ($binLen -shr 13)
if ($endBank -gt 250) { Write-Host "ERROR: TANOOKI.BIN is too large."; exit 1 }
$endAddr = 0xA000 + ($binLen % 8192)
$endLo = $endAddr -band 0xFF
$endHi = $endAddr -shr 8

# Replacement (same 13 bytes): LDA #endBank / STA $00 / LDX #endLo / LDY #endHi / CLC / RTS / NOP NOP NOP
$patch = [byte[]]@(0xA9, [byte]$endBank, 0x85, 0x00, 0xA2, [byte]$endLo, 0xA0, [byte]$endHi, 0x18, 0x60, 0xEA, 0xEA, 0xEA)
[Array]::Copy($patch, 0, $payload, $pos, $patch.Length)

# ---- Layout: [stub][boot block @ $100][program @ $400][TANOOKI.BIN] ----
$off1  = 0x400
$off2  = $off1 + $payload.Length
$total = $off2 + $binLen
if ($payload.Length -gt 65535) { Write-Host "ERROR: program too large for this loader."; exit 1 }

# Copy jobs: the program, then TANOOKI.BIN in chunks of 7 banks (57344 bytes), so every chunk ends
# exactly at the end of a RAM bank and the next one starts at $A000 of the next bank.
$chunk = 57344
$jobList = New-Object System.Collections.ArrayList
[void]$jobList.Add(@($off1, 0x0801, $payload.Length, 0))
$p2 = 0
$rb = 1
while ($p2 -lt $binLen) {
    $n = [Math]::Min($chunk, $binLen - $p2)
    [void]$jobList.Add(@(($off2 + $p2), 0xA000, $n, $rb))
    $p2 += $n
    $rb += 7
}

$jobs = New-Object 'System.Collections.Generic.List[byte]'
foreach ($job in $jobList) {
    $off  = $job[0]
    $dst  = $job[1]
    $len  = $job[2]
    $addr = 0xC000 + ($off -band 0x3FFF)
    $bank = 32 + ($off -shr 14)
    $jobs.Add([byte]($addr -band 0xFF))
    $jobs.Add([byte](($addr -shr 8) -band 0xFF))
    $jobs.Add([byte]($dst -band 0xFF))
    $jobs.Add([byte](($dst -shr 8) -band 0xFF))
    $jobs.Add([byte]($len -band 0xFF))
    $jobs.Add([byte](($len -shr 8) -band 0xFF))
    $jobs.Add([byte]$bank)
    $jobs.Add([byte]$job[3])
}
for ($k = 0; $k -lt 8; $k++) { $jobs.Add([byte]0) }   # end marker
$jobBytes = $jobs.ToArray()

if ($bootCode.Length + $jobBytes.Length -gt 768) { Write-Host "ERROR: too many copy jobs for the 768-byte boot block."; exit 1 }
$block = [byte[]]::new(768)
[Array]::Copy($bootCode, 0, $block, 0, $bootCode.Length)
[Array]::Copy($jobBytes, 0, $block, $bootCode.Length, $jobBytes.Length)

# ---- Choose the output size: smallest power of two (min 16 KB) that holds everything ----
if ($forceSize -gt 0) {
    $size = $forceSize
} else {
    $size = 16384
    while ($size -lt $total) { $size = $size * 2 }
}
if ($size -lt $total) { Write-Host "ERROR: need $total bytes but the image is only $size bytes."; exit 1 }

$rom = [byte[]]::new($size)
for ($i = 0; $i -lt $size; $i++) { $rom[$i] = 0xFF }
[Array]::Copy($romStub, 0, $rom, 0, $romStub.Length)
[Array]::Copy($block, 0, $rom, 0x100, $block.Length)
[Array]::Copy($payload, 0, $rom, $off1, $payload.Length)
[Array]::Copy($bin, 0, $rom, $off2, $binLen)

[System.IO.File]::WriteAllBytes($outFile, $rom)

Write-Host ("OK: {0} generated ({1} KB)." -f $outFile, ($size / 1024))
Write-Host ("  program: {0} bytes, TANOOKI.BIN: {1} bytes, used: {2} bytes, copy jobs: {3}" -f $payload.Length, $binLen, $total, $jobList.Count)
Write-Host ("  loader patched at 0x{0:X4}, end of data: bank {1}, 0x{2:X4}" -f ($pos + 0x0801), $endBank, $endAddr)
Write-Host ("  SHA256: {0}" -f (Get-FileHash -Algorithm SHA256 -Path $outFile).Hash)
