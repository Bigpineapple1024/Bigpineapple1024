# Generates the research-focus card: a pixel image is cut into patches, every patch becomes a visual
# token, most tokens are pruned, and the few that matter flow into the language model, which answers.
# It is the textbook picture of visual token pruning, not any particular method.
# Text lives in hero.config.json ("focus") so this file stays ASCII (PowerShell 5.1 reads BOM-less .ps1 as ANSI).
param(
  [ValidateSet('dark', 'light')][string]$Theme = 'dark',
  [string]$Config = (Join-Path $PSScriptRoot '../hero.config.json'),
  [string]$Out = (Join-Path $PSScriptRoot '../dist/focus.svg')
)
$ErrorActionPreference = 'Stop'
[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture
. (Join-Path $PSScriptRoot 'common.ps1')
$TH = Get-Theme $Theme
$cfg = Read-Config $Config
$focus = $cfg.focus

# Layout
$CARD_W = 1000; $CARD_H = 300
$IX = 48; $IY = 72; $PIX = 10; $SIDE = 16; $GRID = 8          # image: 16x16 pixels, 8x8 patches
$TX = 272; $TY = 90; $TP = 16; $TS = 12                         # token grid
$BX = 468; $BY = 76; $BW = 236; $BH = 156                       # language model block
$KX = 488; $KY = 120; $KEEP = 16                                # where kept tokens land
$OX = 744; $OY = 162                                            # answer
$MID = 154                                                      # height of the flow lines

# Timeline in seconds; everything repeats every $LOOP seconds.
$LOOP = 12.0
$T_SCAN0 = 0.6; $T_SCAN1 = 2.0
$T_PRUNE0 = 2.6; $T_PRUNE1 = 3.0; $T_RING = 3.0
$T_MOVE0 = 3.8; $MOVE_DUR = 0.55; $MOVE_STAG = 0.04
$T_LAYER0 = 5.0; $LAYER_STEP = 0.22
$T_OUT0 = 6.7; $OUT_DT = 0.06
$T_FADE0 = 11.3; $T_FADE1 = 11.6

function N([double]$v) { return ('{0:0.###}' -f $v) }
function Esc([string]$s) { return $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;') }
function Pc([double]$sec) { return (N ($sec / $LOOP * 100)) }

# ---- Scene: the hero's pixel pineapple on a patch of sky and ground.
$ART = @(
  '.....G.....',
  '..G..L..G..',
  '...G.L.G...',
  '....GLG....',
  '...GGLGG...',
  '...YYYYY...',
  '..YDYYYDY..',
  '.YYYDYDYYY.',
  '.YDYYDYYDY.',
  '.YYDYYYDYY.',
  '.YYYDYDYYY.',
  '.YDYYDYYDY.',
  '..YDYYYDY..',
  '...YYYYY...'
)
$scene = @()
for ($r = 0; $r -lt $SIDE; $r++) { $scene += , ('.' * $SIDE).ToCharArray() }
for ($r = 0; $r -lt $ART.Count; $r++) {
  for ($c = 0; $c -lt $ART[$r].Length; $c++) {
    if ($ART[$r][$c] -ne '.') { $scene[$r + 1][$c + 2] = $ART[$r][$c] }
  }
}
foreach ($cl in @(@(0, 2), @(1, 2), @(1, 3), @(13, 1), @(14, 1), @(14, 2), @(15, 2))) {
  if ($scene[$cl[1]][$cl[0]] -eq '.') { $scene[$cl[1]][$cl[0]] = 'c' }
}
for ($c = 0; $c -lt $SIDE; $c++) { if ($scene[$SIDE - 1][$c] -eq '.') { $scene[$SIDE - 1][$c] = 'g' } }

$SCENE_COL = @{
  dark  = @{ '.' = '#172235'; 'c' = '#2a3a57'; 'g' = '#1b3a28' }
  light = @{ '.' = '#dcebfb'; 'c' = '#ffffff'; 'g' = '#b7e3c2' }
}
function Is-Fruit([char]$ch) { return ('GLYD'.IndexOf($ch) -ge 0) }   # String.IndexOf is case-sensitive
function Color-Of([char]$ch) {
  if (Is-Fruit $ch) { return $TH.Art[[string]$ch] }
  return $SCENE_COL[$Theme][[string]$ch]
}

# ---- Patches: score = pineapple pixels in the 2x2 patch; the densest $KEEP survive pruning.
$patches = for ($pr = 0; $pr -lt $GRID; $pr++) {
  for ($pq = 0; $pq -lt $GRID; $pq++) {
    $chars = @($scene[2 * $pr][2 * $pq], $scene[2 * $pr][2 * $pq + 1], $scene[2 * $pr + 1][2 * $pq], $scene[2 * $pr + 1][2 * $pq + 1])
    $fruit = @($chars | Where-Object { Is-Fruit $_ })
    $pool = $chars
    if ($fruit.Count -gt 0) { $pool = $fruit }
    $dominant = ($pool | Group-Object -CaseSensitive | Sort-Object Count -Descending | Select-Object -First 1).Name
    [pscustomobject]@{
      C = $pq; R = $pr; Score = $fruit.Count
      Dist = [Math]::Abs($pq - 3.5) + [Math]::Abs($pr - 4.0)
      Color = (Color-Of ([char]$dominant))
    }
  }
}
$keptList = @($patches | Sort-Object @{ Expression = { -$_.Score } }, @{ Expression = { $_.Dist } } | Select-Object -First $KEEP | Sort-Object R, C)
$keptSlot = @{}
for ($j = 0; $j -lt $keptList.Count; $j++) { $keptSlot["$($keptList[$j].C),$($keptList[$j].R)"] = $j }

$sb = New-Object System.Text.StringBuilder
function A([string]$s) { [void]$sb.Append($s) }

$captions = @($focus.captions)
A ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' + $CARD_W + ' ' + $CARD_H + '" width="' + $CARD_W + '" height="' + $CARD_H + '" role="img" aria-labelledby="t d">')
A ('<title id="t">' + (Esc ([string]$focus.title)) + '</title>')
A ('<desc id="d">' + (Esc ($captions -join ' / ')) + '</desc>')

# ---- Styles and keyframes
A '<style>'
A ('text{font-family:' + $TH.Mono + '}.sans{font-family:' + $TH.Sans + '}')
A ('.ttl{font-size:15px;font-weight:600;fill:' + $TH.Title + '}.m{font-size:12px;fill:' + $TH.Muted + '}')
A ('.cnt{font-size:13px;fill:' + $TH.Muted + '}.fin{fill:' + $TH.Gold + ';font-weight:700}')
A ('.lbl{font-size:13px;fill:' + $TH.Muted + '}.out{font-size:20px;font-weight:700;fill:' + $TH.Gold + '}.cap{font-size:16px;fill:' + $TH.Tag + '}')
A ('.a{animation-duration:' + (N $LOOP) + 's;animation-iteration-count:infinite;animation-fill-mode:both;animation-timing-function:linear}')
A '.st{animation-timing-function:steps(1,end)}.ez{animation-timing-function:ease-in-out}'
# Moving dashes never stop, which also keeps the image's animation clock ticking every frame.
A '.flow{stroke-dasharray:4 6;animation:flow .7s linear infinite}@keyframes flow{to{stroke-dashoffset:-10}}'

A ('@keyframes grid{0%{opacity:0}' + (Pc 0.3) + '%{opacity:.5}' + (Pc $T_FADE0) + '%{opacity:.5}' + (Pc $T_FADE1) + '%,100%{opacity:0}}')
A ('@keyframes scan{0%,' + (Pc $T_SCAN0) + '%{opacity:0;transform:translateY(0)}' + (Pc ($T_SCAN0 + 0.02)) + '%{opacity:1}' + (Pc $T_SCAN1) + '%{opacity:1;transform:translateY(' + ($SIDE * $PIX) + 'px)}' + (Pc ($T_SCAN1 + 0.12)) + '%,100%{opacity:0;transform:translateY(' + ($SIDE * $PIX) + 'px)}}')
for ($r = 0; $r -lt $GRID; $r++) {
  # A row of tokens appears as the scan line finishes the matching row of patches.
  $at = $T_SCAN0 + ($r + 1) / $GRID * ($T_SCAN1 - $T_SCAN0)
  A ('@keyframes rk' + $r + '{0%,' + (Pc $at) + '%{opacity:0}' + (Pc ($at + 0.12)) + '%{opacity:1}' + (Pc $T_FADE0) + '%{opacity:1}' + (Pc $T_FADE1) + '%,100%{opacity:0}}')
  A ('@keyframes rp' + $r + '{0%,' + (Pc $at) + '%{opacity:0}' + (Pc ($at + 0.12)) + '%{opacity:1}' + (Pc $T_PRUNE0) + '%{opacity:1}' + (Pc $T_PRUNE1) + '%{opacity:.12}' + (Pc $T_FADE0) + '%{opacity:.12}' + (Pc $T_FADE1) + '%,100%{opacity:0}}')
}
A ('@keyframes ring{0%,' + (Pc $T_RING) + '%{opacity:0}' + (Pc ($T_RING + 0.15)) + '%{opacity:1}' + (Pc $T_MOVE0) + '%{opacity:1}' + (Pc ($T_MOVE0 + 0.2)) + '%,100%{opacity:0}}')
for ($j = 0; $j -lt $keptList.Count; $j++) {
  $kp = $keptList[$j]
  $dx = ($KX + ($j % 4) * $TP) - ($TX + $kp.C * $TP)
  $dy = ($KY + [Math]::Floor($j / 4) * $TP) - ($TY + $kp.R * $TP)
  $s0 = $T_MOVE0 + $j * $MOVE_STAG; $s1 = $s0 + $MOVE_DUR
  $to = 'transform:translate(' + $dx + 'px,' + $dy + 'px)'
  A ('@keyframes m' + $j + '{0%,' + (Pc $s0) + '%{transform:translate(0,0)}' + (Pc $s1) + '%,' + (Pc $T_FADE1) + '%{' + $to + '}' + (Pc ($T_FADE1 + 0.05)) + '%,100%{transform:translate(0,0)}}')
}

# Token counter: 64 -> 16 in four steps while the pruning happens.
$total = $GRID * $GRID
$frames = @(0..4 | ForEach-Object { [int][Math]::Round($total - ($total - $KEEP) * $_ / 4) })
$frameAt = @($T_SCAN1, $T_PRUNE0, ($T_PRUNE0 + 0.2), ($T_PRUNE0 + 0.4), ($T_PRUNE0 + 0.6))
for ($k = 0; $k -lt 5; $k++) {
  if ($k -lt 4) { A ('@keyframes f' + $k + '{0%{opacity:0}' + (Pc $frameAt[$k]) + '%{opacity:1}' + (Pc $frameAt[$k + 1]) + '%,100%{opacity:0}}') }
  else { A ('@keyframes f' + $k + '{0%{opacity:0}' + (Pc $frameAt[$k]) + '%{opacity:1}' + (Pc $T_FADE0) + '%,100%{opacity:0}}') }
}
# Model layers light up one after another, the block glows while it thinks.
for ($i = 0; $i -lt 6; $i++) {
  $l0 = $T_LAYER0 + $i * $LAYER_STEP
  A ('@keyframes ly' + $i + '{0%,' + (Pc $l0) + '%{opacity:.22}' + (Pc ($l0 + 0.18)) + '%{opacity:1}' + (Pc ($l0 + 0.6)) + '%{opacity:.45}' + (Pc $T_FADE0) + '%{opacity:.45}' + (Pc $T_FADE1) + '%,100%{opacity:.22}}')
}
A ('@keyframes boxk{0%,' + (Pc ($T_MOVE0 + 0.6)) + '%{opacity:0}' + (Pc $T_LAYER0) + '%{opacity:.9}' + (Pc $T_OUT0) + '%{opacity:.9}' + (Pc ($T_OUT0 + 0.8)) + '%{opacity:.3}' + (Pc $T_FADE0) + '%{opacity:.3}' + (Pc $T_FADE1) + '%,100%{opacity:0}}')
$answer = [string]$focus.output
for ($k = 0; $k -lt $answer.Length; $k++) {
  $t = $T_OUT0 + $k * $OUT_DT
  A ('@keyframes oc' + $k + '{0%,' + (Pc $t) + '%{opacity:0}' + (Pc ($t + 0.01)) + '%{opacity:1}' + (Pc $T_FADE0) + '%{opacity:1}' + (Pc $T_FADE1) + '%,100%{opacity:0}}')
}
# Captions take turns, one language per third of the loop.
$third = 100.0 / $captions.Count
for ($k = 0; $k -lt $captions.Count; $k++) {
  $from = N ($k * $third); $until = N (($k + 1) * $third)
  if ($k -eq 0) { A ('@keyframes cap0{0%{opacity:1}' + $until + '%,100%{opacity:0}}') }
  else { A ('@keyframes cap' + $k + '{0%{opacity:0}' + $from + '%{opacity:1}' + $until + '%,100%{opacity:0}}') }
}
A '@media (prefers-reduced-motion:reduce){*{animation:none!important}.scan,.cf{opacity:0}.cf.fin,.ring{opacity:1}.tp{opacity:.12}.c1,.c2{opacity:0}}'
A '</style>'

# ---- Defs and card
A '<defs>'
A ('<radialGradient id="ga" cx=".1" cy=".05" r=".8"><stop offset="0" stop-color="#ffd23f" stop-opacity="' + $TH.GlowGold + '"/><stop offset="1" stop-color="#ffd23f" stop-opacity="0"/></radialGradient>')
A ('<radialGradient id="gb" cx=".95" cy="1" r=".7"><stop offset="0" stop-color="#3fb950" stop-opacity="' + $TH.GlowGreen + '"/><stop offset="1" stop-color="#3fb950" stop-opacity="0"/></radialGradient>')
A ('<filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur in="SourceGraphic" stdDeviation="3" result="b"/><feComponentTransfer in="b" result="g"><feFuncA type="linear" slope="' + $TH.GlowSlope + '"/></feComponentTransfer><feMerge><feMergeNode in="g"/><feMergeNode in="SourceGraphic"/></feMerge></filter>')
A ('<clipPath id="img"><rect x="' + $IX + '" y="' + $IY + '" width="' + ($SIDE * $PIX) + '" height="' + ($SIDE * $PIX) + '" rx="6"/></clipPath>')
A '</defs>'
A ('<rect x=".5" y=".5" width="' + ($CARD_W - 1) + '" height="' + ($CARD_H - 1) + '" rx="14" fill="' + $TH.Card + '" stroke="' + $TH.Stroke + '"/>')
A ('<rect x="1" y="1" width="' + ($CARD_W - 2) + '" height="' + ($CARD_H - 2) + '" rx="14" fill="url(#ga)"/>')
A ('<rect x="1" y="1" width="' + ($CARD_W - 2) + '" height="' + ($CARD_H - 2) + '" rx="14" fill="url(#gb)"/>')
A ('<text class="ttl" x="' + $IX + '" y="42">' + (Esc ([string]$focus.title)) + '</text>')
A ('<text class="m" x="' + ($CARD_W - 48) + '" y="42" text-anchor="end">' + (Esc ([string]$focus.note)) + '</text>')

# ---- Image, patch grid and scan line
A '<g clip-path="url(#img)">'
for ($r = 0; $r -lt $SIDE; $r++) {
  for ($c = 0; $c -lt $SIDE; $c++) {
    A ('<rect x="' + ($IX + $c * $PIX) + '" y="' + ($IY + $r * $PIX) + '" width="' + $PIX + '" height="' + $PIX + '" fill="' + (Color-Of $scene[$r][$c]) + '"/>')
  }
}
$imgW = $SIDE * $PIX; $patch = $imgW / $GRID
A ('<g class="a" style="animation-name:grid" stroke="' + $TH.Title + '" stroke-width="1" fill="none">')
for ($k = 1; $k -lt $GRID; $k++) {
  A ('<line x1="' + ($IX + $k * $patch) + '" y1="' + $IY + '" x2="' + ($IX + $k * $patch) + '" y2="' + ($IY + $imgW) + '"/>')
  A ('<line x1="' + $IX + '" y1="' + ($IY + $k * $patch) + '" x2="' + ($IX + $imgW) + '" y2="' + ($IY + $k * $patch) + '"/>')
}
A '</g>'
A ('<rect class="a scan" style="animation-name:scan" x="' + $IX + '" y="' + ($IY - 2) + '" width="' + $imgW + '" height="3" fill="' + $TH.Gold + '" filter="url(#glow)"/>')
A '</g>'

# ---- Flow lines between the stages
$flowCol = $TH.Muted
A ('<line class="flow" x1="' + ($IX + $imgW + 10) + '" y1="' + $MID + '" x2="' + ($TX - 12) + '" y2="' + $MID + '" stroke="' + $flowCol + '" stroke-width="2"/>')
A ('<line class="flow" x1="' + ($TX + $GRID * $TP + 6) + '" y1="' + $MID + '" x2="' + ($BX - 10) + '" y2="' + $MID + '" stroke="' + $flowCol + '" stroke-width="2"/>')
A ('<line class="flow" x1="' + ($BX + $BW + 10) + '" y1="' + $MID + '" x2="' + ($OX - 12) + '" y2="' + $MID + '" stroke="' + $flowCol + '" stroke-width="2"/>')

# ---- Language model block with its layers
A ('<rect x="' + $BX + '" y="' + $BY + '" width="' + $BW + '" height="' + $BH + '" rx="12" fill="' + $TH.ChipFill + '" stroke="' + $TH.Stroke + '"/>')
A ('<rect class="a" style="animation-name:boxk" x="' + $BX + '" y="' + $BY + '" width="' + $BW + '" height="' + $BH + '" rx="12" fill="none" stroke="' + $TH.Gold + '" stroke-width="1.5" filter="url(#glow)"/>')
A ('<text class="lbl" x="' + ($BX + 16) + '" y="' + ($BY + 24) + '">LLM</text>')
for ($i = 0; $i -lt 6; $i++) {
  $lc = $TH.Levels[$i % $TH.Levels.Count]
  A ('<rect class="a" style="animation-name:ly' + $i + '" x="' + ($BX + 102 + $i * 20) + '" y="' + ($BY + 26) + '" width="12" height="' + ($BH - 46) + '" rx="3" fill="' + $lc + '"/>')
}

# ---- Tokens: pruned ones fade, kept ones get a ring and fly into the model.
A ('<text class="a st cnt cf" style="animation-name:f0" x="' + $TX + '" y="' + ($TY - 14) + '">' + $frames[0] + ' tokens</text>')
for ($k = 1; $k -lt 5; $k++) {
  $cls = 'a st cnt cf'
  if ($k -eq 4) { $cls += ' fin' }
  A ('<text class="' + $cls + '" style="animation-name:f' + $k + '" x="' + $TX + '" y="' + ($TY - 14) + '">' + $frames[$k] + ' tokens</text>')
}
foreach ($pt in $patches) {
  if ($keptSlot.ContainsKey("$($pt.C),$($pt.R)")) { continue }
  A ('<rect class="a tp" style="animation-name:rp' + $pt.R + '" x="' + ($TX + $pt.C * $TP) + '" y="' + ($TY + $pt.R * $TP) + '" width="' + $TS + '" height="' + $TS + '" rx="2.5" fill="' + $pt.Color + '"/>')
}
foreach ($pt in $keptList) {
  A ('<rect class="a ring" style="animation-name:ring" x="' + ($TX + $pt.C * $TP - 2) + '" y="' + ($TY + $pt.R * $TP - 2) + '" width="' + ($TS + 4) + '" height="' + ($TS + 4) + '" rx="4" fill="none" stroke="' + $TH.Gold + '" stroke-width="1.5"/>')
}
A '<g filter="url(#glow)">'
foreach ($pt in $keptList) {
  $j = $keptSlot["$($pt.C),$($pt.R)"]
  A ('<rect class="a ez" style="animation-name:rk' + $pt.R + ',m' + $j + '" x="' + ($TX + $pt.C * $TP) + '" y="' + ($TY + $pt.R * $TP) + '" width="' + $TS + '" height="' + $TS + '" rx="2.5" fill="' + $pt.Color + '"/>')
}
A '</g>'

# ---- Answer, typed out after the model has run.
A ('<g filter="url(#glow)">')
for ($k = 0; $k -lt $answer.Length; $k++) {
  $ch = [string]$answer[$k]
  if ($ch -eq ' ') { continue }
  A ('<text class="a out" style="animation-name:oc' + $k + '" x="' + (N ($OX + $k * 12)) + '" y="' + ($OY + 7) + '">' + (Esc $ch) + '</text>')
}
A '</g>'

# ---- Captions, one language at a time.
for ($k = 0; $k -lt $captions.Count; $k++) {
  A ('<text class="a st cap sans c' + $k + '" style="animation-name:cap' + $k + '" x="' + $IX + '" y="272">' + (Esc ([string]$captions[$k])) + '</text>')
}

A '</svg>'
Save-Svg $Out $sb.ToString()
"kept $($keptList.Count) of $($patches.Count) patches"
