# Generates the intro under the hero: a terminal that types a command and prints one line per language.
# All text lives in hero.config.json ("about") so this file stays ASCII (PowerShell 5.1 reads BOM-less .ps1 as ANSI).
param(
  [ValidateSet('dark', 'light')][string]$Theme = 'dark',
  [string]$Config = (Join-Path $PSScriptRoot '../hero.config.json'),
  [string]$Out = (Join-Path $PSScriptRoot '../dist/intro.svg')
)
$ErrorActionPreference = 'Stop'
[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture
. (Join-Path $PSScriptRoot 'common.ps1')
$TH = Get-Theme $Theme
$cfg = Read-Config $Config
$about = $cfg.about

# Layout. Monospace: Latin glyphs are 0.6em wide, CJK glyphs 1em.
$CARD_W = 680; $FS = 15.0; $CHW = $FS * 0.6; $LH = 27; $BASE0 = 28; $BOTTOM = 14
$PILL_W = 26; $PILL_H = 17; $TEXT_DX = $PILL_W + 10
# Timeline in seconds. Plays once, then only the cursor keeps blinking.
$START = 0.35; $CMD_DT = 0.055; $OUT_DT = 0.022; $LINE_GAP = 0.2

$BLUE = '#58a6ff'; if ($Theme -eq 'light') { $BLUE = '#0969da' }
$GREEN = $TH.Snake[1]

function N([double]$v) { return ('{0:0.###}' -f $v) }
function Esc([string]$s) { return $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;') }
function Width([string]$s) {
  $w = 0.0
  foreach ($ch in $s.ToCharArray()) { if ([int]$ch -gt 0x2E7F) { $w += $FS } else { $w += $CHW } }
  return $w
}

$prompt = [string]$about.prompt
$command = [string]$about.command
$lines = @($about.lines)
$promptW = Width ($prompt + ' ')

# Centre the block on its widest line.
$blockW = Width ($prompt + ' ' + $command)
foreach ($ln in $lines) { $blockW = [Math]::Max($blockW, $TEXT_DX + (Width ([string]$ln.text))) }
$X0 = [Math]::Round(($CARD_W - $blockW) / 2)
$rowCount = $lines.Count + 2
$CARD_H = $BASE0 + ($rowCount - 1) * $LH + $BOTTOM

$sb = New-Object System.Text.StringBuilder
function A([string]$s) { [void]$sb.Append($s) }

# Glyphs and cursor stops are collected first, then written out.
$glyphs = New-Object System.Collections.ArrayList   # x, y, char, delay, isEm
$stops = New-Object System.Collections.ArrayList    # time, x, baseline
$pills = New-Object System.Collections.ArrayList    # y, tag, delay

# Row 0: prompt is there from the start, the command is typed.
$t = $START
$y = $BASE0
$x = $X0 + $promptW
[void]$stops.Add(@(0, $x, $y))
foreach ($ch in $command.ToCharArray()) {
  if ($ch -ne ' ') { [void]$glyphs.Add(@($x, $y, [string]$ch, $t, $false)) }
  $x += $CHW; $t += $CMD_DT
  [void]$stops.Add(@($t, $x, $y))
}
$t += $LINE_GAP

# Output rows, typed fast. Words listed in "em" are drawn in gold with a glow.
for ($i = 0; $i -lt $lines.Count; $i++) {
  $ln = $lines[$i]
  $text = [string]$ln.text
  $y = $BASE0 + ($i + 1) * $LH
  $isEm = New-Object bool[] $text.Length
  foreach ($word in @($ln.em)) {
    $word = [string]$word
    if (-not $word) { continue }
    $from = 0
    while (($at = $text.IndexOf($word, $from, [StringComparison]::Ordinal)) -ge 0) {
      for ($k = $at; $k -lt $at + $word.Length; $k++) { $isEm[$k] = $true }
      $from = $at + $word.Length
    }
  }
  [void]$pills.Add(@($y, [string]$ln.tag, $t))
  $x = $X0 + $TEXT_DX
  [void]$stops.Add(@($t, $x, $y))
  for ($k = 0; $k -lt $text.Length; $k++) {
    $ch = $text[$k]
    if ($ch -ne ' ') { [void]$glyphs.Add(@($x, $y, [string]$ch, $t, $isEm[$k])) }
    if ([int]$ch -gt 0x2E7F) { $x += $FS } else { $x += $CHW }
    $t += $OUT_DT
    [void]$stops.Add(@($t, $x, $y))
  }
  $t += $LINE_GAP
}

# Last row: a fresh prompt with the cursor waiting.
$lastY = $BASE0 + ($lines.Count + 1) * $LH
$lastPromptAt = $t
[void]$stops.Add(@($t, ($X0 + $promptW), $lastY))
$TOTAL = $t + 0.05

$all = ($lines | ForEach-Object { [string]$_.text }) -join ' / '
A ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' + $CARD_W + ' ' + $CARD_H + '" width="' + $CARD_W + '" height="' + $CARD_H + '" role="img" aria-labelledby="t d">')
A '<title id="t">About</title>'
A ('<desc id="d">' + (Esc $all) + '</desc>')

A '<style>'
A ('text{font-family:' + $TH.Mono + ';font-size:' + $FS + 'px;fill:' + $TH.Title + '}')
A ('.tag{font-size:11px;fill:' + $TH.Muted + '}.em{fill:' + $TH.Gold + ';font-weight:700}')
# One-shot animations stall partway when the SVG is shown as an <img> in Chrome, so each glyph
# runs a 10-minute infinite cycle instead: hidden until its delay, then shown for the rest of the cycle.
A '.c{animation:in 600s steps(1,end) infinite both}@keyframes in{0%{opacity:0}.001%,100%{opacity:1}}'
A ('.cur{animation:cur ' + (N $TOTAL) + 's steps(1,end) 1 both}')
A '@keyframes cur{'
foreach ($s in $stops) {
  A ((N ($s[0] / $TOTAL * 100)) + '%{transform:translate(' + (N $s[1]) + 'px,' + (N ($s[2] - $FS * 0.9)) + 'px)}')
}
# Without an explicit 100% the cursor would fall back to the top-left corner once the animation ends.
$end = $stops[$stops.Count - 1]
A ('100%{transform:translate(' + (N $end[1]) + 'px,' + (N ($end[2] - $FS * 0.9)) + 'px)}}')
A '.blink{animation:blink 1s steps(2,jump-none) infinite}@keyframes blink{0%{opacity:1}100%{opacity:.2}}'
A '@media (prefers-reduced-motion:reduce){*{animation:none!important}.cur{display:none}}'
A '</style>'
A ('<defs><filter id="glow" x="-20%" y="-60%" width="140%" height="220%"><feGaussianBlur in="SourceGraphic" stdDeviation="3" result="b"/><feComponentTransfer in="b" result="g"><feFuncA type="linear" slope="' + $TH.GlowSlope + '"/></feComponentTransfer><feMerge><feMergeNode in="g"/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs>')

# Prompts: user in green, path in blue, $ in gold. Glyph by glyph on the same grid as the typed text,
# so a narrower system monospace font cannot open a gap before the command.
function Write-Prompt([double]$Px, [double]$Py, [double]$Delay, [bool]$Animated) {
  $attr = ''
  if ($Animated) { $attr = ' class="c" style="animation-delay:' + (N $Delay) + 's"' }
  A ('<g' + $attr + '>')
  $fill = $GREEN; $px2 = $Px
  foreach ($ch in $prompt.ToCharArray()) {
    if ($ch -eq ':') { $fill = $TH.Muted }
    elseif ($ch -eq '$') { $fill = $TH.Gold }
    elseif ($fill -eq $TH.Muted) { $fill = $BLUE }
    # Inline style, because the stylesheet's text{fill} would override a fill attribute.
    if ($ch -ne ' ') { A ('<text x="' + (N $px2) + '" y="' + $Py + '" style="fill:' + $fill + '">' + (Esc ([string]$ch)) + '</text>') }
    if ([int]$ch -gt 0x2E7F) { $px2 += $FS } else { $px2 += $CHW }
  }
  A '</g>'
}
Write-Prompt $X0 $BASE0 0 $false
Write-Prompt $X0 $lastY $lastPromptAt $true

# Language pills
foreach ($p in $pills) {
  $py = $p[0] - $FS * 0.82
  A ('<g class="c" style="animation-delay:' + (N $p[2]) + 's"><rect x="' + $X0 + '" y="' + (N $py) + '" width="' + $PILL_W + '" height="' + $PILL_H + '" rx="8.5" fill="none" stroke="' + $TH.Stroke + '"/>')
  A ('<text class="tag" x="' + ($X0 + $PILL_W / 2) + '" y="' + (N ($py + 12.5)) + '" text-anchor="middle">' + (Esc $p[1]) + '</text></g>')
}

# Text, plain glyphs first, then the glowing ones in one filtered group.
foreach ($g in $glyphs) {
  if ($g[4]) { continue }
  A ('<text class="c" x="' + (N $g[0]) + '" y="' + $g[1] + '" style="animation-delay:' + (N $g[3]) + 's">' + (Esc $g[2]) + '</text>')
}
A '<g filter="url(#glow)">'
foreach ($g in $glyphs) {
  if (-not $g[4]) { continue }
  A ('<text class="c em" x="' + (N $g[0]) + '" y="' + $g[1] + '" style="animation-delay:' + (N $g[3]) + 's">' + (Esc $g[2]) + '</text>')
}
A '</g>'

# Cursor
A ('<g class="blink"><rect class="cur" width="' + (N $CHW) + '" height="' + (N ($FS * 1.15)) + '" fill="' + $TH.Gold + '"/></g>')

A '</svg>'
Save-Svg $Out $sb.ToString()
