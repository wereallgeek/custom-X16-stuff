# X16 FastLoad

An Epyx FastLoad-style fast IEC loader for the **Commander X16** (ROM R49), written for use with the [MeatLoaf](https://github.com/idolpx/meatloaf) ESP32 drive emulator, which understands the Epyx FastLoad protocol.

> **Status:** confirmed working on real hardware, both as a cartridge and as the FASTROM build.

## What is it?

The X16's stock KERNAL loads from IEC devices byte by byte, which is slow. On the C64 the Epyx FastLoad cartridge fixes this, and MeatLoaf supports its protocol. This project is a from-scratch 65C02 port of that idea for the X16.

It hooks the KERNAL LOAD vector (`ILOAD`, `$0330`) and, for plain `LOAD "NAME",unit` calls, uploads the Epyx stage-1/stage-2 routines to the drive and receives the file at high speed. Everything else (verify, VRAM loads, headerless loads, tape, non-IEC devices, units owned by CMDR-DOS) is passed on to the normal KERNAL LOAD.

- Works with any device number >= 8 (not locked to device 8).
- Reports errors through STATUS so BASIC prints normal errors (FILE NOT FOUND, etc.).

There are two ways to use it:

| Variant | What it is | Cartridge slot |
|---|---|---|
| **Cartridge** (`EPYX16.BIN`) | 16 KB cartridge image (signature `CX16`) for ROM bank 32 | Used |
| **FASTROM** (`FASTROM-R49.BIN`) | Your R49 system ROM with the fastloader built in, made by `Make-FastRom.ps1` | Free for other cartridges |

## How to use

### Cartridge

1. Flash `EPYX16.BIN` (16384 bytes) to your flashable cartridge so it appears as ROM bank 32.
2. Connect Meatloaf trough IEC and turn it on.
3. Power on the X16 and type `LOAD "FILE",8` (or 9, 10, ...). Loads from MeatLoaf are now fast.

### FASTROM (no cartridge needed)

You need your own unmodified `ROM-R49.BIN` (the official `rom.bin`, 262144 bytes) and `EPYX16.BIN` (the fastload cartridge image). Put them next to the script and run:

```powershell
.\Make-FastRom.ps1
```

The script:

- pads the ROM to 512 KB (unused banks `$FF`) and stores the fastloader in ROM bank 31;
- the fastloader runs **directly from ROM**: nothing is copied to RAM, so programs that use RAM `$0400-$07FF` (e.g. CONCERTO) are not disturbed, and the fast LOAD keeps working after them. It keeps its variables in zero page `$02-$17` and restores them (and the registers) afterwards;
- adds a small boot stub and a few shared KERNAL-resident stubs in free KERNAL space ($AA fill); the normal `boot_cartridge` check of bank 32 stays untouched, so **other cartridges still work**;
- changes only the 7-character build id (`FAST` + a build letter + the first 2 characters of the original; edit `$BuildLetter` at the top of the script for each build you flash). The version number (e.g. R49) is **not** changed, so it never impersonates another release. The CX16 update tool will see it as different and let you flash it.

Flash the resulting `FASTROM-R49.BIN` to the system ROM (512 KB). Keep your original ROM to restore.

Note: both builds run from ROM. The cartridge only keeps 36 bytes of stubs in RAM `$0342-$0365` (an unused gap in the R49 KERNAL's low-RAM map, checked against the R49 ROM), so programs that use `$0400-$07FF` (e.g. CONCERTO) are not affected. The FASTROM variant keeps nothing in RAM.

## Disclaimer

Both the cartridge and ROM versions are tested on my hardware as working but I don't have your hardware. Use at your own risk and keep a backup of your original ROM. 
While this has been working for me, Kernal compatibility of other programs is not guaranteed to not be affected.
