# makebinmenu.ps1
# Builds a multi-program cartridge image for the Commander X16.
# Put this script in a folder with your .PRG files and run it.
# Every .PRG found becomes an entry in a boot menu (keys 1-9, then A, B, C...).
# Press ESC at the menu to exit to BASIC (asks for confirmation with Y/N).
# Output: ROM1.BIN, sized automatically to the smallest power-of-two chip that fits.
#
# Requirements for each PRG: it must load at $0801 or higher and end before $9F00.
# If it has a standard BASIC "SYS nnnn" line at $0801, nnnn is used as the start address,
# otherwise the load address is used.

$outFile   = "$pwd\ROM1.BIN"
$title     = "COMMANDER X16 MENU"   # ASCII only
$forceSize = 0                       # 0 = automatic; or force e.g. 131072 (128 KB)

$files = @(Get-ChildItem -Path "$pwd" -Filter "*.PRG" | Where-Object { $_.Extension -ieq ".prg" } | Sort-Object Name)
if ($files.Count -eq 0) { Write-Host "ERROR: no .PRG files found in $pwd"; exit 1 }
if ($files.Count -gt 28) { Write-Host "ERROR: too many programs ($($files.Count)); maximum is 28."; exit 1 }

# Code executed from RAM at $0500 (assembled and tested separately):
# shows the menu, waits for a key (ESC = exit to BASIC after Y/N confirmation), copies the chosen program from cartridge ROM to RAM
# (with interrupts off while a cartridge bank is mapped), then runs it.
# Data follows the code: count (1 byte), text pointer (2 bytes), then the program table.
$menuCode = [byte[]]@(
    0xA9, 0x00,                       # $0500: LDA #$00
    0x85, 0x01,                       # $0502: STA $01
    0x58,                             # $0504: CLI
    0xA9, 0x8E,                       # $0505: LDA #$8E
    0x20, 0xD2, 0xFF,                 # $0507: JSR $FFD2
    0xA9, 0x93,                       # $050A: LDA #$93
    0x20, 0xD2, 0xFF,                 # $050C: JSR $FFD2
    0xAD, 0x10, 0x06,                 # $050F: LDA textptr
    0x85, 0x3A,                       # $0512: STA $3A
    0xAD, 0x11, 0x06,                 # $0514: LDA textptr+1
    0x85, 0x3B,                       # $0517: STA $3B
    0x20, 0xE6, 0x05,                 # $0519: JSR print
    0x20, 0xE4, 0xFF,                 # $051C: JSR $FFE4
    0xC9, 0x00,                       # $051F: CMP #$00
    0xF0, 0xF9,                       # $0521: BEQ wait
    0xC9, 0x1B,                       # $0523: CMP #$1B
    0xD0, 0x03,                       # $0525: BNE n1
    0x4C, 0xC0, 0x05,                 # $0527: JMP esc
    0xC9, 0x03,                       # $052A: CMP #$03
    0xD0, 0x03,                       # $052C: BNE n2
    0x4C, 0xC0, 0x05,                 # $052E: JMP esc
    0xC9, 0x31,                       # $0531: CMP #$31
    0x90, 0xE7,                       # $0533: BCC wait
    0xC9, 0x3A,                       # $0535: CMP #$3A
    0x90, 0x0D,                       # $0537: BCC digit
    0xC9, 0x41,                       # $0539: CMP #$41
    0x90, 0xDF,                       # $053B: BCC wait
    0xC9, 0x5B,                       # $053D: CMP #$5B
    0xB0, 0xDB,                       # $053F: BCS wait
    0x38,                             # $0541: SEC
    0xE9, 0x38,                       # $0542: SBC #$38
    0xD0, 0x03,                       # $0544: BNE chk
    0x38,                             # $0546: SEC
    0xE9, 0x31,                       # $0547: SBC #$31
    0xCD, 0x0F, 0x06,                 # $0549: CMP count
    0xB0, 0xCE,                       # $054C: BCS wait
    0x85, 0x39,                       # $054E: STA $39
    0xA9, 0x93,                       # $0550: LDA #$93
    0x20, 0xD2, 0xFF,                 # $0552: JSR $FFD2
    0xA5, 0x39,                       # $0555: LDA $39
    0x0A,                             # $0557: ASL A
    0x0A,                             # $0558: ASL A
    0x0A,                             # $0559: ASL A
    0x18,                             # $055A: CLC
    0x65, 0x39,                       # $055B: ADC $39
    0xAA,                             # $055D: TAX
    0x78,                             # $055E: SEI
    0xBD, 0x12, 0x06,                 # $055F: LDA table,X
    0x85, 0x38,                       # $0562: STA $38
    0xBD, 0x13, 0x06,                 # $0564: LDA table+1,X
    0x85, 0x30,                       # $0567: STA $30
    0xBD, 0x14, 0x06,                 # $0569: LDA table+2,X
    0x85, 0x31,                       # $056C: STA $31
    0xBD, 0x15, 0x06,                 # $056E: LDA table+3,X
    0x85, 0x34,                       # $0571: STA $34
    0xBD, 0x16, 0x06,                 # $0573: LDA table+4,X
    0x85, 0x35,                       # $0576: STA $35
    0xBD, 0x17, 0x06,                 # $0578: LDA table+5,X
    0x85, 0x32,                       # $057B: STA $32
    0xBD, 0x18, 0x06,                 # $057D: LDA table+6,X
    0x85, 0x33,                       # $0580: STA $33
    0xBD, 0x19, 0x06,                 # $0582: LDA table+7,X
    0x85, 0x36,                       # $0585: STA $36
    0xBD, 0x1A, 0x06,                 # $0587: LDA table+8,X
    0x85, 0x37,                       # $058A: STA $37
    0xA0, 0x00,                       # $058C: LDY #$00
    0xA5, 0x38,                       # $058E: LDA $38
    0x85, 0x01,                       # $0590: STA $01
    0xB1, 0x30,                       # $0592: LDA ($30),Y
    0x91, 0x32,                       # $0594: STA ($32),Y
    0xE6, 0x30,                       # $0596: INC $30
    0xD0, 0x0A,                       # $0598: BNE nosrc
    0xE6, 0x31,                       # $059A: INC $31
    0xD0, 0x06,                       # $059C: BNE nosrc
    0xA9, 0xC0,                       # $059E: LDA #$C0
    0x85, 0x31,                       # $05A0: STA $31
    0xE6, 0x01,                       # $05A2: INC $01
    0xE6, 0x32,                       # $05A4: INC $32
    0xD0, 0x02,                       # $05A6: BNE nodst
    0xE6, 0x33,                       # $05A8: INC $33
    0xA5, 0x34,                       # $05AA: LDA $34
    0xD0, 0x02,                       # $05AC: BNE declo
    0xC6, 0x35,                       # $05AE: DEC $35
    0xC6, 0x34,                       # $05B0: DEC $34
    0xA5, 0x34,                       # $05B2: LDA $34
    0x05, 0x35,                       # $05B4: ORA $35
    0xD0, 0xDA,                       # $05B6: BNE cloop
    0xA9, 0x00,                       # $05B8: LDA #$00
    0x85, 0x01,                       # $05BA: STA $01
    0x4C, 0xE0, 0x07,                 # $05BC: JMP launch   (launch routine at $07E0, see $launch below)
    0xEA,                             # $05BF: NOP (unused)
    0xA9, 0xF8,                       # $05C0: LDA #<confirm
    0x85, 0x3A,                       # $05C2: STA $3A
    0xA9, 0x05,                       # $05C4: LDA #>confirm
    0x85, 0x3B,                       # $05C6: STA $3B
    0x20, 0xE6, 0x05,                 # $05C8: JSR print
    0x20, 0xE4, 0xFF,                 # $05CB: JSR $FFE4
    0xC9, 0x00,                       # $05CE: CMP #$00
    0xF0, 0xF9,                       # $05D0: BEQ cwait
    0xC9, 0x59,                       # $05D2: CMP #$59
    0xF0, 0x07,                       # $05D4: BEQ exit
    0xC9, 0xD9,                       # $05D6: CMP #$D9
    0xF0, 0x03,                       # $05D8: BEQ exit
    0x4C, 0x00, 0x05,                 # $05DA: JMP start
    0xA9, 0x93,                       # $05DD: LDA #$93
    0x20, 0xD2, 0xFF,                 # $05DF: JSR $FFD2
    0x38,                             # $05E2: SEC
    0x4C, 0x47, 0xFF,                 # $05E3: JMP $FF47
    0xA0, 0x00,                       # $05E6: LDY #$00
    0xB1, 0x3A,                       # $05E8: LDA ($3A),Y
    0xF0, 0x0B,                       # $05EA: BEQ pdone
    0x20, 0xD2, 0xFF,                 # $05EC: JSR $FFD2
    0xE6, 0x3A,                       # $05EF: INC $3A
    0xD0, 0xF3,                       # $05F1: BNE print
    0xE6, 0x3B,                       # $05F3: INC $3B
    0xD0, 0xEF,                       # $05F5: BNE print
    0x60,                             # $05F7: RTS
    0x0D, 0x0D,                       # $05F8: .byte $0D,$0D
    0x45, 0x58, 0x49, 0x54, 0x20, 0x54, 0x4F, 0x20, 0x42, 0x41, 0x53, 0x49, 0x43, 0x3F, 0x20, 0x28, 0x59, 0x2F, 0x4E, 0x29, # $05FA: .ascii "EXIT TO BASIC? (Y/N)"
    0x00                              # $060E: .byte 0
)

# Launch routine, stored at $07E0 (end of the boot block). Before starting the program it pushes a
# return address, so a program that ends with RTS (e.g. MOD.PRG) comes back to the "exit" code at $05DD
# (clear screen + cold start BASIC) instead of jumping to garbage.
$launch = [byte[]]@(
    0xA9, 0x05,                       # $07E0: LDA #>(exit-1)
    0x48,                             # $07E2: PHA
    0xA9, 0xDC,                       # $07E3: LDA #<(exit-1)
    0x48,                             # $07E5: PHA
    0x58,                             # $07E6: CLI
    0x6C, 0x36, 0x00                  # $07E7: JMP ($0036)
)
$launchOff = 0x2E0

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

$keys     = "123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
$romOff   = 0x400                    # programs start here (offset in the cartridge image)
$table    = New-Object 'System.Collections.Generic.List[byte]'
$menuText = $title + "`r`r"
$prgs     = @()
$offsets  = @()
$infoLines = @()
$idx      = 0

foreach ($f in $files) {
    $prg = [System.IO.File]::ReadAllBytes($f.FullName)
    if ($prg.Length -lt 3) { Write-Host "ERROR: $($f.Name) is too small."; exit 1 }

    $load = $prg[0] + 256 * $prg[1]
    $len  = $prg.Length - 2

    # Start address: the number in a "SYS nnnn" BASIC line if present, else the load address
    $entry = $load
    if ($load -eq 0x0801 -and $prg.Length -gt 10 -and $prg[6] -eq 0x9E) {
        $p = 7
        while ($p -lt $prg.Length -and $prg[$p] -eq 0x20) { $p++ }
        $num = 0
        $digits = 0
        while ($p -lt $prg.Length -and $prg[$p] -ge 0x30 -and $prg[$p] -le 0x39) {
            $num = $num * 10 + ($prg[$p] - 0x30)
            $p++
            $digits++
        }
        if ($digits -gt 0) { $entry = $num }
    }

    if ($load -lt 0x0801) { Write-Host ("ERROR: {0} loads at 0x{1:X4}; it must load at 0x0801 or higher." -f $f.Name, $load); exit 1 }
    if ($load + $len -gt 0x9F00) { Write-Host "ERROR: $($f.Name) is too large (ends past 0x9EFF)."; exit 1 }
    if ($entry -lt 0x0801 -or $entry -ge 0x9F00) { Write-Host ("ERROR: {0} has an invalid start address 0x{1:X4}." -f $f.Name, $entry); exit 1 }

    $bank = 32 + ($romOff -shr 14)
    $addr = 0xC000 + ($romOff -band 0x3FFF)

    # Table entry (9 bytes): bank, source lo/hi, length lo/hi, load lo/hi, start lo/hi
    $table.Add([byte]$bank)
    $table.Add([byte]($addr -band 0xFF))
    $table.Add([byte](($addr -shr 8) -band 0xFF))
    $table.Add([byte]($len -band 0xFF))
    $table.Add([byte](($len -shr 8) -band 0xFF))
    $table.Add([byte]($load -band 0xFF))
    $table.Add([byte](($load -shr 8) -band 0xFF))
    $table.Add([byte]($entry -band 0xFF))
    $table.Add([byte](($entry -shr 8) -band 0xFF))

    # Menu label: file name without extension, restricted to characters safe in PETSCII
    $name = [System.IO.Path]::GetFileNameWithoutExtension($f.Name).ToUpper()
    $name = $name -replace '[^A-Z0-9 .\-]', '-'
    if ($name.Length -gt 30) { $name = $name.Substring(0, 30) }
    $menuText = $menuText + $keys.Substring($idx, 1) + " " + $name + "`r"

    $prgs    += ,$prg
    $offsets += $romOff
    $infoLines += ("  {0}  {1,-30} {2,6} bytes, start 0x{3:X4}" -f $keys.Substring($idx, 1), $name, $len, $entry)

    $romOff += $len
    $idx++
}
$menuText = $menuText + "`rPRESS A KEY"

# Choose the output size: smallest power of two (min 16 KB) that holds everything
$total = $romOff
if ($total -gt (224 * 16384)) { Write-Host "ERROR: programs do not fit in the 3.5 MB cartridge space."; exit 1 }
if ($forceSize -gt 0) {
    $size = $forceSize
} else {
    $size = 16384
    while ($size -lt $total) { $size = $size * 2 }
}
if ($size -lt $total) { Write-Host "ERROR: programs need $total bytes but the image is only $size bytes."; exit 1 }

# Build the 768-byte boot block: code, count, text pointer, table, menu text
$ascii = [System.Text.Encoding]::ASCII.GetBytes($menuText)
$textBytes = [byte[]]::new($ascii.Length + 1)       # last byte stays 0 (terminator)
[Array]::Copy($ascii, 0, $textBytes, 0, $ascii.Length)

$tableArr  = $table.ToArray()
$tableOff  = $menuCode.Length + 3
$textAddr  = 0x0500 + $tableOff + $tableArr.Length
$blockSize = 768
$used      = $tableOff + $tableArr.Length + $textBytes.Length
if ($used -gt $launchOff) { Write-Host "ERROR: menu too big ($used bytes, max $launchOff). Use fewer or shorter names."; exit 1 }

$block = [byte[]]::new($blockSize)
[Array]::Copy($menuCode, 0, $block, 0, $menuCode.Length)
$block[$menuCode.Length]     = [byte]$files.Count
$block[$menuCode.Length + 1] = [byte]($textAddr -band 0xFF)
$block[$menuCode.Length + 2] = [byte](($textAddr -shr 8) -band 0xFF)
[Array]::Copy($launch, 0, $block, $launchOff, $launch.Length)
[Array]::Copy($tableArr, 0, $block, $tableOff, $tableArr.Length)
[Array]::Copy($textBytes, 0, $block, $tableOff + $tableArr.Length, $textBytes.Length)

# Build the ROM image: fill with $FF, then stub, boot block, and the programs (without their 2-byte headers)
$rom = [byte[]]::new($size)
for ($i = 0; $i -lt $size; $i++) { $rom[$i] = 0xFF }
[Array]::Copy($romStub, 0, $rom, 0, $romStub.Length)
[Array]::Copy($block, 0, $rom, 0x100, $blockSize)
for ($k = 0; $k -lt $prgs.Count; $k++) {
    [Array]::Copy($prgs[$k], 2, $rom, $offsets[$k], $prgs[$k].Length - 2)
}

[System.IO.File]::WriteAllBytes($outFile, $rom)

Write-Host ("OK: {0} generated ({1} KB, {2} programs)." -f $outFile, ($size / 1024), $files.Count)
foreach ($line in $infoLines) { Write-Host $line }
