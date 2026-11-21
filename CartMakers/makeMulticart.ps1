# makeMulticart.ps1
# Builds a Commander X16 cartridge image (menu + programs) from a settings file.
#
# Usage:          .\makeMulticart.ps1                  (reads multicart.cfg in the current folder)
#                 .\makeMulticart.ps1 other.cfg
# The .PRG / data files are looked up in the folder of the .cfg file.
param([string]$ConfigFile = "multicart.cfg")

$ErrorActionPreference = 'Stop'

# ---------------- embedded code (menu, boot stub) ----------------
$MENU_HEX = '4C05040000A9008530A9C58531A9008532A9808533AD03048534AD04048535A9208536A9008500205906A9008501AD259F29FD8D259FAD2C9F8541AD0A80C9FFF00418205FFFAD0B80C9FFF0038D2C9FAD1880F010A200BD7D809D0001E8E0B1D0F520000158A9008539AD2480F0034CB105AD2380F01A20DEFF854220E4FFC98AF00E20DEFF38E542CD238090EE4CB105A9FF8545A9008539853CAD098020D2FFAD0D80853EAD0E80853F209D0620DB06206A05C900F0F9C911F015C991F031C90DF00AC91BF04CC903F04880E34CB105A539186901CD00809008A9008539853C80CB853938E53CCD018090C1E63C80BDA539F00CC639A539C53CB0B1853C80ADAD008038E9018539AD008038ED0180853C809AAD0C80D0034CB104AD0F80853EAD1080853F209D0620E4FFC900F0F9C959F014C9D9F010AD1180853EAD1280853F209D064CB104205405782081FF58384C47FFAD259F29FD8D259FAD299F29EF8D299FA5418D2C9F6020E4FFC900D036A9012056FFC000D02BDA49FF293C85466849FF29804A4A4A05468546A54549FF254648A5468545688908D00B8924D00A8910D009A90060A99160A91160A90D60A5390A0A186D1580853EAD16806900853FA000B13EAAC8B13E48C8B13E8543C8B13E854468853F863EA000B13E999007C8C070D0F6AD2080F011853FAD1F80853EA07FB13E9900018810F8205405AD1880F003202580782081FF78A200204106A5340535F00EA537100520000180EE20590680E9A9008501A234BD58079D4001CA10F7A5438D6601A5448D67014C40018AA8A200B990079530C8E8E008D0F598AAA537297F850060A000A5368501B1309132E630D00AE631D006A9C08531E601E632D00EE633A533C9C0D006A9A08533E600A534D002C635C634A5340535D0CE60A000B13EE63ED002E63F60209206C9FEF00520D2FF80F4209206C901F005C902F012602092068542209206A8A6421820F0FF80D720920685402092068542A54220D2FFC640D0F780C2A9008537A53C186537853BAD0480186537AAAC03801820F0FFA53BC539F010AD068020D2FFA90120D2FFAD0580800EAD088020D2FFA90120D2FFAD078020D2FFAD1380853EAD1480853FA63BF00FA53E186D0280853E9002E63FCAD0F1AD02808540A000B13E20D2FFE63ED002E63FC640D0F1E637A537CD0180D08860A900AA9D00049D00059D00069D0007E8D0F1A2209530CA10FB85008D99A8A90148A96748584C0000A9008501782081FF58384C47FF'
$STUB_HEX = '4358313678A2FF9AA200BD00C19D0004BD00C29D0005BD00C39D0006BD00C49D0007E8D0E54C0004'
$MENU_LEN = 909
$STAGE_HDR = 125
$HDR_FIELDS = 37
$CLEAN_HEX = 'AD259F29FC8D259FA9208D209FA9FA8D219FA9118D229FA2008A0A0A0A0A85428A05428D239F8E239FE8E010D0EBA206A9009D2D9FCA10FA8D209F8D219FA9108D229FA900A096A2008D239F8D239FE8D0F788D0F4600000'
$DC_HEX = 'A9008501AD2280853FAD2180853EDA209D06FAA5348540A5368501205F018534205F018535A5018536A9008532A9208533205906A5018536A900850185028504A9208503A9A08505DA20EDFEFAA5402903D005A92E20D2FFE600C640D0B960B230E630D00CE631D00848A9C08531E60168600000000000000000000000000000'
$DC_LEN = 128
$BG_HEX = 'AD1880D00160AD259F29FC8D259FA9208D209FA9FA8D219FA9118D229FAD1D80853EAD1E80853FA000B13E8D239FC8C020D0F6A9008D209F8D219FA9108D229FAD1A808530AD1B808531AD1C808501A9968534A9008535AD1980F008A92C8534A9018535A000B1308D239FC8D0F8E631D006A9C08531E601A534D002C635C634A5340535D0DEA9008501AD19808D2F9FA9068D2D9FA9018D319FA9008D2E9F8D309F8D329F8D339FAD299F09108D299F60'
$BG_LEN = 177

function HexToBytes([string]$h) {
    $r = New-Object 'byte[]' ($h.Length / 2)
    for ($i = 0; $i -lt $r.Length; $i++) { $r[$i] = [Convert]::ToByte($h.Substring($i * 2, 2), 16) }
    return ,$r
}

function Fail([string]$msg) { throw ("ERROR: " + $msg) }

$ColorNames = @{ 'transparent'=0; 'black'=0; 'white'=1; 'red'=2; 'cyan'=3; 'purple'=4; 'green'=5; 'blue'=6; 'yellow'=7; 'orange'=8; 'brown'=9;
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
$autoVal = (CfgGet 'cartridge.autoexec' 'no').ToLower()
if ('yes','true','1','on','no','false','0','off','single' -notcontains $autoVal) { Fail 'cartridge.autoexec must be yes, single or no' }
$single = ($autoVal -eq 'single')
$bgOn = (CfgBool 'background.enabled' $false) -and -not $single
$bgFile = CfgGet 'background.file' 'BACKGROUND.PNG'
$compress = CfgBool 'cartridge.compress' $false
$autoexec = ('yes','true','1','on' -contains $autoVal)
$autoJiffies = CfgInt 'cartridge.autoexec_delay' 30 1 255
$loadingText = CfgGet 'loading.text' 'Loading'
$lzsaExe = $null
$tmpDir = $null
function Init-Lzsa {
    $lzsaCfg = CfgGet 'cartridge.lzsa' 'lzsa.exe'
    $cands = @($lzsaCfg, (Join-Path $BaseDir $lzsaCfg))
    if ($PSScriptRoot) { $cands += (Join-Path $PSScriptRoot $lzsaCfg) }
    foreach ($cand in $cands) {
        if (-not $script:lzsaExe -and (Test-Path -LiteralPath $cand -PathType Leaf)) { $script:lzsaExe = (Resolve-Path -LiteralPath $cand).Path }
    }
    if (-not $script:lzsaExe) {
        $gc = Get-Command $lzsaCfg -ErrorAction SilentlyContinue
        if ($gc) { $script:lzsaExe = $gc.Source }
    }
    if (-not $script:lzsaExe) { Fail "compression needs lzsa.exe: put it next to this script or the .cfg, or set cartridge.lzsa = full path" }
    $script:tmpDir = Join-Path ([IO.Path]::GetTempPath()) ("mcart_" + [Guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $script:tmpDir)
}
if ($bgOn -and $modeName -ne '80x30' -and $modeName -ne '40x30') { Fail "background.enabled = yes needs screen.mode = 80x30 or 40x30" }
if ($modeName -eq '80x30') { $bgW = 640 } else { $bgW = 320 }
if ($bgOn) { $scrBgDefault = 0 } else { $scrBgDefault = 6 }
$scrBg = CfgColor 'screen.background' $scrBgDefault
$scrFg = CfgColor 'screen.text' 14
$bv = (CfgGet 'screen.border' 'default').ToLower()
if ($bv -eq 'default' -or $single) { $border = 255 } else { $border = CfgColor 'screen.border' 0 }

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
    'binx16' = @{ pat = (HexToBytes 'A900A200A0A020D5FF900E'); tail = (HexToBytes '189 00E'.Replace(' ','')) }
    'smbx16'  = @{ pat = (HexToBytes 'A900A200A0A020D5FF900E'); tail = (HexToBytes '189 00E'.Replace(' ','')) }  # old name of binx16 (still accepted)
    'tanookix16' = @{ pat = (HexToBytes 'A901850 0A900A200A0A04CD5FF'.Replace(' ','')); tail = (HexToBytes '1860EAEAEA') }
    'smb3x16' = @{ pat = (HexToBytes 'A901850 0A900A200A0A04CD5FF'.Replace(' ','')); tail = (HexToBytes '1860EAEAEA') }  # old name of tanookix16 (still accepted)
    'bincompress' = @{ pat = (HexToBytes 'A901850 0A900A200A0A04CD5FF'.Replace(' ','')); tail = (HexToBytes '1860EAEAEA') }  # old name (still accepted)
    # diskemu: a virtual disk inside the cartridge. DATA is a FOLDER; every file in it (except the
    # program itself and documents/scripts) becomes a file the game can LOAD by name. The KERNAL LOAD vector ($0330) is redirected
    # to a small routine that reads the files from the cartridge (RAM, banked RAM and VRAM destinations).
    'diskemu' = @{ pat = $null; tail = $null }
}
$DE_BANK_USE = 15872
$skipExt = @('.PYZ','.PY','.TXT','.MD','.CFG','.PS1','.ZIP','.DBG','.LBL','.MAP','.ASM','.INC','.BAT','.SH','.LOG','.INI','.DB','.PNG','.JPG')
$DE_STUB_HEX = '0878A601DAA20086014C00FE68850128AD2001C90160'
$DE_HOOK_HEX = '8D2101A203B5FA48CA10FAA90085FAA9C085FBA000B1FAD0034CEEFECC8F02F009B18AD1FAD00BC880F2C010F011B1FAF00D18A5FA691685FA90D8E6FB80D4A010B1FA8D2601C8B1FAAAC8B1FA48C8B1FA8D2301C8B1FA8D2401C8B1FA8D250186FA6885FBAD26018501A000AD9102C901D0122006FF85FC2006FF85FD201DFF201DFF8008A58885FCA58985FDA200AD2101C902901AE8290109108D229FA5FC8D209FA5FD8D219FAD259F29FE8D259F8E2201AD23010D24010D2501F02C2006FFAE2201D01691FCE6FCD019E6FDA6FDE0C0D011A2A086FDE60080098D239FE6FCD002E6FD201DFF80C9A9008002A9048D2001A6FCA4FD6885FA6885FB6885FC6885FD4C0C01B1FAE6FAD010E6FB48A5FBC9FED006A9C085FBE6016860AD2301D00BAD2401D003CE2501CE2401CE230160'
$entries = New-Object System.Collections.ArrayList
if ($single -and $progLines.Count -gt 1) { $progLines = [System.Collections.ArrayList]@($progLines[0]) }
foreach ($pl in $progLines) {
    $parts = @($pl.Split('|') | ForEach-Object { $_.Trim() })
    if ($parts.Count -lt 2 -or $parts[0] -eq '' -or $parts[1] -eq '') { Fail "invalid program line (format: Name | FILE.PRG): $pl" }
    $e = @{ label = $parts[0]; prg = $parts[1]; data = ''; loader = ''; comp = '' }
    if ($parts.Count -gt 2) { $e.data = $parts[2] }
    if ($parts.Count -gt 3) { $e.loader = $parts[3].ToLower() }
    if ($parts.Count -gt 4) { $e.comp = $parts[4].ToLower() }
    if ($e.comp -ne '' -and $e.comp -ne 'yes' -and $e.comp -ne 'no') { Fail "$($e.label): the 5th column must be yes or no (compression)" }
    if ($e.data -ne '' -and $e.loader -eq '') { Fail "$($e.label): a data file needs a loader (binx16, tanookix16 or diskemu)" }
    if ($e.loader -ne '' -and -not $loaders.ContainsKey($e.loader)) { Fail "$($e.label): unknown loader '$($e.loader)' (binx16, tanookix16 or diskemu)" }
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

# ---------------- loading message ----------------
$sload = New-Object System.Collections.Generic.List[byte]
[void]$sload.Add([byte]0x8E)
if ($loadingText.Length -gt 0) {
    $charsetSaved = $charset
    $charset = 'upper'
    $lt = ToPetscii $loadingText
    $charset = $charsetSaved
    if ($lt.Length -gt 70) { Fail "loading.text is too long" }
    S-Plot $sload 29 ([int][Math]::Floor((80 - $lt.Length) / 2))
    S-Add $sload ([byte[]]$lt)
}
S-End $sload

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

# ---------------- compression helper (lzsa) ----------------
function Compress-Chunk([byte[]]$bytes) {
    $cin = Join-Path $tmpDir 'chunk.bin'
    $cout = Join-Path $tmpDir 'chunk.lz'
    if (Test-Path -LiteralPath $cout) { Remove-Item -LiteralPath $cout -Force }
    [IO.File]::WriteAllBytes($cin, $bytes)
    & $lzsaExe -r -f2 $cin $cout | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $cout)) { Fail "lzsa failed on a data block ($lzsaExe)" }
    return ,([IO.File]::ReadAllBytes($cout))
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
    $e.load = $load; $e.entry = $entry; $e.dataBytes = $null; $e.stored = $null; $e.nchunks = 0
    $e.dfiles = $null
    if ($e.data -ne '' -and $e.loader -eq 'diskemu') {
        $dd = Join-Path $BaseDir $e.data
        if (-not (Test-Path -LiteralPath $dd -PathType Container)) { Fail "folder not found: $($e.data)" }
        $mainFull = (Resolve-Path -LiteralPath $p).Path
        $dl = New-Object System.Collections.ArrayList
        foreach ($fi in (Get-ChildItem -LiteralPath $dd -File | Sort-Object { $_.Name.ToUpper() })) {
            $ext = $fi.Extension.ToUpper()
            if ($skipExt -contains $ext) { continue }
            if ($fi.FullName -ieq $mainFull) { continue }
            if ($fi.Name.Length -gt 16) { Fail "$($e.label): file name too long (max 16 characters): $($fi.Name)" }
            $fb = [IO.File]::ReadAllBytes($fi.FullName)
            if ($fb.Length -lt 1) { Fail "$($fi.Name) is empty" }
            [void]$dl.Add(@($fi.Name.ToUpper(), $fb))
        }
        Write-Host ("{0}: virtual disk with {1} file(s): {2}" -f $e.label, $dl.Count, (($dl | ForEach-Object { "{0} ({1})" -f $_[0], $_[1].Length }) -join ', '))
        if ($dl.Count -eq 0) { Fail "$($e.label): no files found in $($e.data)" }
        $stubAt = $load + $payload.Length
        $dataAt = $stubAt + 24
        $ins = [byte[]]@(0xA2, 0x15, 0xBD, ($dataAt -band 255), ($dataAt -shr 8), 0x9D, 0x00, 0x01, 0xCA, 0x10, 0xF7, 0xA9, 0x00, 0x8D, 0x30, 0x03, 0xA9, 0x01, 0x8D, 0x31, 0x03, 0x4C, ($entry -band 255), ($entry -shr 8))
        $stubB = HexToBytes $DE_STUB_HEX
        $np = New-Object 'byte[]' ($payload.Length + 24 + $stubB.Length)
        [Array]::Copy($payload, 0, $np, 0, $payload.Length)
        [Array]::Copy($ins, 0, $np, $payload.Length, 24)
        [Array]::Copy($stubB, 0, $np, $payload.Length + 24, $stubB.Length)
        if (($load + $np.Length) -gt 0x9F00) { Fail "$($e.label): program too large for the diskemu loader" }
        $e.dirOfs = $payload.Length + 24 + 6
        $payload = $np
        $e.entry = $stubAt
        $e.dfiles = $dl
    } elseif ($e.data -ne '') {
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
        if ($endBank -gt 127) { Fail "$($e.data) is too large (max 1 MB of data per game)" }
        $patch = New-Object System.Collections.Generic.List[byte]
        foreach ($b in @(0xA9, $endBank, 0x85, 0x00, 0xA2, ($endAddr -band 255), 0xA0, ($endAddr -shr 8))) { [void]$patch.Add([byte]$b) }
        S-Add $patch $tailp
        for ($j = 0; $j -lt $patch.Count; $j++) { $payload[$hits[0] + $j] = $patch[$j] }
        $e.dataBytes = $db
        $e.stored = $db
        $useComp = $compress
        if ($e.comp -eq 'yes') { $useComp = $true } elseif ($e.comp -eq 'no') { $useComp = $false }
        if ($useComp) {
            if (-not $lzsaExe) { Init-Lzsa }
            Write-Host ("Compressing {0} ..." -f $e.data)
            $st = New-Object System.Collections.Generic.List[byte]
            $nch = 0
            for ($pos = 0; $pos -lt $db.Length; $pos += 8192) {
                $n = [Math]::Min(8192, $db.Length - $pos)
                $part = New-Object 'byte[]' $n
                [Array]::Copy($db, $pos, $part, 0, $n)
                $cc = Compress-Chunk $part
                if ($cc.Length -gt 8300) { Fail "compressed block too large" }
                [void]$st.Add([byte]($cc.Length -band 255)); [void]$st.Add([byte]($cc.Length -shr 8))
                $st.AddRange($cc)
                $nch++
            }
            $e.stored = $st.ToArray()
            $e.nchunks = $nch
            Write-Host ("  {0} -> {1} bytes" -f $db.Length, $e.stored.Length)
        }
    }
    $e.payload = $payload
    if ($null -eq $e.dataBytes) { $e.njobs = 1 } elseif ($e.nchunks -gt 0) { $e.njobs = 2 } else { $e.njobs = 1 + [int][Math]::Ceiling($e.dataBytes.Length / $CHUNK) }
    if ($e.njobs -gt 13) { Fail "$($e.label) needs $($e.njobs) copy jobs (max 13)" }
}

# ---------------- background image (optional) ----------------
$McImageSource = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public class McResult
{
    public byte[] Palette;
    public byte[] Pixels;
    public int Colors;
}

public static class McImage
{
    public static McResult Convert(string path, int w, int h)
    {
        Bitmap bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
        using (Image src = Image.FromFile(path))
        {
            using (Graphics g = Graphics.FromImage(bmp))
            {
                g.Clear(Color.Black);
                if (src.Width == w && src.Height == h)
                {
                    g.InterpolationMode = InterpolationMode.NearestNeighbor;
                    g.PixelOffsetMode = PixelOffsetMode.Half;
                }
                else
                {
                    g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    g.SmoothingMode = SmoothingMode.HighQuality;
                }
                g.DrawImage(src, new Rectangle(0, 0, w, h), 0, 0, src.Width, src.Height, GraphicsUnit.Pixel);
            }
        }
        BitmapData bd = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        int stride = bd.Stride;
        byte[] raw = new byte[stride * h];
        Marshal.Copy(bd.Scan0, raw, 0, raw.Length);
        bmp.UnlockBits(bd);
        bmp.Dispose();

        int n = w * h;
        int[] code = new int[n];
        int[] hist = new int[4096];
        for (int y = 0; y < h; y++)
        {
            for (int x = 0; x < w; x++)
            {
                int o = y * stride + x * 4;
                int b4 = (raw[o] * 15 + 127) / 255;
                int g4 = (raw[o + 1] * 15 + 127) / 255;
                int r4 = (raw[o + 2] * 15 + 127) / 255;
                int c = (r4 << 8) | (g4 << 4) | b4;
                code[y * w + x] = c;
                hist[c]++;
            }
        }

        List<int> distinct = new List<int>();
        for (int c = 0; c < 4096; c++) { if (hist[c] > 0) distinct.Add(c); }

        List<int> palette = new List<int>();
        if (distinct.Count <= 15)
        {
            palette.AddRange(distinct);
        }
        else
        {
            List<List<int>> boxes = new List<List<int>>();
            boxes.Add(distinct);
            while (boxes.Count < 15)
            {
                int best = -1;
                long bestPop = -1;
                for (int i = 0; i < boxes.Count; i++)
                {
                    if (boxes[i].Count < 2) continue;
                    long pop = 0;
                    foreach (int c in boxes[i]) pop += hist[c];
                    if (pop > bestPop) { bestPop = pop; best = i; }
                }
                if (best < 0) break;
                List<int> box = boxes[best];
                int rmin = 15, rmax = 0, gmin = 15, gmax = 0, bmin = 15, bmax = 0;
                foreach (int c in box)
                {
                    int r = (c >> 8) & 15, g = (c >> 4) & 15, b = c & 15;
                    if (r < rmin) rmin = r; if (r > rmax) rmax = r;
                    if (g < gmin) gmin = g; if (g > gmax) gmax = g;
                    if (b < bmin) bmin = b; if (b > bmax) bmax = b;
                }
                int shift = 8;
                int range = rmax - rmin;
                if (gmax - gmin > range) { range = gmax - gmin; shift = 4; }
                if (bmax - bmin > range) { range = bmax - bmin; shift = 0; }
                int sh = shift;
                box.Sort(delegate (int a, int b) { return ((a >> sh) & 15).CompareTo((b >> sh) & 15); });
                long total = 0;
                foreach (int c in box) total += hist[c];
                long acc = 0;
                int cut = 1;
                for (int i = 0; i < box.Count - 1; i++)
                {
                    acc += hist[box[i]];
                    cut = i + 1;
                    if (acc * 2 >= total) break;
                }
                List<int> left = box.GetRange(0, cut);
                List<int> right = box.GetRange(cut, box.Count - cut);
                boxes[best] = left;
                boxes.Add(right);
            }
            foreach (List<int> box in boxes)
            {
                long sr = 0, sg = 0, sb = 0, sn = 0;
                foreach (int c in box)
                {
                    long cn = hist[c];
                    sr += cn * ((c >> 8) & 15);
                    sg += cn * ((c >> 4) & 15);
                    sb += cn * (c & 15);
                    sn += cn;
                }
                int r = (int)((sr + sn / 2) / sn);
                int g = (int)((sg + sn / 2) / sn);
                int b = (int)((sb + sn / 2) / sn);
                palette.Add((r << 8) | (g << 4) | b);
            }
        }

        int[] lut = new int[4096];
        foreach (int c in distinct)
        {
            int bestIdx = 0;
            int bestD = int.MaxValue;
            int r = (c >> 8) & 15, g = (c >> 4) & 15, b = c & 15;
            for (int i = 0; i < palette.Count; i++)
            {
                int p = palette[i];
                int dr = r - ((p >> 8) & 15), dg = g - ((p >> 4) & 15), db = b - (p & 15);
                int d = dr * dr * 3 + dg * dg * 4 + db * db * 2;
                if (d < bestD) { bestD = d; bestIdx = i; }
            }
            lut[c] = bestIdx + 1;
        }

        McResult res = new McResult();
        res.Colors = palette.Count;
        res.Palette = new byte[32];
        for (int i = 0; i < palette.Count; i++)
        {
            int p = palette[i];
            res.Palette[(i + 1) * 2] = (byte)((((p >> 4) & 15) << 4) | (p & 15));
            res.Palette[(i + 1) * 2 + 1] = (byte)((p >> 8) & 15);
        }
        res.Pixels = new byte[n / 2];
        for (int i = 0; i < n; i += 2)
        {
            res.Pixels[i / 2] = (byte)((lut[code[i]] << 4) | lut[code[i + 1]]);
        }
        return res;
    }
}
'@
$bgPal = $null
$bgPix = $null
if ($bgOn) {
    $bgPath = Join-Path $BaseDir $bgFile
    if (-not (Test-Path -LiteralPath $bgPath)) { Fail "background image not found: $bgFile" }
    Write-Host "Converting background image..."
    Add-Type -AssemblyName System.Drawing
    if (-not ('McImage' -as [type])) {
        Add-Type -ReferencedAssemblies ([System.Drawing.Bitmap].Assembly.Location) -TypeDefinition $McImageSource -Language CSharp
    }
    try { $bgRes = [McImage]::Convert($bgPath, $bgW, 240) }
    catch { Fail "cannot read background image $bgFile ($($_.Exception.Message))" }
    $bgPal = $bgRes.Palette
    $bgPix = $bgRes.Pixels
    Write-Host ("  {0} colors used" -f $bgRes.Colors)
}

# ---------------- layout ----------------
$jlTotal = 0
foreach ($e in $entries) { $jlTotal += 8 * ($e.njobs + 1) }
$anyDc = $false
foreach ($e in $entries) { if ($e.nchunks -gt 0) { $anyDc = $true } }
if ($bgOn) { $bgExtra = $BG_LEN + 32 } else { $bgExtra = 0 }
if ($anyDc) { $dcExtra = $DC_LEN } else { $dcExtra = 0 }
$dataLen = $STAGE_HDR + $bgExtra + $dcExtra + $sinit.Count + $sconf.Count + $sunconf.Count + $sload.Count + $names.Count + 4 * $count + $jlTotal + 8
if ($dataLen -gt 0x1D00) { Fail "menu data too large ($dataLen bytes)" }
if ($bgOn) { $payloadBase = (0x500 + $dataLen + 255) -band (-bnot 255) } else { $payloadBase = (0x500 + $dataLen + 15) -band (-bnot 15) }

$STAGE = 0x8000
$off = $STAGE_HDR
$aBgPal = $STAGE + $off + $BG_LEN
$off += $bgExtra
$aDc = $STAGE + $off
$off += $dcExtra
$aSinit = $STAGE + $off; $off += $sinit.Count
$aSconf = $STAGE + $off; $off += $sconf.Count
$aSunconf = $STAGE + $off; $off += $sunconf.Count
$aSload = $STAGE + $off; $off += $sload.Count
$aNames = $STAGE + $off; $off += $names.Count
$aEntries = $STAGE + $off; $off += 4 * $count
$aJobs = $STAGE + $off

$romOff = $payloadBase
$bgOff = $romOff
if ($bgOn) { $romOff += $bgPix.Length }
$entriesBytes = New-Object System.Collections.Generic.List[byte]
$jobsBytes = New-Object System.Collections.Generic.List[byte]
$jlAddr = $aJobs
foreach ($e in $entries) {
    $jl = New-Object System.Collections.ArrayList
    $e.romOff = $romOff
    $romOff += $e.payload.Length
    if ($null -ne $e.dfiles) {
        $bs = [int][Math]::Floor(($romOff + 16383) / 16384) * 16384
        $dirLen = ($e.dfiles.Count + 1) * 22
        if ($dirLen -gt $DE_BANK_USE) { Fail "too many files for the diskemu directory" }
        $dirb = New-Object System.Collections.Generic.List[byte]
        $stream = New-Object System.Collections.Generic.List[byte]
        $v = $dirLen
        foreach ($f in $e.dfiles) {
            $nb = [Text.Encoding]::ASCII.GetBytes($f[0]); $fb = $f[1]
            $bank = 32 + ($bs -shr 14) + [int][Math]::Floor($v / $DE_BANK_USE)
            $ad = 0xC000 + ($v % $DE_BANK_USE)
            $dirb.AddRange($nb)
            for ($q = $nb.Length; $q -lt 16; $q++) { [void]$dirb.Add([byte]0) }
            foreach ($b in @($bank, ($ad -band 255), ($ad -shr 8), ($fb.Length -band 255), (($fb.Length -shr 8) -band 255), ($fb.Length -shr 16))) { [void]$dirb.Add([byte]$b) }
            $v += $fb.Length
        }
        for ($q = 0; $q -lt 22; $q++) { [void]$dirb.Add([byte]0) }
        $stream.AddRange($dirb)
        foreach ($f in $e.dfiles) { $stream.AddRange([byte[]]$f[1]) }
        $e.blobBanks = [int][Math]::Ceiling($stream.Count / $DE_BANK_USE)
        $e.blobStart = $bs
        $e.blobBytes = $stream.ToArray()
        $e.payload[$e.dirOfs] = [byte](32 + ($bs -shr 14))
        $romOff = $bs + $e.blobBanks * 16384
    }
    if ($null -ne $e.dataBytes) {
        $e.dataOff = $romOff
        if ($e.nchunks -gt 0) {
            [void]$jl.Add(@($romOff, 0xA000, $e.nchunks, 0x81))
            $romOff += $e.stored.Length
        } else {
            $dl = $e.dataBytes.Length; $pos = 0; $rb = 1
            while ($pos -lt $dl) {
                $k = [Math]::Min($CHUNK, $dl - $pos)
                [void]$jl.Add(@(($romOff + $pos), 0xA000, $k, $rb))
                $pos += $k; $rb += 7
            }
            $romOff += $dl
        }
    }
    [void]$jl.Add(@($e.romOff, $e.load, $e.payload.Length, 0))
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
$cleanBytes = HexToBytes $CLEAN_HEX
[Array]::Copy($cleanBytes, 0, $hdr, $HDR_FIELDS, $cleanBytes.Length)
$hdr[0] = $count; $hdr[1] = $rowsEff; $hdr[2] = $mw; $hdr[3] = $mx; $hdr[4] = $my
$hdr[5] = $ColCode[$ntext]; $hdr[6] = $ColCode[$nbg]; $hdr[7] = $ColCode[$stext]; $hdr[8] = $ColCode[$sbg]
if ($charset -eq 'upper') { $hdr[9] = 0x8E } else { $hdr[9] = 0x0E }
if ($single) { $modeByte = 255 }
$hdr[10] = $modeByte; $hdr[11] = $border
if ($allowExit) { $hdr[12] = 1 } else { $hdr[12] = 0 }
$hdr[13] = $aSinit -band 255;   $hdr[14] = $aSinit -shr 8
$hdr[15] = $aSconf -band 255;   $hdr[16] = $aSconf -shr 8
$hdr[17] = $aSunconf -band 255; $hdr[18] = $aSunconf -shr 8
$hdr[19] = $aNames -band 255;   $hdr[20] = $aNames -shr 8
$hdr[21] = $aEntries -band 255; $hdr[22] = $aEntries -shr 8
if ($anyDc) { $hdr[31] = $aDc -band 255; $hdr[32] = $aDc -shr 8 }
$hdr[33] = $aSload -band 255; $hdr[34] = $aSload -shr 8
if ($autoexec) { $hdr[35] = $autoJiffies } else { $hdr[35] = 0 }
if ($single) { $hdr[36] = 1 }
if ($bgOn) {
    $hdr[24] = 1
    if ($bgW -eq 640) { $hdr[25] = 1 } else { $hdr[25] = 0 }
    $ba = 0xC000 + ($bgOff -band 0x3FFF)
    $hdr[26] = $ba -band 255; $hdr[27] = $ba -shr 8
    $hdr[28] = 32 + ($bgOff -shr 14)
    $hdr[29] = $aBgPal -band 255; $hdr[30] = $aBgPal -shr 8
}

$data = New-Object System.Collections.Generic.List[byte]
$data.AddRange($hdr)
if ($bgOn) { $data.AddRange((HexToBytes $BG_HEX)); $data.AddRange($bgPal) }
if ($anyDc) { $data.AddRange((HexToBytes $DC_HEX)) }
$data.AddRange($sinit); $data.AddRange($sconf); $data.AddRange($sunconf); $data.AddRange($sload); $data.AddRange($names)
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
if ($bgOn) { [Array]::Copy($bgPix, 0, $rom, $bgOff, $bgPix.Length) }
foreach ($e in $entries) {
    [Array]::Copy($e.payload, 0, $rom, $e.romOff, $e.payload.Length)
    if ($null -ne $e.dataBytes) { [Array]::Copy($e.stored, 0, $rom, $e.dataOff, $e.stored.Length) }
    if ($null -ne $e.dfiles) {
        $hk = HexToBytes $DE_HOOK_HEX
        for ($i = 0; $i -lt $e.blobBanks; $i++) {
            $n = [Math]::Min($DE_BANK_USE, $e.blobBytes.Length - $i * $DE_BANK_USE)
            [Array]::Copy($e.blobBytes, $i * $DE_BANK_USE, $rom, $e.blobStart + $i * 16384, $n)
            [Array]::Copy($hk, 0, $rom, $e.blobStart + $i * 16384 + 0x3E00, $hk.Length)
        }
    }
}

$outPath = Join-Path $BaseDir $outName
[IO.File]::WriteAllBytes($outPath, $rom)
if ($tmpDir -and (Test-Path -LiteralPath $tmpDir)) { Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue }
Write-Host ""
Write-Host "Cartridge created: $outPath"
Write-Host ("  {0} program(s), content {1} bytes, chip {2} KB" -f $count, $total, ($size / 1024))
if ($bgOn) { Write-Host ("  background image: {0} ({1}x240, 15 colors max)" -f $bgFile, $bgW) }
foreach ($e in $entries) { Write-Host ("  - {0,-30} {1}" -f $e.label, $e.prg) }
