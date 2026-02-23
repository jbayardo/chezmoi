$j = [Console]::In.ReadToEnd() | ConvertFrom-Json

# --- Extract fields ---
$model = $j.model.display_name
$dir = $j.workspace.current_dir
$cwd = $j.workspace.current_dir
$cost = if ($j.cost.total_cost_usd) { $j.cost.total_cost_usd } else { 0 }
$pct = if ($j.context_window.used_percentage) { [int]$j.context_window.used_percentage } else { 0 }
$durationMs = if ($j.cost.total_duration_ms) { [int]$j.cost.total_duration_ms } else { 0 }

# --- ANSI colors ---
$esc = [char]27
$cyan = "$esc[36m"
$green = "$esc[32m"
$yellow = "$esc[33m"
$red = "$esc[31m"
$dim = "$esc[2m"
$reset = "$esc[0m"

# --- Context bar color ---
if ($pct -ge 90) { $barColor = $red }
elseif ($pct -ge 70) { $barColor = $yellow }
else { $barColor = $green }

$filled = [math]::Floor($pct / 5)
$empty = 20 - $filled
$bar = ('█' * $filled) + ('░' * $empty)

# --- Cost & duration ---
$costFmt = '${0:N2}' -f $cost
$mins = [math]::Floor($durationMs / 60000)
$secs = [math]::Floor(($durationMs % 60000) / 1000)

# --- Git info ---
$branch = ''
$staged = 0
$modified = 0
$repoUrl = ''
$repoName = ''

try {
  Push-Location $cwd
  git rev-parse --git-dir 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0) {
    $branch = git branch --show-current 2>$null
    if (-not $branch) { $branch = '' }
    $stagedOut = git diff --cached --numstat 2>$null
    $modifiedOut = git diff --numstat 2>$null
    $staged = if ($stagedOut) { @($stagedOut).Count } else { 0 }
    $modified = if ($modifiedOut) { @($modifiedOut).Count } else { 0 }

    $remote = git remote get-url origin 2>$null
    if ($remote) {
      # Azure DevOps SSH
      if ($remote -match '^git@ssh\.dev\.azure\.com:v3/(.+)/(.+)/(.+?)(?:\.git)?$') {
        $repoUrl = "https://dev.azure.com/$($Matches[1])/$($Matches[2])/_git/$($Matches[3])"
      }
      # Generic SSH (GitHub, GHE, etc.)
      elseif ($remote -match '^git@([^:]+):(.+?)(?:\.git)?$') {
        $repoUrl = "https://$($Matches[1])/$($Matches[2])"
      }
      # HTTPS
      elseif ($remote -match '^https?://') {
        $repoUrl = $remote -replace '\.git$', ''
      }
      # Strip Azure DevOps embedded credentials: https://org@dev.azure.com/...
      if ($repoUrl -match '^https://[^@]+@(.+)$') {
        $repoUrl = "https://$($Matches[1])"
      }
    }
    
    if ($repoUrl) {
      $repoName = Split-Path -Leaf $repoUrl
    }
  }
}
catch {}
finally { Pop-Location }

# --- Build line 1: model, dir, git branch + status, repo link ---
$line1 = "${cyan}[$model]${reset} $dir"

if ($branch) {
  $gitStatus = ''
  if ($staged -gt 0) { $gitStatus += "${green}+${staged}${reset}" }
  if ($modified -gt 0) { $gitStatus += "${yellow}~${modified}${reset}" }
  $line1 += " ${dim}|${reset} $branch"
  if ($gitStatus) { $line1 += " $gitStatus" }
}

if ($repoUrl -and $repoName) {
  # OSC 8 clickable link
  $bel = [char]7
  $line1 += " ${dim}|${reset} ${esc}]8;;${repoUrl}${bel}${cyan}${repoName}${reset}${esc}]8;;${bel}"
}

# --- Build line 2: context bar, cost, duration ---
$line2 = "${barColor}${bar}${reset} ${pct}% ${dim}|${reset} ${yellow}${costFmt}${reset} ${dim}|${reset} ${mins}m ${secs}s"

# Write raw UTF-8 bytes to stdout to preserve escape sequences
$output = $line1 + "`n" + $line2
$bytes = [System.Text.Encoding]::UTF8.GetBytes($output)
$stdout = [Console]::OpenStandardOutput()
$stdout.Write($bytes, 0, $bytes.Length)
$stdout.Flush()
