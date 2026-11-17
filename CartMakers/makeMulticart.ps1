# makeMulticart.ps1
# Builds a Commander X16 cartridge image (menu + programs) from a settings file.
#
# Usage:          .\makeMulticart.ps1                  (reads multicart.cfg in the current folder)
#                 .\makeMulticart.ps1 other.cfg
# The .PRG / data files are looked up in the folder of the .cfg file.
param([string]$ConfigFile = "multicart.cfg")

$ErrorActionPreference = 'Stop'

# ---------------- embedded code (menu, boot stub) ----------------
$MENU_HEX = '4C05040000A9008530A9C58531A9008532A9808533AD03048534AD04048535A9208538A900850020B805A9008501AD259F29FD8D259FAD2C9F8541AD0A80C9FFF00418205FFFAD0B80C9FFF0038D2C9F58A9008539853CAD098020D2FFAD0D80853EAD0E80853F20FC05203A0620E4FFC900F0F9C911F015C991F031C90DF00AC91BF04CC903F04880E34C1E05A539186901CD00809008A9008539853C80CB853938E53CCD018090C1E63C80BDA539F00CC639A539C53CB0B1853C80ADAD008038E9018539AD008038ED0180853C809AAD0C80D0034C6D04AD0F80853EAD1080853F20FC0520E4FFC900F0F9C959F014C9D9F010AD1180853EAD1280853F20FC054C6D04201005782081FF58384C47FFAD259F29FD8D259FA5418D2C9F60A5390A0A186D1580853EAD16806900853FA000B13EAAC8B13E48C8B13E8543C8B13E854468853F863EA000B13E998007C8C080D0F6201005782081FF78A200208F05A5340535F00D20B805E8E8E8E8E8E8E8E880EAA9008501A221BDB7069D4001CA10F7A5438D6001A5448D61014C4001BD80078530BD81078531BD82078532BD83078533BD84078534BD85078535BD86078538BD8707850060A000A5388501B1309132E630D00AE631D006A9C08531E601E632D00EE633A533C9C0D006A9A08533E600A534D002C635C634A5340535D0CE60A000B13EE63ED002E63F6020F105C9FEF00520D2FF80F420F105C901F005C902F0126020F105854220F105A8A6421820F0FF80D720F105854020F1058542A54220D2FFC640D0F780C2A900853AA53C18653A853BAD048018653AAAAC03801820F0FFA53BC539F010AD068020D2FFA90120D2FFAD0580800EAD088020D2FFA90120D2FFAD078020D2FFAD1380853EAD1480853FA63BF00FA53E186D0280853E9002E63FCAD0F1AD02808540A000B13E20D2FFE63ED002E63FC640D0F1E63AA53ACD0180D08860A900AA9D00049D00059D00069D0007E8D0F1A2209530CA10FB85008D99A8584C0000'
$STUB_HEX = '4358313678A2FF9AA200BD00C19D0004BD00C29D0005BD00C39D0006BD00C49D0007E8D0E54C0004'
$MENU_LEN = 729
$STAGE_HDR = 24

function HexToBytes([string]$h) {
    $r = New-Object 'byte[]' ($h.Length / 2)
    for ($i = 0; $i -lt $r.Length; $i++) { $r[$i] = [Convert]::ToByte($h.Substring($i * 2, 2), 16) }
    return ,$r
}

function Fail([string]$msg) { throw ("ERROR: " + $msg) }

$ColorNames = @{ 'black'=0; 'white'=1; 'red'=2; 'cyan'=3; 'purple'=4; 'green'=5; 'blue'=6; 'yellow'=7; 'orange'=8; 'brown'=9;
    'lightred'=10; 'darkgray'=11; 'darkgrey'=11; 'gray'=12; 'grey'=12; 'lightgreen'=13; 'lightgray'=15; 'lightgrey'=15; 'lightblue'=14 }
$ColCode = @(0x90,0x05,0x1C,0x9F,0x9C,0x1E,0x1F,0x9E,0x81,0x95,0x96,0x97,0x98,0x99,0x9A,0x9B)

# ---------------- reading the settings file ----------------
if (-not (Test-Path -LiteralPath $ConfigFile)) { Fail "settings file not found: $ConfigFile" }
$ConfigPath = (Resolve-Path -LiteralPath $ConfigFile).Path
$BaseDir = Split-Path -Parent $ConfigPath

$cfg = @{}
$progLines = New-Object System.Collections.ArrayList
$section = ''
foreach ($raw in [IO.File]::ReadAllLines($ConfigPath)) {
    $line = $raw.Trim()
    if ($line.Length -eq 0) { continue }
    if ($line.StartsWith(';') -or $line.StartsWith('#')) { continue }
    if ($line.StartsWith('[') -and $line.EndsWith(']')) { $section = $line.Substring(1, $line.Length - 2).Trim().ToLower(); continue }
    if ($section -eq 'programs') { [void]$progLines.Add($line); continue }
    $eq = $line.IndexOf('=')
    if ($eq -lt 1) { Fail "invalid line (expected: key = value): $line" }
    $cfg[$section + '.' + $line.Substring(0, $eq).Trim().ToLower()] = $line.Substring($eq + 1).Trim()
}

function CfgGet([string]$key, [string]$default) { if ($cfg.ContainsKey($key)) { return $cfg[$key] } else { return $default } }
function CfgInt([string]$key, [int]$default, [int]$lo, [int]$hi) {
    if (-not $cfg.ContainsKey($key)) { return $default }
    $v = $cfg[$key]
    if ($v -notmatch '^-?\d+$') { Fail "$key must be a number" }
    $n = [int]$v
    if ($n -lt $lo -or $n -gt $hi) { Fail "$key must be between $lo and $hi" }
    return $n
}
function CfgColor([string]$key, [int]$default) {
    if (-not $cfg.ContainsKey($key)) { return $default }
    $v = $cfg[$key].ToLower()
    if ($ColorNames.ContainsKey($v)) { return [int]$ColorNames[$v] }
    if ($v -match '^\d+$' -and [int]$v -lt 16) { return [int]$v }
    Fail "$key : unknown color '$($cfg[$key])'"
}
function CfgBool([string]$key, [bool]$default) {
    if (-not $cfg.ContainsKey($key)) { return $default }
    $v = $cfg[$key].ToLower()
    if ($v -eq 'yes' -or $v -eq 'true' -or $v -eq '1' -or $v -eq 'on') { return $true }
    if ($v -eq 'no' -or $v -eq 'false' -or $v -eq '0' -or $v -eq 'off') { return $false }
    Fail "$key must be yes or no"
}

$outName = CfgGet 'cartridge.output' 'ROM1.BIN'
$title = CfgGet 'cartridge.title' 'Cartridge Title'

$modeName = (CfgGet 'screen.mode' '80x60').ToLower()
switch ($modeName) {
    '80x60'   { $modeByte = 0;   $cols = 80; $rows = 60 }
    '80x30'   { $modeByte = 1;   $cols = 80; $rows = 30 }
    '40x60'   { $modeByte = 2;   $cols = 40; $rows = 60 }
    '40x30'   { $modeByte = 3;   $cols = 40; $rows = 30 }
    'default' { $modeByte = 255; $cols = 80; $rows = 60 }
    default   { Fail "screen.mode must be 80x60, 80x30, 40x60, 40x30 or default" }
}
$charset = (CfgGet 'screen.charset' 'upper').ToLower()
if ($charset -ne 'upper' -and $charset -ne 'lower') { Fail "screen.charset must be upper or lower" }
$scrBg = CfgColor 'screen.background' 6
$scrFg = CfgColor 'screen.text' 14
$bv = (CfgGet 'screen.border' 'default').ToLower()
if ($bv -eq 'default') { $border = 255 } else { $border = CfgColor 'screen.border' 0 }

if ($cols -ge 80) { $margin = 4 } else { $margin = 2 }
if ($rows -ge 60) { $ymargin = 3 } else { $ymargin = 2 }
$bx = CfgInt 'box.x' $margin 0 ($cols - 1)
$by = CfgInt 'box.y' $ymargin 0 ($rows - 1)
$bw = CfgInt 'box.width' ($cols - 2 * $bx) 20 $cols
$bh = CfgInt 'box.height' ($rows - 2 * $by) 10 $rows
if (($bx + $bw) -gt $cols -or ($by + $bh) -gt $rows) { Fail "the box does not fit on a $cols x $rows screen" }
if (($bx + $bw) -eq $cols -and ($by + $bh) -eq $rows) { Fail "the box must not touch the bottom-right corner of the screen (it would scroll); make it one row or column smaller" }
$panel = CfgColor 'box.background' 14
$boxText = CfgColor 'box.text' 1
$frame = (CfgGet 'box.frame' 'white').ToLower()
$frameOn = ($frame -ne 'none')
if ($frameOn) { $frameCol = CfgColor 'box.frame' 1 } else { $frameCol = 1 }
$banner = (CfgGet 'box.banner' 'red').ToLower()
$bannerOn = ($banner -ne 'none')
if ($bannerOn) { $bannerCol = CfgColor 'box.banner' 2 } else { $bannerCol = $panel }
$tcol = CfgColor 'box.title_color' 1
$tbg = CfgColor 'box.title_background' $panel
$allowExit = CfgBool 'menu.allow_exit' $true
$mx = CfgInt 'menu.x' ($bx + 3) 0 ($cols - 1)
$my = CfgInt 'menu.y' ($by + 3) 0 ($rows - 1)
$mw = CfgInt 'menu.width' ($bw - 6) 5 $cols
$mrows = CfgInt 'menu.rows' ($bh - 7) 1 $rows
$ntext = CfgColor 'menu.text' $boxText
$nbg = CfgColor 'menu.background' $panel
$stext = CfgColor 'menu.selected_text' $panel
$sbg = CfgColor 'menu.selected_background' 1
$footerDefault = 'UP/DOWN: SELECT   ENTER: START'
if ($allowExit) { $footerDefault += '   ESC: BASIC' }
$footer = CfgGet 'menu.footer' $footerDefault
if ($footer.Length -eq 0) { $footer = $footerDefault }
$fcol = CfgColor 'menu.footer_color' $boxText
if (($mx + $mw) -gt $cols -or ($my + $mrows) -gt $rows) { Fail "the menu does not fit on the screen" }

# ---------------- program list ----------------
$loaders = @{
    'smbx16'  = @{ pat = (HexToBytes 'A900A200A0A020D5FF900E'); tail = (HexToBytes '189 00E'.Replace(' ','')) }
    'smb3x16' = @{ pat = (HexToBytes 'A901850 0A900A200A0A04CD5FF'.Replace(' ','')); tail = (HexToBytes '1860EAEAEA') }
}
$entries = New-Object System.Collections.ArrayList
foreach ($pl in $progLines) {
    $parts = @($pl.Split('|') | ForEach-Object { $_.Trim() })
    if ($parts.Count -lt 2 -or $parts[0] -eq '' -or $parts[1] -eq '') { Fail "invalid program line (format: Name | FILE.PRG): $pl" }
    $e = @{ label = $parts[0]; prg = $parts[1]; data = ''; loader = '' }
    if ($parts.Count -gt 2) { $e.data = $parts[2] }
    if ($parts.Count -gt 3) { $e.loader = $parts[3].ToLower() }
    if ($e.data -ne '' -and $e.loader -eq '') { Fail "$($e.label): a data file needs a loader (smbx16 or smb3x16)" }
    if ($e.loader -ne '' -and -not $loaders.ContainsKey($e.loader)) { Fail "$($e.label): unknown loader '$($e.loader)' (smbx16 or smb3x16)" }
    [void]$entries.Add($e)
}
$count = $entries.Count
if ($count -eq 0) { Fail "no programs listed in the [programs] section" }
if ($count -gt 60) { Fail "too many programs (max 60)" }
if ($count -lt $mrows) { $rowsEff = $count } else { $rowsEff = $mrows }

# ---------------- text -> PETSCII ----------------
function ToPetscii([string]$s) {
    $out = New-Object System.Collections.Generic.List[byte]
    foreach ($ch in $s.ToCharArray()) {
        $o = [int]$ch
        if ($ch -cge 'a' -and $ch -cle 'z') { [void]$out.Add([byte]($o - 32)) }
        elseif ($ch -cge 'A' -and $ch -cle 'Z') {
            if ($charset -eq 'upper') { [void]$out.Add([byte]$o) } else { [void]$out.Add([byte]($o + 128)) }
        }
        elseif (' !"#$%&''()*+,-./0123456789:;<=>?@[]'.IndexOf($ch) -ge 0) { [void]$out.Add([byte]$o) }
        else { [void]$out.Add([byte]0x3F) }
    }
    return ,($out.ToArray())
}

# ---------------- small display scripts (run by the menu) ----------------
function S-Colors($l, [int]$fg, [int]$bg) { [void]$l.Add([byte]$ColCode[$bg]); [void]$l.Add([byte]1); [void]$l.Add([byte]$ColCode[$fg]) }
function S-Plot($l, [int]$r, [int]$c) { [void]$l.Add([byte]0xFE); [void]$l.Add([byte]1); [void]$l.Add([byte]$r); [void]$l.Add([byte]$c) }
function S-Rep($l, [int]$n, [int]$ch) {
    while ($n -gt 0) {
        $k = [Math]::Min($n, 255)
        [void]$l.Add([byte]0xFE); [void]$l.Add([byte]2); [void]$l.Add([byte]$k); [void]$l.Add([byte]$ch)
        $n -= $k
    }
}
function S-End($l) { [void]$l.Add([byte]0xFE); [void]$l.Add([byte]0) }
function S-Add($l, [byte[]]$b) { if ($b.Length -gt 0) { $l.AddRange($b) } }

$sinit = New-Object System.Collections.Generic.List[byte]
S-Colors $sinit $scrFg $scrBg
[void]$sinit.Add([byte]0x93)
for ($r = 0; $r -lt $bh; $r++) {
    S-Plot $sinit ($by + $r) $bx
    if ($r -eq 0 -and $bannerOn) { S-Colors $sinit $boxText $bannerCol } else { S-Colors $sinit $boxText $panel }
    S-Rep $sinit $bw 0x20
}
$ttext = ToPetscii $title
$tab = New-Object System.Collections.Generic.List[byte]
foreach ($b in @(0x20, 0xC0, 0x20)) { [void]$tab.Add([byte]$b) }
S-Add $tab $ttext
foreach ($b in @(0x20, 0xC0, 0x20)) { [void]$tab.Add([byte]$b) }
if ($tab.Count -gt ($bw - 4)) { Fail "the title is too long for the box" }
$tabx = $bx + [int][Math]::Floor(($bw - $tab.Count) / 2)
S-Plot $sinit $by $tabx
S-Colors $sinit $tcol $tbg
S-Add $sinit $tab.ToArray()
if ($frameOn) {
    $fx = $bx + 1; $fy = $by + 1; $fw = $bw - 2; $fh = $bh - 2
    if ($charset -eq 'upper') { $tl = 0xD5; $tr = 0xC9; $bl = 0xCA; $br = 0xCB } else { $tl = 0xB0; $tr = 0xAE; $bl = 0xAD; $br = 0xBD }
    S-Colors $sinit $frameCol $panel
    S-Plot $sinit $fy $fx; [void]$sinit.Add([byte]$tl); S-Rep $sinit ($fw - 2) 0xC0; [void]$sinit.Add([byte]$tr)
    for ($r = $fy + 1; $r -lt ($fy + $fh - 1); $r++) {
        S-Plot $sinit $r $fx; [void]$sinit.Add([byte]0xDD)
        S-Plot $sinit $r ($fx + $fw - 1); [void]$sinit.Add([byte]0xDD)
    }
    S-Plot $sinit ($fy + $fh - 1) $fx; [void]$sinit.Add([byte]$bl); S-Rep $sinit ($fw - 2) 0xC0; [void]$sinit.Add([byte]$br)
}
$footerRow = $by + $bh - 3
$confirmText = 'EXIT TO BASIC? (Y/N)'
$padw = [Math]::Max($footer.Length, $confirmText.Length)
$ftxt = ToPetscii ($footer.PadRight($padw))
$ctxt = ToPetscii ($confirmText.PadRight($padw))
S-Plot $sinit $footerRow $mx; S-Colors $sinit $fcol $panel; S-Add $sinit $ftxt; S-End $sinit
$sconf = New-Object System.Collections.Generic.List[byte]
S-Plot $sconf $footerRow $mx; S-Colors $sconf $stext $sbg; S-Add $sconf $ctxt; S-End $sconf
$sunconf = New-Object System.Collections.Generic.List[byte]
S-Plot $sunconf $footerRow $mx; S-Colors $sunconf $fcol $panel; S-Add $sunconf $ftxt; S-End $sunconf

# ---------------- entry names ----------------
$names = New-Object System.Collections.Generic.List[byte]
foreach ($e in $entries) {
    $t = ToPetscii $e.label
    if ($t.Length -gt ($mw - 2)) {
        Write-Host ("Warning: '" + $e.label + "' is truncated to " + ($mw - 2) + " characters")
        $t = $t[0..($mw - 3)]
    }
    [void]$names.Add([byte]0x20)
    S-Add $names ([byte[]]$t)
    for ($i = 0; $i -lt ($mw - 1 - $t.Length); $i++) { [void]$names.Add([byte]0x20) }
}

# ---------------- loading the files ----------------
$CHUNK = 7 * 8192
foreach ($e in $entries) {
    $p = Join-Path $BaseDir $e.prg
    if (-not (Test-Path -LiteralPath $p)) { Fail "file not found: $($e.prg)" }
    $prg = [IO.File]::ReadAllBytes($p)
    if ($prg.Length -lt 3) { Fail "$($e.prg) is too small" }
    $load = $prg[0] + 256 * $prg[1]
    $ln = $prg.Length - 2
    $entry = $load
    if ($load -eq 0x0801 -and $prg.Length -gt 10 -and $prg[6] -eq 0x9E) {
        $q = 7
        while ($q -lt $prg.Length -and $prg[$q] -eq 0x20) { $q++ }
        $num = 0; $dig = 0
        while ($q -lt $prg.Length -and $prg[$q] -ge 0x30 -and $prg[$q] -le 0x39) { $num = $num * 10 + $prg[$q] - 0x30; $q++; $dig++ }
        if ($dig -gt 0) { $entry = $num }
    }
    if ($load -lt 0x0801) { Fail ("{0} loads at `${1:X4}; it must load at `$0801 or higher" -f $e.prg, $load) }
    if (($load + $ln) -gt 0x9F00) { Fail "$($e.prg) is too large (ends past `$9EFF)" }
    if ($entry -lt 0x0801 -or $entry -ge 0x9F00) { Fail ("{0}: invalid start address `${1:X4}" -f $e.prg, $entry) }
    $payload = New-Object 'byte[]' $ln
    [Array]::Copy($prg, 2, $payload, 0, $ln)
    $e.load = $load; $e.entry = $entry; $e.dataBytes = $null
    if ($e.data -ne '') {
        $dp = Join-Path $BaseDir $e.data
        if (-not (Test-Path -LiteralPath $dp)) { Fail "file not found: $($e.data)" }
        $db = [IO.File]::ReadAllBytes($dp)
        if ($db.Length -lt 1) { Fail "$($e.data) is empty" }
        $pat = $loaders[$e.loader].pat
        $tailp = $loaders[$e.loader].tail
        $hits = New-Object System.Collections.ArrayList
        for ($i = 0; $i -le $ln - $pat.Length; $i++) {
            $same = $true
            for ($j = 0; $j -lt $pat.Length; $j++) { if ($payload[$i + $j] -ne $pat[$j]) { $same = $false; break } }
            if ($same) { [void]$hits.Add($i) }
        }
        if ($hits.Count -ne 1) { Fail "$($e.label): expected exactly one '$($e.loader)' loader in $($e.prg), found $($hits.Count); check the loader name" }
        $endBank = 1 + [int][Math]::Floor($db.Length / 8192)
        $endAddr = 0xA000 + ($db.Length % 8192)
        if ($endBank -gt 250) { Fail "$($e.data) is too large" }
        $patch = New-Object System.Collections.Generic.List[byte]
        foreach ($b in @(0xA9, $endBank, 0x85, 0x00, 0xA2, ($endAddr -band 255), 0xA0, ($endAddr -shr 8))) { [void]$patch.Add([byte]$b) }
        S-Add $patch $tailp
        for ($j = 0; $j -lt $patch.Count; $j++) { $payload[$hits[0] + $j] = $patch[$j] }
        $e.dataBytes = $db
    }
    $e.payload = $payload
    if ($null -eq $e.dataBytes) { $e.njobs = 1 } else { $e.njobs = 1 + [int][Math]::Ceiling($e.dataBytes.Length / $CHUNK) }
    if ($e.njobs -gt 15) { Fail "$($e.label) needs $($e.njobs) copy jobs (max 15)" }
}

# ---------------- layout ----------------
$jlTotal = 0
foreach ($e in $entries) { $jlTotal += 8 * ($e.njobs + 1) }
$dataLen = $STAGE_HDR + $sinit.Count + $sconf.Count + $sunconf.Count + $names.Count + 4 * $count + $jlTotal + 8
if ($dataLen -gt 0x1D00) { Fail "menu data too large ($dataLen bytes)" }
$payloadBase = (0x500 + $dataLen + 15) -band (-bnot 15)

$STAGE = 0x8000
$off = $STAGE_HDR
$aSinit = $STAGE + $off; $off += $sinit.Count
$aSconf = $STAGE + $off; $off += $sconf.Count
$aSunconf = $STAGE + $off; $off += $sunconf.Count
$aNames = $STAGE + $off; $off += $names.Count
$aEntries = $STAGE + $off; $off += 4 * $count
$aJobs = $STAGE + $off

$romOff = $payloadBase
$entriesBytes = New-Object System.Collections.Generic.List[byte]
$jobsBytes = New-Object System.Collections.Generic.List[byte]
$jlAddr = $aJobs
foreach ($e in $entries) {
    $jl = New-Object System.Collections.ArrayList
    [void]$jl.Add(@($romOff, $e.load, $e.payload.Length, 0))
    $e.romOff = $romOff
    $romOff += $e.payload.Length
    if ($null -ne $e.dataBytes) {
        $e.dataOff = $romOff
        $dl = $e.dataBytes.Length; $pos = 0; $rb = 1
        while ($pos -lt $dl) {
            $k = [Math]::Min($CHUNK, $dl - $pos)
            [void]$jl.Add(@(($romOff + $pos), 0xA000, $k, $rb))
            $pos += $k; $rb += 7
        }
        $romOff += $dl
    }
    $jb = New-Object System.Collections.Generic.List[byte]
    foreach ($j in $jl) {
        $o = $j[0]; $dst = $j[1]; $n = $j[2]; $rbk = $j[3]
        $a = 0xC000 + ($o -band 0x3FFF)
        foreach ($b in @(($a -band 255), ($a -shr 8), ($dst -band 255), ($dst -shr 8), ($n -band 255), ($n -shr 8), (32 + ($o -shr 14)), $rbk)) { [void]$jb.Add([byte]$b) }
    }
    for ($i = 0; $i -lt 8; $i++) { [void]$jb.Add([byte]0) }
    foreach ($b in @(($jlAddr -band 255), ($jlAddr -shr 8), ($e.entry -band 255), ($e.entry -shr 8))) { [void]$entriesBytes.Add([byte]$b) }
    $jobsBytes.AddRange($jb)
    $jlAddr += $jb.Count
}
$total = $romOff
if ($total -gt 224 * 16384) { Fail "the programs do not fit in the 3.5 MB cartridge space" }

$sizeS = (CfgGet 'cartridge.size' 'auto').ToLower()
if ($sizeS -eq 'auto') {
    $size = 16384
    while ($size -lt $total) { $size *= 2 }
} else {
    $sm = [regex]::Match($sizeS, '^(\d+)\s*(k|kb)?$')
    if (-not $sm.Success) { Fail "cartridge.size must be auto or a size like 512K" }
    $size = [int]$sm.Groups[1].Value
    if ($sm.Groups[2].Value -ne '') { $size *= 1024 }
    if ($size -lt $total) { Fail "the content needs $total bytes but cartridge.size is $size bytes" }
}

# ---------------- menu header ----------------
$hdr = New-Object 'byte[]' $STAGE_HDR
$hdr[0] = $count; $hdr[1] = $rowsEff; $hdr[2] = $mw; $hdr[3] = $mx; $hdr[4] = $my
$hdr[5] = $ColCode[$ntext]; $hdr[6] = $ColCode[$nbg]; $hdr[7] = $ColCode[$stext]; $hdr[8] = $ColCode[$sbg]
if ($charset -eq 'upper') { $hdr[9] = 0x8E } else { $hdr[9] = 0x0E }
$hdr[10] = $modeByte; $hdr[11] = $border
if ($allowExit) { $hdr[12] = 1 } else { $hdr[12] = 0 }
$hdr[13] = $aSinit -band 255;   $hdr[14] = $aSinit -shr 8
$hdr[15] = $aSconf -band 255;   $hdr[16] = $aSconf -shr 8
$hdr[17] = $aSunconf -band 255; $hdr[18] = $aSunconf -shr 8
$hdr[19] = $aNames -band 255;   $hdr[20] = $aNames -shr 8
$hdr[21] = $aEntries -band 255; $hdr[22] = $aEntries -shr 8

$data = New-Object System.Collections.Generic.List[byte]
$data.AddRange($hdr)
$data.AddRange($sinit); $data.AddRange($sconf); $data.AddRange($sunconf); $data.AddRange($names)
$data.AddRange($entriesBytes); $data.AddRange($jobsBytes)
for ($i = 0; $i -lt 8; $i++) { [void]$data.Add([byte]0) }
if ($data.Count -ne $dataLen) { Fail "internal error: data size mismatch ($($data.Count) / $dataLen)" }

# ---------------- building the image ----------------
$rom = New-Object 'byte[]' $size
for ($i = 0; $i -lt $size; $i++) { $rom[$i] = 0xFF }
$stub = HexToBytes $STUB_HEX
[Array]::Copy($stub, 0, $rom, 0, $stub.Length)
$menu = HexToBytes $MENU_HEX
[Array]::Copy($menu, 0, $rom, 0x100, $menu.Length)
$rom[0x103] = $dataLen -band 255
$rom[0x104] = $dataLen -shr 8
[Array]::Copy($data.ToArray(), 0, $rom, 0x500, $dataLen)
foreach ($e in $entries) {
    [Array]::Copy($e.payload, 0, $rom, $e.romOff, $e.payload.Length)
    if ($null -ne $e.dataBytes) { [Array]::Copy($e.dataBytes, 0, $rom, $e.dataOff, $e.dataBytes.Length) }
}

$outPath = Join-Path $BaseDir $outName
[IO.File]::WriteAllBytes($outPath, $rom)
Write-Host ""
Write-Host "Cartridge created: $outPath"
Write-Host ("  {0} program(s), content {1} bytes, chip {2} KB" -f $count, $total, ($size / 1024))
foreach ($e in $entries) { Write-Host ("  - {0,-30} {1}" -f $e.label, $e.prg) }
