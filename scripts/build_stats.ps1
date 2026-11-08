# Generates the stats panel: four numbers from the past year of contributions that count up when shown,
# with labels that take turns in Japanese, English and Chinese.
# Labels live in hero.config.json ("stats") so this file stays ASCII (PowerShell 5.1 reads BOM-less .ps1 as ANSI).
param(
  [string]$User = $(if ($env:GITHUB_REPOSITORY_OWNER) { $env:GITHUB_REPOSITORY_OWNER } else { 'Bigpineapple1024' }),
  [string]$Html = '',
  [string]$Config = (Join-Path $PSScriptRoot '../hero.config.json'),
  [string]$Out = (Join-Path $PSScriptRoot '../dist/stats.svg'),
  [string]$LightOut = (Join-Path $PSScriptRoot '../dist/stats-light.svg')
)
$ErrorActionPreference = 'Stop'
[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture
. (Join-Path $PSScriptRoot 'common.ps1')
$cfg = Read-Config $Config
$labels = @($cfg.stats.labels)
$weekdays = @($cfg.stats.weekdays)

# ---- Numbers
$data = Get-Contributions $User $Html
$inv = [Globalization.CultureInfo]::InvariantCulture
$total = 0; $best = 0; $active = 0
$byWeekday = @(0, 0, 0, 0, 0, 0, 0)
foreach ($key in $data.Levels.Keys) {
  $n = 0
  if ($data.Counts.ContainsKey($key)) { $n = $data.Counts[$key] }
  if ($n -gt 0 -or $data.Levels[$key] -gt 0) { $active++ }
  $total += $n
  if ($n -gt $best) { $best = $n }
  $byWeekday[[int]([datetime]::ParseExact($key, 'yyyy-MM-dd', $inv).DayOfWeek)] += $n
}
if ($data.Counts.Count -eq 0) { Write-Warning 'No per-day counts found; the totals will read 0.' }
$perActive = 0
if ($active -gt 0) { $perActive = [int][Math]::Round($total / $active) }
$peak = 0
for ($d = 1; $d -lt 7; $d++) { if ($byWeekday[$d] -gt $byWeekday[$peak]) { $peak = $d } }
$values = @($total, $best, $perActive)

# Layout
$CARD_W = 1000; $CARD_H = 132; $TILE = 244; $PAD = 34
# Count-up: frames in the first 1.4 s of a 10-minute infinite cycle. One-shot animations stall in Chrome
# when the SVG is shown as an <img>, so nothing here is one-shot.
$HOLD = 600.0; $F = 14; $C0 = 0.3; $CDT = 0.08
# Labels take turns every $TURN seconds.
$TURN = 4.0

function N([double]$v) { return ('{0:0.###}' -f $v) }
function Esc([string]$s) { return $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;') }
function Ph([double]$sec) { return (N ($sec / $HOLD * 100)) }

function Build-Stats([string]$ThemeName) {
  $th = Get-Theme $ThemeName
  $sb = New-Object System.Text.StringBuilder
  function A([string]$s) { [void]$sb.Append($s) }
  $langs = $labels[0].Count
  $cycle = $TURN * $langs

  A ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' + $CARD_W + ' ' + $CARD_H + '" width="' + $CARD_W + '" height="' + $CARD_H + '" role="img" aria-labelledby="t d">')
  A '<title id="t">Past year in numbers</title>'
  A ('<desc id="d">' + $total + ' contributions, best day ' + $best + ', ' + $perActive + ' per active day, busiest on ' + (Esc ([string]$weekdays[1][$peak])) + '.</desc>')

  A '<style>'
  A ('text{font-family:' + $th.Mono + '}.sans{font-family:' + $th.Sans + '}')
  A ('.big{font-size:38px;font-weight:700;fill:' + $th.Title + '}.gold{fill:' + $th.Gold + '}.lab{font-size:14px;fill:' + $th.Tag + '}.wd{font-size:30px;font-weight:700;fill:' + $th.Gold + '}')
  A ('.cu{animation-duration:' + (N $HOLD) + 's;animation-iteration-count:infinite;animation-fill-mode:both;animation-timing-function:steps(1,end)}')
  A ('.gr{transform-box:fill-box;transform-origin:bottom;animation:grow ' + (N $HOLD) + 's ease-out infinite both}')
  A ('@keyframes grow{0%,' + (Ph $C0) + '%{transform:scaleY(0)}' + (Ph ($C0 + $F * $CDT)) + '%,100%{transform:scaleY(1)}}')
  A ('.lg{animation-duration:' + (N $cycle) + 's;animation-iteration-count:infinite;animation-fill-mode:both;animation-timing-function:steps(1,end)}')
  # A light sweeping along the top edge: purely decorative, and it keeps the animation clock ticking.
  A '.sweep{animation:sweep 6s linear infinite}@keyframes sweep{0%{transform:translateX(-260px)}100%{transform:translateX(1000px)}}'
  for ($k = 0; $k -le $F; $k++) {
    $t0 = $C0 + $k * $CDT
    if ($k -lt $F) { A ('@keyframes f' + $k + '{0%{opacity:0}' + (Ph $t0) + '%{opacity:1}' + (Ph ($t0 + $CDT)) + '%,100%{opacity:0}}') }
    else { A ('@keyframes f' + $k + '{0%{opacity:0}' + (Ph $t0) + '%,100%{opacity:1}}') }
  }
  $share = 100.0 / $langs
  for ($q = 0; $q -lt $langs; $q++) {
    if ($q -eq 0) { A ('@keyframes l0{0%{opacity:1}' + (N $share) + '%,100%{opacity:0}}') }
    else { A ('@keyframes l' + $q + '{0%{opacity:0}' + (N ($q * $share)) + '%{opacity:1}' + (N (($q + 1) * $share)) + '%,100%{opacity:0}}') }
  }
  A '@media (prefers-reduced-motion:reduce){*{animation:none!important}.cu{opacity:0}.cu.last{opacity:1}.lg{opacity:0}.lg.first{opacity:1}.sweep{display:none}}'
  A '</style>'

  A '<defs>'
  A ('<radialGradient id="ga" cx=".05" cy="0" r=".9"><stop offset="0" stop-color="#ffd23f" stop-opacity="' + $th.GlowGold + '"/><stop offset="1" stop-color="#ffd23f" stop-opacity="0"/></radialGradient>')
  A ('<radialGradient id="gb" cx="1" cy="1" r=".8"><stop offset="0" stop-color="#3fb950" stop-opacity="' + $th.GlowGreen + '"/><stop offset="1" stop-color="#3fb950" stop-opacity="0"/></radialGradient>')
  A ('<linearGradient id="sw" x1="0" x2="1"><stop offset="0" stop-color="' + $th.Gold + '" stop-opacity="0"/><stop offset=".5" stop-color="' + $th.Gold + '" stop-opacity=".9"/><stop offset="1" stop-color="' + $th.Gold + '" stop-opacity="0"/></linearGradient>')
  A ('<filter id="glow" x="-20%" y="-50%" width="140%" height="200%"><feGaussianBlur in="SourceGraphic" stdDeviation="4" result="b"/><feComponentTransfer in="b" result="g"><feFuncA type="linear" slope="' + $th.GlowSlope + '"/></feComponentTransfer><feMerge><feMergeNode in="g"/><feMergeNode in="SourceGraphic"/></feMerge></filter>')
  A ('<clipPath id="card"><rect x="1" y="1" width="' + ($CARD_W - 2) + '" height="' + ($CARD_H - 2) + '" rx="14"/></clipPath>')
  A '</defs>'
  A ('<rect x=".5" y=".5" width="' + ($CARD_W - 1) + '" height="' + ($CARD_H - 1) + '" rx="14" fill="' + $th.Card + '" stroke="' + $th.Stroke + '"/>')
  A ('<rect x="1" y="1" width="' + ($CARD_W - 2) + '" height="' + ($CARD_H - 2) + '" rx="14" fill="url(#ga)"/>')
  A ('<rect x="1" y="1" width="' + ($CARD_W - 2) + '" height="' + ($CARD_H - 2) + '" rx="14" fill="url(#gb)"/>')
  A ('<g clip-path="url(#card)"><rect class="sweep" x="0" y="0" width="260" height="2" fill="url(#sw)"/></g>')
  for ($i = 1; $i -lt 4; $i++) {
    A ('<line x1="' + (26 + $i * $TILE) + '" y1="30" x2="' + (26 + $i * $TILE) + '" y2="104" stroke="' + $th.Stroke + '"/>')
  }

  # Three counting numbers; the best day is the gold one, because big days are the point.
  for ($i = 0; $i -lt 3; $i++) {
    $x0 = $PAD + $i * $TILE
    $cls = 'big'
    $wrapOpen = '<g>'
    if ($i -eq 1) { $cls = 'big gold'; $wrapOpen = '<g filter="url(#glow)">' }
    A $wrapOpen
    for ($k = 0; $k -le $F; $k++) {
      $eased = 1 - [Math]::Pow(1 - $k / $F, 3)
      $v = [int][Math]::Round($values[$i] * $eased)
      $extra = ''
      if ($k -eq $F) { $extra = ' last' }
      A ('<text class="' + $cls + ' cu' + $extra + '" style="animation-name:f' + $k + '" x="' + $x0 + '" y="74">' + $v + '</text>')
    }
    A '</g>'
  }

  # Busiest weekday: seven bars growing from the bottom, the peak in gold, and its name.
  $x0 = $PAD + 3 * $TILE
  $maxDay = [Math]::Max(1, ($byWeekday | Measure-Object -Maximum).Maximum)
  for ($d = 0; $d -lt 7; $d++) {
    $h = [Math]::Max(3, [Math]::Round(44 * $byWeekday[$d] / $maxDay))
    $fill = $th.Art.G
    if ($d -eq $peak) { $fill = $th.Gold }
    A ('<rect class="gr" x="' + ($x0 + $d * 12) + '" y="' + (78 - $h) + '" width="8" height="' + $h + '" rx="2" fill="' + $fill + '"/>')
  }
  A '<g filter="url(#glow)">'
  for ($q = 0; $q -lt $langs; $q++) {
    $extra = ''
    if ($q -eq 0) { $extra = ' first' }
    A ('<text class="wd lg' + $extra + '" style="animation-name:l' + $q + '" x="' + ($x0 + 96) + '" y="74">' + (Esc ([string]$weekdays[$q][$peak])) + '</text>')
  }
  A '</g>'

  # Labels, one language at a time.
  for ($i = 0; $i -lt 4; $i++) {
    for ($q = 0; $q -lt $langs; $q++) {
      $extra = ''
      if ($q -eq 0) { $extra = ' first' }
      A ('<text class="lab sans lg' + $extra + '" style="animation-name:l' + $q + '" x="' + ($PAD + $i * $TILE) + '" y="104">' + (Esc ([string]$labels[$i][$q])) + '</text>')
    }
  }

  A '</svg>'
  return $sb.ToString()
}

"$total contributions, best $best, $perActive per active day over $active days, peak weekday $peak"
Save-Svg $Out (Build-Stats 'dark')
Save-Svg $LightOut (Build-Stats 'light')
