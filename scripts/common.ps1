# Shared by the image generators: colours, config loading and output.

function Get-Theme([string]$Name) {
  $fonts = @{
    Mono = "ui-monospace,SFMono-Regular,'SF Mono',Menlo,Consolas,'Liberation Mono','PingFang SC','Hiragino Sans','Microsoft YaHei','Noto Sans CJK SC',monospace"
    Sans = "-apple-system,BlinkMacSystemFont,'Segoe UI','PingFang SC','Hiragino Sans','Microsoft YaHei','Noto Sans CJK SC',sans-serif"
  }
  if ($Name -eq 'light') {
    return $fonts + @{
      Card = '#ffffff'; Stroke = '#d0d7de'; Empty = '#f0f2f4'
      Scatter1 = '#dcf3e1'; Scatter2 = '#e8f6eb'
      Title = '#1f2328'; Muted = '#656d76'; Lead = '#1f2328'; Tag = '#59636e'
      ChipText = '#1f2328'; ChipFill = '#f6f8fa'
      Gold = '#c58a00'
      Levels = '#9c6a00', '#b97f00', '#cf9200', '#e0a400'
      Snake = '#116329', '#1a7f37', '#2da44e', '#4ac26b', '#6fdd8b', '#9be9a8', '#c6f0cf'
      GlowGold = '.16'; GlowGreen = '.12'; GlowSlope = '.35'
      Art = @{ G = '#2da44e'; L = '#4ac26b'; Y = '#f5bd1f'; D = '#b97f00' }
    }
  }
  return $fonts + @{
    Card = '#0d1117'; Stroke = '#30363d'; Empty = '#161b22'
    Scatter1 = '#0e4429'; Scatter2 = '#0b3320'
    Title = '#e6edf3'; Muted = '#7d8590'; Lead = '#f0f6fc'; Tag = '#9198a1'
    ChipText = '#c9d1d9'; ChipFill = '#161b22'
    Gold = '#ffd23f'
    Levels = '#d99a00', '#f2b705', '#ffd23f', '#ffe98a'
    Snake = '#7ee787', '#56d364', '#3fb950', '#2ea043', '#238636', '#1a7f37', '#116329'
    GlowGold = '.13'; GlowGreen = '.14'; GlowSlope = '.8'
    Art = @{ G = '#3fb950'; L = '#7ee787'; Y = '#ffd23f'; D = '#d99a00' }
  }
}

function Read-Config([string]$Path) {
  # Line comments are allowed in the config; Windows PowerShell 5.1 cannot parse them itself.
  $lines = Get-Content -Encoding UTF8 $Path | Where-Object { $_ -notmatch '^\s*//' }
  $json = $lines -join "`n"
  return ($json | ConvertFrom-Json)
}

function Get-Contributions([string]$User, [string]$Html = '') {
  # Reads the public contributions page (the same source Platane/snk uses), or a saved copy of it.
  # Levels: date -> 0..4 for every day shown. Counts: date -> contributions, from the cell tooltips;
  # Counts comes back empty if GitHub changes that markup, so callers must cope without it.
  if ($Html) {
    $page = Get-Content -Raw -Encoding UTF8 $Html
  } else {
    $page = (Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/users/$User/contributions" -Headers @{ 'User-Agent' = 'profile-snake' }).Content
  }
  $levels = @{}
  foreach ($m in [regex]::Matches($page, 'data-date="(\d{4}-\d{2}-\d{2})"[^>]*?data-level="(\d)"')) {
    $levels[$m.Groups[1].Value] = [int]$m.Groups[2].Value
  }
  if ($levels.Count -lt 7) { throw "Found only $($levels.Count) days on the contributions page; its markup may have changed." }
  $counts = @{}
  $dateOfId = @{}
  foreach ($m in [regex]::Matches($page, '<td[^>]*>')) {
    $d = [regex]::Match($m.Value, 'data-date="([^"]+)"'); $id = [regex]::Match($m.Value, '\bid="([^"]+)"')
    if ($d.Success -and $id.Success) { $dateOfId[$id.Groups[1].Value] = $d.Groups[1].Value }
  }
  foreach ($m in [regex]::Matches($page, '<tool-tip[^>]*\bfor="([^"]+)"[^>]*>\s*(\d+) contributions? on')) {
    $id = $m.Groups[1].Value
    if ($dateOfId.ContainsKey($id)) { $counts[$dateOfId[$id]] = [int]$m.Groups[2].Value }
  }
  return @{ Levels = $levels; Counts = $counts }
}

function Save-Svg([string]$Path, [string]$Svg) {
  $full = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
  New-Item -ItemType Directory -Force (Split-Path $full) | Out-Null
  [IO.File]::WriteAllText($full, $Svg, (New-Object Text.UTF8Encoding $false))
  "wrote $full ($((Get-Item $full).Length) bytes)"
}
