# makebinsmb.ps1
# Builds a Commander X16 cartridge image that runs SMBX16.PRG with SMB.NES stored inside the cartridge.
# Put this script, SMBX16.PRG and SMB.NES in the same folder and run it. Output: ROM1.BIN.
#
# How it works:
#  1) At power-on the cartridge boot code copies the program to $0801 and copies SMB.NES
#     into banked RAM (banks 1+, $A000), exactly where the program's own LOAD would put it.
#  2) The program's single LOAD call is replaced (inside the ROM image only; the .PRG file on disk
#     is not touched) by code that reports a successful load with the same end bank/address.
#  3) Just before starting, the boot code clears its own traces and marks the KERNAL's keyboard joystick
#     as present ($A899 = 0). At power-on the KERNAL marks it "absent" until the first key press, and
#     SMBX16 then discards joystick 1 (it reads joystick 1 | keyboard). Without this, pad 1 is dead.
#  4) The program is started directly at $080D.
# The SD card is not needed for the NES file anymore.

$prgFile   = "$pwd\SMBX16.PRG"
$nesFile   = "$pwd\SMB.NES"
$outFile   = "$pwd\ROM1.BIN"
$forceSize = 0   # 0 = automatic (smallest power of two that fits); or force e.g. 262144

# Boot code executed from RAM at $0500 (assembled and tested separately).
# Data follows the code: two 8-byte job records (source lo/hi, destination lo/hi, length lo/hi,
# cartridge bank, RAM bank).
# It copies everything, then moves a small tail routine to $0110 (so it can erase its own area),
# clears $0500-$07FF and $30-$38, sets RAM bank 0, sets $A899 = 0, enables interrupts, JMP $080D.
$bootCode = [byte[]]@(
    0xA2, 0x00,                       # $0500: LDX #$00
    0x20, 0x42, 0x05,                 # $0502: JSR setjob
    0x20, 0x6B, 0x05,                 # $0505: JSR docopy
    0xA2, 0x08,                       # $0508: LDX #$08
    0x20, 0x42, 0x05,                 # $050A: JSR setjob
    0x20, 0x6B, 0x05,                 # $050D: JSR docopy
    0xA9, 0x00,                       # $0510: LDA #$00
    0x85, 0x01,                       # $0512: STA $01
    0xA2, 0x1F,                       # $0514: LDX #31
    0xBD, 0x22, 0x05,                 # $0516: LDA tail,X
    0x9D, 0x10, 0x01,                 # $0519: STA $0110,X
    0xCA,                             # $051C: DEX
    0x10, 0xF7,                       # $051D: BPL cp
    0x4C, 0x10, 0x01,                 # $051F: JMP $0110
    0xA9, 0x00, 0xAA, 0x9D, 0x00, 0x05, 0x9D, 0x00, 0x06, 0x9D, 0x00, 0x07, 0xE8, 0xD0, 0xF4, 0xA2, 0x08, 0x9D, 0x30, 0x00, 0xCA, 0x10, 0xFA, 0x85, 0x00, 0x8D, 0x99, 0xA8, 0x58, 0x4C, 0x0D, 0x08, # $0522: .byte $A9,$00,$AA,$9D,$00,$05,$9D,$00,$06,$9D,$00,$07,$E8,$D0,$F4,$A2,$08,$9D,$30,$00,$CA,$10,$FA,$85,$00,$8D,$99,$A8,$58,$4C,$0D,$08
    0xBD, 0xA4, 0x05,                 # $0542: LDA job,X
    0x85, 0x30,                       # $0545: STA $30
    0xBD, 0xA5, 0x05,                 # $0547: LDA job+1,X
    0x85, 0x31,                       # $054A: STA $31
    0xBD, 0xA6, 0x05,                 # $054C: LDA job+2,X
    0x85, 0x32,                       # $054F: STA $32
    0xBD, 0xA7, 0x05,                 # $0551: LDA job+3,X
    0x85, 0x33,                       # $0554: STA $33
    0xBD, 0xA8, 0x05,                 # $0556: LDA job+4,X
    0x85, 0x34,                       # $0559: STA $34
    0xBD, 0xA9, 0x05,                 # $055B: LDA job+5,X
    0x85, 0x35,                       # $055E: STA $35
    0xBD, 0xAA, 0x05,                 # $0560: LDA job+6,X
    0x85, 0x38,                       # $0563: STA $38
    0xBD, 0xAB, 0x05,                 # $0565: LDA job+7,X
    0x85, 0x00,                       # $0568: STA $00
    0x60,                             # $056A: RTS
    0xA0, 0x00,                       # $056B: LDY #$00
    0xA5, 0x38,                       # $056D: LDA $38
    0x85, 0x01,                       # $056F: STA $01
    0xB1, 0x30,                       # $0571: LDA ($30),Y
    0x91, 0x32,                       # $0573: STA ($32),Y
    0xE6, 0x30,                       # $0575: INC $30
    0xD0, 0x0A,                       # $0577: BNE nosrc
    0xE6, 0x31,                       # $0579: INC $31
    0xD0, 0x06,                       # $057B: BNE nosrc
    0xA9, 0xC0,                       # $057D: LDA #$C0
    0x85, 0x31,                       # $057F: STA $31
    0xE6, 0x01,                       # $0581: INC $01
    0xE6, 0x32,                       # $0583: INC $32
    0xD0, 0x0E,                       # $0585: BNE nodst
    0xE6, 0x33,                       # $0587: INC $33
    0xA5, 0x33,                       # $0589: LDA $33
    0xC9, 0xC0,                       # $058B: CMP #$C0
    0xD0, 0x06,                       # $058D: BNE nodst
    0xA9, 0xA0,                       # $058F: LDA #$A0
    0x85, 0x33,                       # $0591: STA $33
    0xE6, 0x00,                       # $0593: INC $00
    0xA5, 0x34,                       # $0595: LDA $34
    0xD0, 0x02,                       # $0597: BNE declo
    0xC6, 0x35,                       # $0599: DEC $35
    0xC6, 0x34,                       # $059B: DEC $34
    0xA5, 0x34,                       # $059D: LDA $34
    0x05, 0x35,                       # $059F: ORA $35
    0xD0, 0xCE,                       # $05A1: BNE cloop
    0x60                              # $05A3: RTS
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
if (-not (Test-Path $nesFile)) { Write-Host "ERROR: $nesFile not found."; exit 1 }
$prg = [System.IO.File]::ReadAllBytes($prgFile)
$nes = [System.IO.File]::ReadAllBytes($nesFile)

if ($prg.Length -lt 100 -or $prg[0] -ne 0x01 -or $prg[1] -ne 0x08) { Write-Host "ERROR: SMBX16.PRG must load at 0x0801."; exit 1 }
if ($nes.Length -lt 16 -or $nes[0] -ne 0x4E -or $nes[1] -ne 0x45 -or $nes[2] -ne 0x53 -or $nes[3] -ne 0x1A) { Write-Host "ERROR: SMB.NES does not look like an iNES file."; exit 1 }

$payload = [byte[]]::new($prg.Length - 2)
[Array]::Copy($prg, 2, $payload, 0, $payload.Length)
if (0x0801 + $payload.Length -gt 0x9F00) { Write-Host "ERROR: the program is too large."; exit 1 }

# ---- Find the program's LOAD call: LDA #0 / LDX #0 / LDY #$A0 / JSR $FFD5 / BCC +14 ----
$pattern = [byte[]]@(0xA9, 0x00, 0xA2, 0x00, 0xA0, 0xA0, 0x20, 0xD5, 0xFF, 0x90, 0x0E)
$hits = @()
for ($i = 0; $i -le $payload.Length - $pattern.Length; $i++) {
    if ($payload[$i] -ne 0xA9) { continue }
    $same = $true
    for ($j = 1; $j -lt $pattern.Length; $j++) {
        if ($payload[$i + $j] -ne $pattern[$j]) { $same = $false; break }
    }
    if ($same) { $hits += $i }
}
if ($hits.Count -ne 1) { Write-Host "ERROR: expected exactly one LOAD call in the program, found $($hits.Count). This script is made for SMBX16.PRG."; exit 1 }
$pos = $hits[0]

# ---- Where the program expects to find itself after LOAD: end bank and end address in banked RAM ----
# LOAD starts at bank 1, address $A000; each bank holds 8192 bytes.
$nesLen = $nes.Length
$rem = $nesLen % 8192
if ($rem -eq 0) { Write-Host "ERROR: unsupported SMB.NES size."; exit 1 }
if (($rem -band 0x0F) -ne 0) { Write-Host "WARNING: SMB.NES size is not a multiple of 16; the program will probably reject it." }
$endBank = 1 + ($nesLen -shr 13)
if ($endBank -gt 200) { Write-Host "ERROR: SMB.NES is too large."; exit 1 }
$endAddr = 0xA000 + $rem
$endLo = $endAddr -band 0xFF
$endHi = $endAddr -shr 8

# Replacement for the LOAD call (same 11 bytes):
#   LDA #endBank / STA $00 / LDX #endLo / LDY #endHi / CLC / BCC +14  (success, no disk access)
$patch = [byte[]]@(0xA9, [byte]$endBank, 0x85, 0x00, 0xA2, [byte]$endLo, 0xA0, [byte]$endHi, 0x18, 0x90, 0x0E)
[Array]::Copy($patch, 0, $payload, $pos, $patch.Length)

# ---- Layout: [stub][boot block @ $100][program @ $400][SMB.NES] ----
$off1  = 0x400
$off2  = $off1 + $payload.Length
$total = $off2 + $nesLen
if ($payload.Length -gt 65535 -or $nesLen -gt 65535) { Write-Host "ERROR: file too large for this loader."; exit 1 }

$jobs = New-Object 'System.Collections.Generic.List[byte]'
$jobList = @(
    @($off1, 0x0801, $payload.Length, 0),
    @($off2, 0xA000, $nesLen, 1)
)
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
$jobBytes = $jobs.ToArray()

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
[Array]::Copy($nes, 0, $rom, $off2, $nesLen)

[System.IO.File]::WriteAllBytes($outFile, $rom)

Write-Host ("OK: {0} generated ({1} KB)." -f $outFile, ($size / 1024))
Write-Host ("  program: {0} bytes, SMB.NES: {1} bytes, used: {2} bytes" -f $payload.Length, $nesLen, $total)
Write-Host ("  LOAD call patched at 0x{0:X4}, end of NES data: bank {1}, 0x{2:X4}" -f ($pos + 0x0801), $endBank, $endAddr)
Write-Host ("  SHA256: {0}" -f (Get-FileHash -Algorithm SHA256 -Path $outFile).Hash)
