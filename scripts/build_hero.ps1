# Generates the hero image: a contribution wall where a snake writes PINEAPPLE.
# All text lives in hero.config.json so this file stays ASCII (PowerShell 5.1 reads BOM-less .ps1 as ANSI).
param(
  [ValidateSet('dark', 'light')][string]$Theme = 'dark',
  [string]$Config = (Join-Path $PSScriptRoot '../hero.config.json'),
  [string]$Out = (Join-Path $PSScriptRoot '../dist/hero.svg')
)
$ErrorActionPreference = 'Stop'
[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture
. (Join-Path $PSScriptRoot 'common.ps1')
$TH = Get-Theme $Theme
$cfg = Read-Config $Config

# Layout. 53 columns x 7 rows is the real calendar; PINEAPPLE in a 5x7 font is 51 columns wide.
$CARD_W = 1000; $CARD_H = 382
$PITCH = 18; $CELL = 14; $X0 = 25; $Y0 = 66
$COLS = 53; $ROWS = 7

# Timeline (seconds). Pass 1 writes the name, pass 2 eats it.
$LOOP = 18.0; $PASS = 5.0; $EAT_AT = 12.0
$PHRASE_STARTS = 0.3, 6.3, 12.3
$PHRASE_LEN = 5.7
$TYPE_DT = 0.085

$FONT = @{
  'P' = '11110', '10001', '10001', '11110', '10000', '10000', '10000'
  'I' = '111', '010', '010', '010', '010', '010', '111'
  'N' = '10001', '11001', '10101', '10011', '10001', '10001', '10001'
  'E' = '11111', '10000', '10000', '11110', '10000', '10000', '11111'
  'A' = '01110', '10001', '10001', '11111', '10001', '10001', '10001'
  'L' = '10000', '10000', '10000', '10000', '10000', '10000', '11111'
}

function N([double]$v) { return ('{0:0.###}' -f $v) }
function Esc([string]$s) { return $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;') }

# Letter cells
$lit = New-Object System.Collections.ArrayList
$occupied = @{}
$col = 1
foreach ($ch in 'PINEAPPLE'.ToCharArray()) {
  $glyph = $FONT[[string]$ch]
  for ($r = 0; $r -lt 7; $r++) {
    for ($i = 0; $i -lt $glyph[$r].Length; $i++) {
      if ($glyph[$r][$i] -eq '1') {
        [void]$lit.Add(@(($col + $i), $r))
        $occupied["$($col + $i),$r"] = $true
      }
    }
  }
  $col += $glyph[0].Length + 1
}

# Snake path across the wall: right along a row, with Manhattan turns.
$turns = @{ 6 = 1; 14 = 5; 22 = 2; 30 = 6; 38 = 0; 46 = 4; 54 = 3 }
$path = New-Object System.Collections.ArrayList
$row = 3
for ($c = -8; $c -le 61; $c++) {
  [void]$path.Add(@($c, $row))
  if ($turns.ContainsKey($c)) {
    $to = $turns[$c]
    while ($row -ne $to) {
      $row += [Math]::Sign($to - $row)
      [void]$path.Add(@($c, $row))
    }
  }
}
$dt = $PASS / $path.Count
$arrive = @{}
for ($i = 0; $i -lt $path.Count; $i++) {
  $c = $path[$i][0]
  if (-not $arrive.ContainsKey($c)) { $arrive[$c] = $i * $dt }
}

$sb = New-Object System.Text.StringBuilder
function A([string]$s) { [void]$sb.Append($s) }

$helloAll = ($cfg.intro | ForEach-Object { $_.hello }) -join ' / '
A ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' + $CARD_W + ' ' + $CARD_H + '" width="' + $CARD_W + '" height="' + $CARD_H + '" role="img" aria-labelledby="t d">')
A '<title id="t">Pineapple</title>'
A ('<desc id="d">' + (Esc $helloAll) + '</desc>')

# Styles
A '<style>'
A ('text{font-family:' + $TH.Mono + '}.sans{font-family:' + $TH.Sans + '}')
A ('.ttl{font-size:15px;font-weight:600;fill:' + $TH.Title + '}.m{font-size:12px;fill:' + $TH.Muted + '}')
A ('.lead{font-size:32px;font-weight:700;fill:' + $TH.Lead + '}.gt{font-size:32px;font-weight:700}')
A ('.tag{font-size:19px;fill:' + $TH.Tag + '}.chip{font-size:14px;fill:' + $TH.ChipText + '}')
A ('.l{transform-box:fill-box;transform-origin:center;animation:lit ' + (N $LOOP) + 's linear infinite both}')
$eatPct = $EAT_AT / $LOOP * 100
A ('@keyframes lit{0%{opacity:0;transform:scale(.4)}1%{opacity:1;transform:scale(1.4)}3%{opacity:1;transform:scale(1)}' + (N $eatPct) + '%{opacity:1;transform:scale(1)}' + (N ($eatPct + 0.4)) + '%{opacity:0;transform:scale(.4)}100%{opacity:0;transform:scale(.4)}}')
A ('.s{animation:snake ' + (N $LOOP) + 's steps(1,end) infinite both}')

# Snake keyframes: same path twice, 12 seconds apart, so the second pass eats what the first wrote.
A '@keyframes snake{'
foreach ($start in 0.0, $EAT_AT) {
  for ($i = 0; $i -lt $path.Count; $i++) {
    $pct = ($start + $i * $dt) / $LOOP * 100
    $px = $X0 + $path[$i][0] * $PITCH
    $py = $Y0 + $path[$i][1] * $PITCH
    A ((N $pct) + '%{transform:translate(' + $px + 'px,' + $py + 'px)}')
  }
}
$last = $path[$path.Count - 1]
A ('100%{transform:translate(' + ($X0 + $last[0] * $PITCH) + 'px,' + ($Y0 + $last[1] * $PITCH) + 'px)}}')

# Typing
$visPct = $PHRASE_LEN / $LOOP * 100
A ('.c{animation:ch ' + (N $LOOP) + 's linear infinite both}@keyframes ch{0%{opacity:0}.01%{opacity:1}' + (N $visPct) + '%{opacity:1}' + (N ($visPct + 0.01)) + '%{opacity:0}100%{opacity:0}}')
A '.ph2,.ph3{opacity:0}'
for ($p = 0; $p -lt 3; $p++) {
  $a = $PHRASE_STARTS[$p] / $LOOP * 100
  $b = ($PHRASE_STARTS[$p] + $PHRASE_LEN) / $LOOP * 100
  $name = 'ph' + ($p + 1)
  A ('.' + $name + '{animation:' + $name + ' ' + (N $LOOP) + 's steps(1,end) infinite}')
  A ('@keyframes ' + $name + '{0%{opacity:0}' + (N $a) + '%{opacity:1}' + (N $b) + '%{opacity:0}100%{opacity:0}}')
}
A '.blink{animation:blink 1s steps(2,jump-none) infinite}@keyframes blink{0%{opacity:1}100%{opacity:.25}}'
A '.bob{animation:bob 1.6s steps(2,jump-none) infinite alternate}@keyframes bob{0%{transform:translateY(0)}100%{transform:translateY(-7px)}}'
A '@media (prefers-reduced-motion:reduce){*{animation:none!important}.ph1,.c,.l{opacity:1}.cur,.snake{display:none}}'
A '</style>'

# Defs
A '<defs>'
A ('<pattern id="p" x="' + $X0 + '" y="' + $Y0 + '" width="' + $PITCH + '" height="' + $PITCH + '" patternUnits="userSpaceOnUse"><rect width="' + $CELL + '" height="' + $CELL + '" rx="3" fill="' + $TH.Empty + '"/></pattern>')
A ('<radialGradient id="ga" cx=".12" cy=".05" r=".8"><stop offset="0" stop-color="#ffd23f" stop-opacity="' + $TH.GlowGold + '"/><stop offset="1" stop-color="#ffd23f" stop-opacity="0"/></radialGradient>')
A ('<radialGradient id="gb" cx=".95" cy="1" r=".7"><stop offset="0" stop-color="#3fb950" stop-opacity="' + $TH.GlowGreen + '"/><stop offset="1" stop-color="#3fb950" stop-opacity="0"/></radialGradient>')
A ('<filter id="glow" filterUnits="userSpaceOnUse" x="0" y="40" width="' + $CARD_W + '" height="170"><feGaussianBlur in="SourceGraphic" stdDeviation="6" result="b"/><feComponentTransfer in="b" result="g"><feFuncA type="linear" slope="' + $TH.GlowSlope + '"/></feComponentTransfer><feMerge><feMergeNode in="g"/><feMergeNode in="SourceGraphic"/></feMerge></filter>')
A ('<clipPath id="wall"><rect x="' + ($X0 - 2) + '" y="' + ($Y0 - 2) + '" width="' + ($COLS * $PITCH) + '" height="' + ($ROWS * $PITCH) + '"/></clipPath>')
A '</defs>'

# Card
A ('<rect x=".5" y=".5" width="' + ($CARD_W - 1) + '" height="' + ($CARD_H - 1) + '" rx="14" fill="' + $TH.Card + '" stroke="' + $TH.Stroke + '"/>')
A ('<rect x="1" y="1" width="' + ($CARD_W - 2) + '" height="' + ($CARD_H - 2) + '" rx="14" fill="url(#ga)"/>')
A ('<rect x="1" y="1" width="' + ($CARD_W - 2) + '" height="' + ($CARD_H - 2) + '" rx="14" fill="url(#gb)"/>')

# Header + month labels
A ('<text class="ttl" x="' + $X0 + '" y="34">' + (Esc $cfg.title) + '</text>')
$months = 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
for ($m = 0; $m -lt 12; $m++) {
  $mx = $X0 + [Math]::Round($m * $COLS / 12) * $PITCH
  A ('<text class="m" x="' + $mx + '" y="56">' + $months[$m] + '</text>')
}

# Wall background, with a light scatter of low-level green so it reads as a real calendar.
A ('<rect x="' + $X0 + '" y="' + $Y0 + '" width="' + ($COLS * $PITCH - 4) + '" height="' + ($ROWS * $PITCH - 4) + '" fill="url(#p)"/>')
for ($c = 0; $c -lt $COLS; $c++) {
  for ($r = 0; $r -lt $ROWS; $r++) {
    if ($occupied.ContainsKey("$c,$r")) { continue }
    $h = ($c * 31 + $r * 17 + $c * $r * 7) % 13
    if ($h -eq 0 -or $h -eq 5) {
      $fill = if ($h -eq 0) { $TH.Scatter1 } else { $TH.Scatter2 }
      A ('<rect x="' + ($X0 + $c * $PITCH) + '" y="' + ($Y0 + $r * $PITCH) + '" width="' + $CELL + '" height="' + $CELL + '" rx="3" fill="' + $fill + '"/>')
    }
  }
}

# Letters. Glow is part of the same filter, so it can never drift from the cells.
A '<g filter="url(#glow)">'
foreach ($pt in $lit) {
  $c = $pt[0]; $r = $pt[1]
  $fill = $TH.Levels[($c * 7 + $r * 13) % 4]
  A ('<rect class="l" x="' + ($X0 + $c * $PITCH) + '" y="' + ($Y0 + $r * $PITCH) + '" width="' + $CELL + '" height="' + $CELL + '" rx="3" fill="' + $fill + '" style="animation-delay:' + (N $arrive[$c]) + 's"/>')
}
A '</g>'

# Snake
A '<g class="snake" clip-path="url(#wall)">'
$seg = $TH.Snake
for ($k = $seg.Count - 1; $k -ge 0; $k--) {
  A ('<rect class="s" width="' + $CELL + '" height="' + $CELL + '" rx="3" fill="' + $seg[$k] + '" style="animation-delay:' + (N ($k * $dt)) + 's"/>')
}
A '</g>'

# Legend row
A ('<text class="m" x="' + $X0 + '" y="214">' + (Esc $cfg.footnote) + '</text>')
A '<text class="m" x="975" y="214" text-anchor="end">Sweet</text>'
$legend = @($TH.Empty) + $TH.Levels
for ($i = 0; $i -lt 5; $i++) {
  A ('<rect x="' + (870 + $i * 14) + '" y="204" width="11" height="11" rx="2" fill="' + $legend[$i] + '"/>')
}
A '<text class="m" x="862" y="214" text-anchor="end">Sour</text>'

# Greeting and tagline rotate together, one language at a time.
# Every glyph gets an explicit x, so CJK/Latin mixing and font fallback cannot shift the cursor.
$fs = 32.0; $tx = 58; $ty = 272
A ('<text class="gt" x="' + $X0 + '" y="' + $ty + '" fill="' + $TH.Gold + '">&gt;</text>')
for ($p = 0; $p -lt 3; $p++) {
  $phrase = [string]$cfg.intro[$p].hello
  $x = [double]$tx
  $start = $PHRASE_STARTS[$p]
  A ('<g class="ph' + ($p + 1) + '">')
  $kf = New-Object System.Text.StringBuilder
  $i = 0
  foreach ($ch in $phrase.ToCharArray()) {
    $wide = [int][char]$ch -gt 0x2E7F
    $delay = $start + $i * $TYPE_DT
    [void]$kf.Append((N (($delay) / $LOOP * 100)) + '%{transform:translateX(' + (N $x) + 'px)}')
    if ($ch -ne ' ') {
      A ('<text class="lead c" x="' + (N $x) + '" y="' + $ty + '" style="animation-delay:' + (N $delay) + 's">' + (Esc ([string]$ch)) + '</text>')
    }
    $x += if ($wide) { $fs } else { $fs * 0.6 }
    $i++
  }
  $endT = $start + $i * $TYPE_DT
  [void]$kf.Append((N ($endT / $LOOP * 100)) + '%{transform:translateX(' + (N ($x + 4)) + 'px)}')
  $name = 'cur' + ($p + 1)
  A ('<style>.' + $name + '{animation:' + $name + ' ' + (N $LOOP) + 's steps(1,end) infinite both}@keyframes ' + $name + '{0%{transform:translateX(' + $tx + 'px)}' + $kf.ToString() + '}</style>')
  A ('<g class="cur blink"><rect class="' + $name + '" y="' + ($ty - 27) + '" width="15" height="33" fill="' + $TH.Gold + '"/></g>')
  A ('<text class="tag sans" x="' + $X0 + '" y="312">' + (Esc ([string]$cfg.intro[$p].tagline)) + '</text>')
  A '</g>'
}

# Chips
$cx = $X0
foreach ($chip in $cfg.chips) {
  $w = [Math]::Round($chip.Length * 8.4 + 24)
  A ('<rect x="' + $cx + '" y="328" width="' + $w + '" height="28" rx="14" fill="' + $TH.ChipFill + '" stroke="' + $TH.Stroke + '"/>')
  A ('<text class="chip" x="' + ($cx + $w / 2) + '" y="347" text-anchor="middle">' + (Esc $chip) + '</text>')
  $cx += $w + 10
}

# Pixel pineapple. G/L crown, Y/D body.
$art = @(
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
A '<g class="bob">'
for ($r = 0; $r -lt $art.Count; $r++) {
  for ($c = 0; $c -lt $art[$r].Length; $c++) {
    $k = [string]$art[$r][$c]
    if ($k -eq '.') { continue }
    A ('<rect x="' + (898 + $c * 7) + '" y="' + (250 + $r * 7) + '" width="6" height="6" rx="1" fill="' + $TH.Art[$k] + '"/>')
  }
}
A '</g>'

A '</svg>'

Save-Svg $Out $sb.ToString()
