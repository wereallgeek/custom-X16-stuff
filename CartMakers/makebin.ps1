$prgFile   = "$pwd\INPUT.PRG"
$outFile   = "$pwd\ROM1.BIN"
$forceSize = 0   # 0 = automatic (smallest power of two that fits); or force e.g. 131072

# Load the PRG and strip its 2-byte load address header
$prg = [System.IO.File]::ReadAllBytes($prgFile)
$payload = [byte[]]::new($prg.Length - 2)
[Array]::Copy($prg, 2, $payload, 0, $payload.Length)

# Compute where the copy must stop (high byte of the end address, rounded up to a page).
# The program is loaded at $0801 and can extend at most up to $9EFF (main RAM limit).
$endAddr = 0x0801 + $payload.Length
$endHi   = [byte](($endAddr + 255) -shr 8)
if ($endAddr -gt 0x9F00) {
    Write-Host "ERROR: program is too large ($($payload.Length) bytes). Maximum is $(0x9F00 - 0x0801) bytes."
    exit 1
}

# Choose the output size: smallest power of two (min 16 KB = one bank) that holds
# the stub, the boot code and the program (program starts at offset $A0)
$needed = 0xA0 + $payload.Length
if ($forceSize -gt 0) {
    $targetSize = $forceSize
} else {
    $targetSize = 16384
    while ($targetSize -lt $needed) { $targetSize *= 2 }
}
if ($needed -gt $targetSize) {
    Write-Host "ERROR: program does not fit in $targetSize bytes (needs $needed)."
    exit 1
}

# Code executed from RAM at $0500:
# copies the program from cartridge ROM ($C0A0, banks 32+) to $0801,
# then switches back to the KERNAL bank and jumps to $080D (SYS 2061 entry point)
$ramBoot = [byte[]]@(
    0xA9, 0x20, 0x85, 0x01,             # $0500: LDA #$20 ; STA $01  (select cartridge bank 32)
    0xA9, 0xA0, 0x85, 0x30,             # $0504: source low  = $A0
    0xA9, 0xC0, 0x85, 0x31,             # $0508: source high = $C0
    0xA9, 0x01, 0x85, 0x32,             # $050C: destination low  = $01
    0xA9, 0x08, 0x85, 0x33,             # $0510: destination high = $08
    0xA0, 0x00,                         # $0514: LDY #0
    # copy loop ($0516)
    0xB1, 0x30,                         # $0516: LDA ($30),Y
    0x91, 0x32,                         # $0518: STA ($32),Y
    0xE6, 0x30,                         # $051A: INC $30
    0xD0, 0x0A,                         # $051C: BNE $0528
    0xE6, 0x31,                         # $051E: INC $31
    0xD0, 0x06,                         # $0520: BNE $0528
    0xA9, 0xC0, 0x85, 0x31,             # $0522: source high = $C0 (window wrap)
    0xE6, 0x01,                         # $0526: INC $01 (next cartridge bank)
    # destination increment ($0528)
    0xE6, 0x32,                         # $0528: INC $32
    0xD0, 0x02,                         # $052A: BNE $052E
    0xE6, 0x33,                         # $052C: INC $33
    0xA5, 0x33, 0xC9, $endHi,           # $052E: LDA $33 ; CMP #endHi  (stop at end of program)
    0xD0, 0xE2,                         # $0532: BNE $0516
    # done: back to KERNAL bank, enable interrupts, run the program
    0xA9, 0x00, 0x85, 0x01,             # $0534: LDA #0 ; STA $01
    0x58,                               # $0538: CLI
    0x4C, 0x0D, 0x08                    # $0539: JMP $080D
)

$ramLen = [byte]$ramBoot.Length

# ROM stub at $C000 (bank 32): the KERNAL jumps to $C004 if it finds "CX16" at $C000.
# It copies $ramBoot to $0500 in RAM and jumps there.
$romStub = [byte[]]@(
    0x43, 0x58, 0x31, 0x36,             # $C000: "CX16" signature
    0x78,                               # $C004: SEI
    0xA2, 0xFF, 0x9A,                   # $C005: LDX #$FF ; TXS
    0xA2, 0x00,                         # $C008: LDX #0
    0xBD, 0x18, 0xC0,                   # $C00A: LDA $C018,X
    0x9D, 0x00, 0x05,                   # $C00D: STA $0500,X
    0xE8,                               # $C010: INX
    0xE0, $ramLen,                      # $C011: CPX #length of $ramBoot
    0xD0, 0xF5,                         # $C013: BNE $C00A
    0x4C, 0x00, 0x05                    # $C015: JMP $0500
)

# Build the ROM image: fill with $FF, then place stub, RAM code and program
$rom = [byte[]]::new($targetSize)
for ($i = 0; $i -lt $targetSize; $i++) { $rom[$i] = 0xFF }
[Array]::Copy($romStub, 0, $rom, 0x00, $romStub.Length)
[Array]::Copy($ramBoot, 0, $rom, 0x18, $ramBoot.Length)
[Array]::Copy($payload, 0, $rom, 0xA0, $payload.Length)

[System.IO.File]::WriteAllBytes($outFile, $rom)
Write-Host ("OK: {0} generated ({1} KB, program = {2} bytes)." -f $outFile, ($targetSize / 1024), $payload.Length)
