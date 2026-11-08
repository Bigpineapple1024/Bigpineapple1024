# Generates the contribution snake for the last few months, in light and dark versions.
# Data comes from the public contributions page, the same source Platane/snk reads,
# so private contributions show up exactly as they do on the profile.
param(
  [string]$User = $(if ($env:GITHUB_REPOSITORY_OWNER) { $env:GITHUB_REPOSITORY_OWNER } else { 'Bigpineapple1024' }),
  [int]$Weeks = 13,
  [string]$Html = '',
  [string]$Out = (Join-Path $PSScriptRoot '../dist/github-snake.svg'),
  [string]$DarkOut = (Join-Path $PSScriptRoot '../dist/github-snake-dark.svg')
)
$ErrorActionPreference = 'Stop'
[Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture
. (Join-Path $PSScriptRoot 'common.ps1')

# Layout in SVG units. The root width/height draw it at $SCALE times this size.
$PITCH = 16; $DOT = 12; $ROWS = 7; $SCALE = 1.5
$TOP = 22; $BAR_GAP = 12; $BAR_H = 6; $BOTTOM = 14
# Timeline in seconds.
$STEP = 0.12; $START_HOLD = 0.6; $END_HOLD = 2.0
# Segment sizes, head first.
$SEG_SIZES = 12, 10.5, 9, 7.5

$PALETTES = @{
  light = @{ Empty = '#ebedf0'; Levels = '#9be9a8', '#40c463', '#30a14e', '#216e39'; Snake = '#d99a00' }
  dark  = @{ Empty = '#161b22'; Levels = '#0e4429', '#006d32', '#26a641', '#39d353'; Snake = '#ffd23f' }
}

function N([double]$v) { return ('{0:0.###}' -f $v) }

# ---- Contribution data
if ($Html) {
  $page = Get-Content -Raw -Encoding UTF8 $Html
} else {
  $page = (Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/users/$User/contributions" -Headers @{ 'User-Agent' = 'profile-snake' }).Content
}
$days = @{}
foreach ($m in [regex]::Matches($page, 'data-date="(\d{4}-\d{2}-\d{2})"[^>]*?data-level="(\d)"')) {
  $days[$m.Groups[1].Value] = [int]$m.Groups[2].Value
}
if ($days.Count -lt 7) { throw "Found only $($days.Count) days on the contributions page; its markup may have changed." }

$inv = [Globalization.CultureInfo]::InvariantCulture
$lastKey = $days.Keys | Sort-Object | Select-Object -Last 1
$lastDay = [datetime]::ParseExact($lastKey, 'yyyy-MM-dd', $inv)
$firstDay = $lastDay.AddDays(-[int]$lastDay.DayOfWeek).AddDays(-7 * ($Weeks - 1))
$COLS = $Weeks

$grid = New-Object System.Collections.ArrayList   # every day in range: col, row, level
$targets = @{}                                      # "col,row" -> level, for days with contributions
for ($day = $firstDay; $day -le $lastDay; $day = $day.AddDays(1)) {
  $key = $day.ToString('yyyy-MM-dd', $inv)
  $lvl = 0
  if ($days.ContainsKey($key)) { $lvl = $days[$key] }
  $c = [int][Math]::Floor(($day - $firstDay).TotalDays / 7)
  $r = [int]$day.DayOfWeek
  [void]$grid.Add(@($c, $r, $lvl))
  if ($lvl -gt 0) { $targets["$c,$r"] = $lvl }
}
$levelOf = $targets.Clone()

# ---- Snake path
# Head enters from the left, always heads for the nearest uneaten cell without U-turns,
# then leaves through the nearer side.
$dirs = @(@(1, 0), @(0, 1), @(-1, 0), @(0, -1))
$head = @(-2, 3); $dir = 0
$path = New-Object System.Collections.ArrayList
[void]$path.Add($head)
$order = New-Object System.Collections.ArrayList   # cell keys in the order they are eaten
$eatStep = @{}
$exitAt = $null
$done = $false
for ($guard = 0; $guard -lt 5000; $guard++) {
  if ($targets.Count -gt 0) {
    $goal = $null; $best = [int]::MaxValue
    foreach ($k in $targets.Keys) {
      $parts = $k.Split(','); $tc = [int]$parts[0]; $tr = [int]$parts[1]
      $dist = [Math]::Abs($tc - $head[0]) + [Math]::Abs($tr - $head[1])
      if ($dist -lt $best -or ($dist -eq $best -and ($tc -lt $goal[0] -or ($tc -eq $goal[0] -and $tr -lt $goal[1])))) {
        $best = $dist; $goal = @($tc, $tr)
      }
    }
    $cMin = -1; $cMax = $COLS
  } else {
    if ($null -eq $exitAt) {
      $side = $COLS + 5
      if ($head[0] -lt $COLS / 2) { $side = -6 }
      $exitAt = @($side, $head[1])
    }
    $goal = $exitAt; $cMin = -6; $cMax = $COLS + 5
    if ($head[0] -eq $goal[0] -and $head[1] -eq $goal[1]) { $done = $true; break }
  }

  $here = [Math]::Abs($goal[0] - $head[0]) + [Math]::Abs($goal[1] - $head[1])
  $pick = -1; $pickScore = [double]::MaxValue
  for ($k = 0; $k -lt 4; $k++) {
    if ($k -eq (($dir + 2) % 4)) { continue }
    $nc = $head[0] + $dirs[$k][0]; $nr = $head[1] + $dirs[$k][1]
    if ($nr -lt 0 -or $nr -ge $ROWS -or $nc -lt $cMin -or $nc -gt $cMax) { continue }
    $dist = [Math]::Abs($goal[0] - $nc) + [Math]::Abs($goal[1] - $nr)
    # Prefer getting closer and going straight; when nothing gets closer, turn instead of running away.
    $score = $dist * 4
    if ($k -eq $dir) {
      if ($dist -lt $here) { $score -= 1 } else { $score += 2 }
    }
    if ($score -lt $pickScore) { $pickScore = $score; $pick = $k }
  }
  if ($pick -lt 0) { throw "The snake got stuck at $($head -join ',')." }
  $dir = $pick
  $head = @(($head[0] + $dirs[$dir][0]), ($head[1] + $dirs[$dir][1]))
  [void]$path.Add($head)
  $key = "$($head[0]),$($head[1])"
  if ($targets.ContainsKey($key)) {
    $eatStep[$key] = $path.Count - 1
    [void]$order.Add($key)
    $targets.Remove($key)
  }
}
if (-not $done) { throw 'The snake path did not finish.' }

$STEPS = $path.Count - 1
$LOOP = $START_HOLD + $STEPS * $STEP + $END_HOLD
function At([int]$i) { return $START_HOLD + $i * $STEP }
function Pct([double]$sec) { return (N ($sec / $LOOP * 100)) }

# ---- SVG
function Build-Snake([string]$ThemeName) {
  $pal = $PALETTES[$ThemeName]
  $th = Get-Theme $ThemeName
  $sb = New-Object System.Text.StringBuilder
  function A([string]$s) { [void]$sb.Append($s) }

  $gridW = $COLS * $PITCH - ($PITCH - $DOT)
  $gridH = $ROWS * $PITCH - ($PITCH - $DOT)
  $barY = $gridH + $BAR_GAP
  $vbX = -$PITCH; $vbY = -$TOP
  $vbW = $gridW + 2 * $PITCH
  $vbH = $TOP + $barY + $BAR_H + $BOTTOM

  A ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="' + $vbX + ' ' + $vbY + ' ' + $vbW + ' ' + $vbH + '" width="' + ($vbW * $SCALE) + '" height="' + ($vbH * $SCALE) + '" role="img" aria-labelledby="t d">')
  A '<title id="t">Contribution snake</title>'
  A ('<desc id="d">A snake eats the last ' + $Weeks + ' weeks of contributions: ' + $order.Count + ' active days.</desc>')

  A '<style>'
  A ('.m{font:9px ' + $th.Sans + ';fill:' + $th.Muted + '}')
  A ('.s{animation:mv ' + (N $LOOP) + 's linear infinite both}')
  A ('.e,.b{animation-duration:' + (N $LOOP) + 's;animation-timing-function:steps(1,end);animation-iteration-count:infinite;animation-fill-mode:both}')

  # Head keyframes only at the start, the corners and the end; linear motion fills the straight runs.
  A '@keyframes mv{'
  $p0 = $path[0]
  A ('0%{transform:translate(' + ($p0[0] * $PITCH) + 'px,' + ($p0[1] * $PITCH) + 'px)}')
  for ($i = 0; $i -le $STEPS; $i++) {
    $isCorner = $i -eq 0 -or $i -eq $STEPS
    if (-not $isCorner) {
      $a = $path[$i - 1]; $b = $path[$i]; $c2 = $path[$i + 1]
      $isCorner = ($b[0] - $a[0]) -ne ($c2[0] - $b[0]) -or ($b[1] - $a[1]) -ne ($c2[1] - $b[1])
    }
    if ($isCorner) {
      $pt = $path[$i]
      A ((Pct (At $i)) + '%{transform:translate(' + ($pt[0] * $PITCH) + 'px,' + ($pt[1] * $PITCH) + 'px)}')
    }
  }
  $pe = $path[$STEPS]
  A ('100%{transform:translate(' + ($pe[0] * $PITCH) + 'px,' + ($pe[1] * $PITCH) + 'px)}}')

  for ($j = 0; $j -lt $order.Count; $j++) {
    $p = Pct (At $eatStep[$order[$j]])
    A ('@keyframes e' + $j + '{0%{opacity:1}' + $p + '%,100%{opacity:0}}')
    A ('@keyframes b' + $j + '{0%{opacity:0}' + $p + '%,100%{opacity:1}}')
  }
  A '@media (prefers-reduced-motion:reduce){*{animation:none!important}.snake,.fill{display:none}}'
  A '</style>'

  A ('<defs><clipPath id="bar"><rect width="' + $gridW + '" height="' + $BAR_H + '" y="' + $barY + '" rx="' + ($BAR_H / 2) + '"/></clipPath></defs>')

  # Month labels, like the profile calendar; the first one is dropped if the next is too close.
  $labels = New-Object System.Collections.ArrayList
  for ($c = 0; $c -lt $COLS; $c++) {
    $wk = $firstDay.AddDays(7 * $c)
    if ($c -eq 0 -or $wk.Month -ne $firstDay.AddDays(7 * ($c - 1)).Month) { [void]$labels.Add(@($c, $wk.ToString('MMM', $inv))) }
  }
  if ($labels.Count -gt 1 -and $labels[1][0] -le 2) { $labels.RemoveAt(0) }
  foreach ($lb in $labels) { A ('<text class="m" x="' + ($lb[0] * $PITCH) + '" y="-8">' + $lb[1] + '</text>') }

  # Calendar
  foreach ($g in $grid) {
    A ('<rect x="' + ($g[0] * $PITCH) + '" y="' + ($g[1] * $PITCH) + '" width="' + $DOT + '" height="' + $DOT + '" rx="2.5" fill="' + $pal.Empty + '"/>')
  }
  for ($j = 0; $j -lt $order.Count; $j++) {
    $parts = $order[$j].Split(',')
    $fill = $pal.Levels[$levelOf[$order[$j]] - 1]
    A ('<rect class="e" style="animation-name:e' + $j + '" x="' + ([int]$parts[0] * $PITCH) + '" y="' + ([int]$parts[1] * $PITCH) + '" width="' + $DOT + '" height="' + $DOT + '" rx="2.5" fill="' + $fill + '"/>')
  }

  # Progress bar: one slice per eaten day, in the order the snake eats them.
  A ('<rect y="' + $barY + '" width="' + $gridW + '" height="' + $BAR_H + '" rx="' + ($BAR_H / 2) + '" fill="' + $pal.Empty + '"/>')
  if ($order.Count -gt 0) {
    $w = $gridW / $order.Count
    A '<g class="fill" clip-path="url(#bar)">'
    for ($j = 0; $j -lt $order.Count; $j++) {
      $fill = $pal.Levels[$levelOf[$order[$j]] - 1]
      A ('<rect class="b" style="animation-name:b' + $j + '" x="' + (N ($j * $w)) + '" y="' + $barY + '" width="' + (N ($w + 0.4)) + '" height="' + $BAR_H + '" fill="' + $fill + '"/>')
    }
    A '</g>'
  }

  # Snake: every segment replays the head's path a few steps later. Tail first so the head draws on top.
  A '<g class="snake">'
  for ($k = $SEG_SIZES.Count - 1; $k -ge 0; $k--) {
    $sz = $SEG_SIZES[$k]
    $off = ($DOT - $sz) / 2
    $delay = 0
    if ($k -gt 0) { $delay = $k * $STEP - $LOOP }
    A ('<rect class="s" style="animation-delay:' + (N $delay) + 's" x="' + (N $off) + '" y="' + (N $off) + '" width="' + (N $sz) + '" height="' + (N $sz) + '" rx="' + (N ($sz * 0.3)) + '" fill="' + $pal.Snake + '"/>')
  }
  A '</g>'

  A '</svg>'
  return $sb.ToString()
}

"$User, $($firstDay.ToString('yyyy-MM-dd', $inv)) .. $lastKey, $($order.Count) active days, $STEPS steps, loop $(N $LOOP)s"
Save-Svg $Out (Build-Snake 'light')
Save-Svg $DarkOut (Build-Snake 'dark')
