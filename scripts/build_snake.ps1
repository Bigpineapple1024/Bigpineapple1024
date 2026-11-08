# Generates the contribution snake for the last few months, in light and dark versions.
# Data comes from the public contributions page, the same source Platane/snk reads,
# so private contributions show up exactly as they do on the profile.
# The snake wanders on a route that changes every day, grows one segment per active day it eats,
# shows "+N" for that day's contributions, and fills a bar weighted by contribution count.
param(
  [string]$User = $(if ($env:GITHUB_REPOSITORY_OWNER) { $env:GITHUB_REPOSITORY_OWNER } else { 'Bigpineapple1024' }),
  [int]$Weeks = 13,
  [int]$Seed = 0,   # 0 = use the date of the newest day, so each daily build gets a new route
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
$STEP = 0.1; $START_HOLD = 0.6; $END_HOLD = 2.0; $POP = 0.9
# The snake starts with this many segments and grows as it eats, one per active day,
# spread out evenly once there are more active days than it has room to grow.
$START_LEN = 4; $MAX_LEN = 18
# Long routes walk faster so a loop stays under about this many seconds of walking.
$MAX_WALK = 24
# Random walk: chance of detouring to a random spot before the next meal, and how many detours at most.
$WANDER_P = 0.45; $MAX_WANDER = 3

$PALETTES = @{
  light = @{ Bg = '#ffffff'; Empty = '#ebedf0'; Levels = '#9be9a8', '#40c463', '#30a14e', '#216e39'; Snake = '#d99a00' }
  dark  = @{ Bg = '#0d1117'; Empty = '#161b22'; Levels = '#0e4429', '#006d32', '#26a641', '#39d353'; Snake = '#ffd23f' }
}

function N([double]$v) { return ('{0:0.###}' -f $v) }

# ---- Contribution data. Without per-day counts the bar slices are equal and no "+N" is shown.
$data = Get-Contributions $User $Html
$days = $data.Levels
$counts = $data.Counts

$inv = [Globalization.CultureInfo]::InvariantCulture
$lastKey = $days.Keys | Sort-Object | Select-Object -Last 1
$lastDay = [datetime]::ParseExact($lastKey, 'yyyy-MM-dd', $inv)
$firstDay = $lastDay.AddDays(-[int]$lastDay.DayOfWeek).AddDays(-7 * ($Weeks - 1))
$COLS = $Weeks

$grid = New-Object System.Collections.ArrayList   # every day in range: col, row, level
$targets = @{}                                      # "col,row" -> @(level, count)
for ($day = $firstDay; $day -le $lastDay; $day = $day.AddDays(1)) {
  $key = $day.ToString('yyyy-MM-dd', $inv)
  $lvl = 0
  if ($days.ContainsKey($key)) { $lvl = $days[$key] }
  $c = [int][Math]::Floor(($day - $firstDay).TotalDays / 7)
  $r = [int]$day.DayOfWeek
  [void]$grid.Add(@($c, $r, $lvl))
  if ($lvl -gt 0) {
    $cnt = 0
    if ($counts.ContainsKey($key)) { $cnt = $counts[$key] }
    $targets["$c,$r"] = @($lvl, $cnt)
  }
}

# ---- Snake path: a seeded random walk, so the route changes every day.
# The snake drifts toward random spots or the nearest uneaten day, never reverses, does not bite
# its own body, and avoids moves that would box it in. When everything is eaten it leaves
# through the nearer side, far enough that even the grown tail is off the picture.
if ($Seed -eq 0) { $Seed = [int]$lastDay.ToString('yyyyMMdd', $inv) }
$rng = New-Object System.Random $Seed
$dirs = @(@(1, 0), @(0, 1), @(-1, 0), @(0, -1))

function Get-Reach([int]$FromC, [int]$FromR, $Occ, [int]$CMin, [int]$CMax, [int]$Cap) {
  # Counts free cells reachable from a square, stopping once it has seen $Cap of them.
  $seen = @{ "$FromC,$FromR" = $true }
  $queue = New-Object System.Collections.Queue
  $queue.Enqueue(@($FromC, $FromR))
  while ($queue.Count -gt 0 -and $seen.Count -lt $Cap) {
    $cur = $queue.Dequeue()
    foreach ($dd in $dirs) {
      $nc = $cur[0] + $dd[0]; $nr = $cur[1] + $dd[1]; $nk = "$nc,$nr"
      if ($nr -lt 0 -or $nr -ge $ROWS -or $nc -lt $CMin -or $nc -gt $CMax) { continue }
      if ($seen.ContainsKey($nk) -or $Occ.ContainsKey($nk)) { continue }
      $seen[$nk] = $true
      $queue.Enqueue(@($nc, $nr))
    }
  }
  return $seen.Count
}

# Growth plan: new segment g appears when the snake eats its $growAt[g]-th day (0-based).
$foodCount = $targets.Count
$GROW = [Math]::Min($foodCount, $MAX_LEN - $START_LEN)
$growAt = @(for ($g = 0; $g -lt $GROW; $g++) { [int][Math]::Ceiling(($g + 1) * $foodCount / $GROW) - 1 })
if ($foodCount -gt 24) { $MAX_WANDER = 0 }   # plenty of food already makes it roam

$startRow = $rng.Next(0, $ROWS)
$path = New-Object System.Collections.ArrayList
[void]$path.Add(@(-2, $startRow)); [void]$path.Add(@(-1, $startRow))
$dir = 0
$left = $targets.Clone()
$order = New-Object System.Collections.ArrayList   # cell keys in the order they are eaten
$eatStep = @{}
$len = $START_LEN
$goal = $null; $goalIsFood = $false; $wanders = 0; $exiting = $false; $done = $false
for ($guard = 0; $guard -lt 3000; $guard++) {
  $head = $path[$path.Count - 1]
  $hk = "$($head[0]),$($head[1])"
  if ($left.ContainsKey($hk)) {
    $left.Remove($hk); $eatStep[$hk] = $path.Count - 1; [void]$order.Add($hk)
    $len = $START_LEN + @($growAt | Where-Object { $_ -lt $order.Count }).Count
  }
  $late = $path.Count -gt 260

  if ($left.Count -eq 0) {
    if (-not $exiting) {
      $exiting = $true
      $side = $COLS + $len + 1
      if ($head[0] -lt $COLS / 2) { $side = -($len + 2) }
      $goal = @($side, $head[1])
    }
    if ($head[0] -eq $goal[0]) { $done = $true; break }
  } else {
    $reached = $null -ne $goal -and $head[0] -eq $goal[0] -and $head[1] -eq $goal[1]
    $stale = $goalIsFood -and -not $left.ContainsKey("$($goal[0]),$($goal[1])")
    if ($null -eq $goal -or $reached -or $stale) {
      if (-not $late -and $wanders -lt $MAX_WANDER -and $rng.NextDouble() -lt $WANDER_P) {
        $goal = @($rng.Next(0, $COLS), $rng.Next(0, $ROWS)); $goalIsFood = $false; $wanders++
      } else {
        $best = [double]::MaxValue
        foreach ($k in $left.Keys) {
          $parts = $k.Split(','); $tc = [int]$parts[0]; $tr = [int]$parts[1]
          $dist = [Math]::Abs($tc - $head[0]) + [Math]::Abs($tr - $head[1]) + $rng.NextDouble() * 0.9
          if ($dist -lt $best) { $best = $dist; $goal = @($tc, $tr) }
        }
        $goalIsFood = $true
      }
    }
  }

  $cMin = -1; $cMax = $COLS
  if ($exiting) { $cMin = -($len + 3); $cMax = $COLS + $len + 3 }
  # Squares the body will still cover after this move (the tail moves out of the way),
  # mapped to how many steps until each frees up.
  $occ = @{}
  for ($b = 1; $b -le $len - 1 -and $b -le $path.Count; $b++) {
    $seg = $path[$path.Count - $b]; $occ["$($seg[0]),$($seg[1])"] = $len - $b
  }
  # Mostly heads for the goal, sometimes strays; stricter late in long walks and when leaving.
  $beta = 1.1
  if ($late) { $beta = 3 }
  if ($exiting) { $beta = 4 }
  $here = [Math]::Abs($goal[0] - $head[0]) + [Math]::Abs($goal[1] - $head[1])
  $cands = New-Object System.Collections.ArrayList
  $weights = New-Object System.Collections.ArrayList
  $roomy = New-Object System.Collections.ArrayList
  $bestReach = -1; $bestReachMove = -1
  $soonest = [int]::MaxValue; $soonestMove = -1
  for ($k = 0; $k -lt 4; $k++) {
    if ($k -eq (($dir + 2) % 4)) { continue }
    $nc = $head[0] + $dirs[$k][0]; $nr = $head[1] + $dirs[$k][1]
    if ($nr -lt 0 -or $nr -ge $ROWS -or $nc -lt $cMin -or $nc -gt $cMax) { continue }
    if ($occ.ContainsKey("$nc,$nr")) {
      if ($occ["$nc,$nr"] -lt $soonest) { $soonest = $occ["$nc,$nr"]; $soonestMove = $k }
      continue
    }
    $dist = [Math]::Abs($goal[0] - $nc) + [Math]::Abs($goal[1] - $nr)
    $wt = [Math]::Exp(-$beta * ($dist - $here))
    if ($k -eq $dir) { $wt *= 1.6 }
    $reach = Get-Reach $nc $nr $occ $cMin $cMax ($len + 2)
    if ($reach -gt $bestReach) { $bestReach = $reach; $bestReachMove = $k }
    [void]$cands.Add($k); [void]$weights.Add($wt); [void]$roomy.Add($reach -ge $len)
  }
  # Random choice only among moves that leave room for the whole body; otherwise take the
  # roomiest move, and only touch the body (at the segment about to leave) if there is nothing else.
  for ($q = $cands.Count - 1; $q -ge 0; $q--) {
    if (-not $roomy[$q]) { $cands.RemoveAt($q); $weights.RemoveAt($q) }
  }
  if ($cands.Count -eq 0) {
    if ($bestReachMove -ge 0) { $pick = $bestReachMove }
    elseif ($soonestMove -ge 0) { $pick = $soonestMove }
    else { throw "The snake got stuck at $hk." }
  } else {
    $sum = 0.0
    foreach ($wt in $weights) { $sum += $wt }
    $roll = $rng.NextDouble() * $sum
    $pick = $cands[$cands.Count - 1]
    for ($q = 0; $q -lt $cands.Count; $q++) {
      $roll -= $weights[$q]
      if ($roll -le 0) { $pick = $cands[$q]; break }
    }
  }
  $dir = $pick
  [void]$path.Add(@(($head[0] + $dirs[$dir][0]), ($head[1] + $dirs[$dir][1])))
}
if (-not $done) { throw 'The snake path did not finish.' }
$FINAL_LEN = $START_LEN + $GROW

$STEPS = $path.Count - 1
$STEP = [Math]::Min($STEP, $MAX_WALK / $STEPS)
$LOOP = $START_HOLD + $STEPS * $STEP + $END_HOLD
$total = 0
foreach ($k in $order) { $total += $targets[$k][1] }
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
  $loopS = (N $LOOP) + 's'

  A ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="' + $vbX + ' ' + $vbY + ' ' + $vbW + ' ' + $vbH + '" width="' + ($vbW * $SCALE) + '" height="' + ($vbH * $SCALE) + '" role="img" aria-labelledby="t d">')
  A '<title id="t">Contribution snake</title>'
  $summary = 'A snake walks the last ' + $Weeks + ' weeks and eats ' + $order.Count + ' active days'
  if ($total -gt 0) { $summary += ' (' + $total + ' contributions)' }
  A ('<desc id="d">' + $summary + '.</desc>')

  A '<style>'
  A ('.m{font:9px ' + $th.Sans + ';fill:' + $th.Muted + '}')
  A ('.pop{font:700 7.5px ' + $th.Sans + ';fill:' + $th.Title + ';stroke:' + $pal.Bg + ';stroke-width:2.2px;paint-order:stroke;text-anchor:middle;opacity:0}')
  A ('.s{animation:mv ' + $loopS + ' linear infinite both}')
  A ('.e,.b{animation-duration:' + $loopS + ';animation-timing-function:steps(1,end);animation-iteration-count:infinite;animation-fill-mode:both}')
  A ('.pop{animation-duration:' + $loopS + ';animation-timing-function:linear;animation-iteration-count:infinite;animation-fill-mode:both}')

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

  # e: a cell disappears when eaten. b: its bar slice and the snake's new segment appear.
  # p: the "+N" label pops up and floats away.
  for ($j = 0; $j -lt $order.Count; $j++) {
    $t = At $eatStep[$order[$j]]
    $p = Pct $t
    A ('@keyframes e' + $j + '{0%{opacity:1}' + $p + '%,100%{opacity:0}}')
    A ('@keyframes b' + $j + '{0%{opacity:0}' + $p + '%,100%{opacity:1}}')
    A ('@keyframes p' + $j + '{0%,' + $p + '%{opacity:0;transform:translateY(0)}' + (Pct ($t + 0.01)) + '%{opacity:1;transform:translateY(0)}' + (Pct ($t + $POP)) + '%{opacity:0;transform:translateY(-10px)}100%{opacity:0}}')
  }
  A '@media (prefers-reduced-motion:reduce){*{animation:none!important}.snake,.fill,.pops{display:none}}'
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
    $fill = $pal.Levels[$targets[$order[$j]][0] - 1]
    A ('<rect class="e" style="animation-name:e' + $j + '" x="' + ([int]$parts[0] * $PITCH) + '" y="' + ([int]$parts[1] * $PITCH) + '" width="' + $DOT + '" height="' + $DOT + '" rx="2.5" fill="' + $fill + '"/>')
  }

  # Progress bar: one slice per eaten day, as wide as its share of all contributions.
  A ('<rect y="' + $barY + '" width="' + $gridW + '" height="' + $BAR_H + '" rx="' + ($BAR_H / 2) + '" fill="' + $pal.Empty + '"/>')
  if ($order.Count -gt 0) {
    A '<g class="fill" clip-path="url(#bar)">'
    $x = 0.0
    for ($j = 0; $j -lt $order.Count; $j++) {
      $w = $gridW / $order.Count
      if ($total -gt 0) { $w = $gridW * $targets[$order[$j]][1] / $total }
      $fill = $pal.Levels[$targets[$order[$j]][0] - 1]
      A ('<rect class="b" style="animation-name:b' + $j + '" x="' + (N $x) + '" y="' + $barY + '" width="' + (N ($w + 0.4)) + '" height="' + $BAR_H + '" fill="' + $fill + '"/>')
      $x += $w
    }
    A '</g>'
  }

  # Snake: every segment replays the head's path a few steps later. Tail first so the head draws on top.
  # Segments past the starting length stay hidden until their growth day is eaten, so the snake grows at the tail.
  A '<g class="snake">'
  for ($k = $FINAL_LEN - 1; $k -ge 0; $k--) {
    $sz = [Math]::Max(6, 12 - 0.35 * $k)
    $off = ($DOT - $sz) / 2
    $delay = 0
    if ($k -gt 0) { $delay = $k * $STEP - $LOOP }
    $anim = 'animation-delay:' + (N $delay) + 's'
    if ($k -ge $START_LEN) {
      $anim = 'animation:mv ' + $loopS + ' linear ' + (N $delay) + 's infinite both,b' + $growAt[$k - $START_LEN] + ' ' + $loopS + ' steps(1,end) 0s infinite both'
    }
    A ('<rect class="s" style="' + $anim + '" x="' + (N $off) + '" y="' + (N $off) + '" width="' + (N $sz) + '" height="' + (N $sz) + '" rx="' + (N ($sz * 0.3)) + '" fill="' + $pal.Snake + '"/>')
  }
  A '</g>'

  # "+N" labels rise from each eaten day; they start on the cell so the top row stays clear of the month labels.
  if ($total -gt 0) {
    A '<g class="pops">'
    for ($j = 0; $j -lt $order.Count; $j++) {
      $parts = $order[$j].Split(',')
      A ('<text class="pop" style="animation-name:p' + $j + '" x="' + ([int]$parts[0] * $PITCH + $DOT / 2) + '" y="' + ([int]$parts[1] * $PITCH + 9) + '">+' + $targets[$order[$j]][1] + '</text>')
    }
    A '</g>'
  }

  A '</svg>'
  return $sb.ToString()
}

"$User, $($firstDay.ToString('yyyy-MM-dd', $inv)) .. $lastKey, $($order.Count) active days, $total contributions, seed $Seed, $STEPS steps, loop $(N $LOOP)s"
Save-Svg $Out (Build-Snake 'light')
Save-Svg $DarkOut (Build-Snake 'dark')
