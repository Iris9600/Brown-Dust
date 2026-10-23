# Unattended BD2 checklist update check, run by Windows Task Scheduler every 2 hours.
# 1. A Node script looks for new official notices (no Claude usage when there are none).
# 2. Claude reads the new notices and edits lib/mission_data.dart only when routines change.
# 3. This script runs analyze + tests, then commits or reverts, and shows a Windows toast.
# 4. Commits are pushed to origin/Developing (Solar-owo's saved login); the user merges to main.
# Log: .tool/logs/update-check.log
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$OutputEncoding = [Text.Encoding]::UTF8

$toolDir = Join-Path $root '.tool'
$logDir = Join-Path $toolDir 'logs'
New-Item -ItemType Directory -Force $logDir | Out-Null
$log = Join-Path $logDir 'update-check.log'
$state = Join-Path $toolDir 'bd2-watch-state.json'
$stateBackup = "$state.bak"
$pending = Join-Path $toolDir 'pending-notices.json'
$result = Join-Path $toolDir 'bd2-update-result.txt'
$branch = 'Developing'
# Never open a sign-in prompt from the background; fail and retry next run instead.
$env:GCM_INTERACTIVE = 'never'
$env:GIT_TERMINAL_PROMPT = '0'

function Write-Log([string]$message) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $message" | Out-File -FilePath $log -Append -Encoding utf8
}

function Show-Toast([string]$title, [string]$body) {
    try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $escape = { param($s) [Security.SecurityElement]::Escape($s) }
        $xml.LoadXml("<toast><visual><binding template='ToastGeneric'><text>$(& $escape $title)</text><text>$(& $escape $body)</text></binding></visual></toast>")
        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show(
            [Windows.UI.Notifications.ToastNotification]::new($xml))
    } catch {
        Write-Log "Toast failed: $($_.Exception.Message)"
    }
}

# Run a native command, appending its output to the log; returns its exit code.
# Stderr lines are logged, not treated as fatal (PowerShell 5.1 wraps them as errors).
function Invoke-Logged([string]$file, [string[]]$arguments) {
    $ErrorActionPreference = 'Continue'
    & $file @arguments 2>&1 | ForEach-Object { "    $_" } | Out-File -FilePath $log -Append -Encoding utf8
    return $LASTEXITCODE
}

function Get-CurrentBranch {
    $ErrorActionPreference = 'Continue'
    return "$(& git rev-parse --abbrev-ref HEAD 2>$null)".Trim()
}

# Push local Developing commits that GitHub doesn't have yet. Never force-pushes.
# $notify shows a toast on failure (used right after a new commit, not on silent retries).
function Push-Pending([bool]$notify) {
    $ErrorActionPreference = 'Continue'
    if ((Get-CurrentBranch) -ne $branch) { return }
    if ((Invoke-Logged 'git' @('fetch', '-q', 'origin', $branch)) -ne 0) {
        Write-Log 'Push skipped: could not reach GitHub; will retry next run.'
        if ($notify) { Show-Toast 'BD2 update not pushed yet' 'Committed locally; GitHub unreachable. Will retry next run.' }
        return
    }
    $ahead = [int]"$(& git rev-list --count "origin/$branch..$branch" 2>$null)"
    if ($ahead -eq 0) { return }
    $behind = [int]"$(& git rev-list --count "$branch..origin/$branch" 2>$null)"
    if ($behind -gt 0) {
        Write-Log "Push skipped: origin/$branch has $behind commit(s) not on this PC. Needs a manual pull."
        if ($notify) { Show-Toast 'BD2 update not pushed' "GitHub $branch has newer commits. Ask Claude to sync the branch." }
        return
    }
    if ((Invoke-Logged 'git' @('push', 'origin', $branch)) -eq 0) {
        Write-Log "Pushed $ahead commit(s) to origin/$branch."
    } else {
        Write-Log 'Push failed; will retry next run.'
        if ($notify) { Show-Toast 'BD2 update not pushed yet' 'Committed locally; push failed. See .tool/logs/update-check.log' }
    }
}

# Only ever revert edits made during this run, never the user's own work.
$script:ownsTree = $false
function Undo-Changes {
    if ($script:ownsTree) { & git checkout -- lib test 2>&1 | Out-Null }
}

try {
    if (Test-Path $state) { Copy-Item $state $stateBackup -Force }
    Remove-Item $pending, $result -ErrorAction SilentlyContinue
    Push-Pending $false

    if ((Invoke-Logged 'node' @('tool/check_bd2_updates.mjs', '--out', $pending)) -ne 0) {
        throw 'Notice check failed'
    }
    # Assign before wrapping: PowerShell 5.1 emits "[]" as one item, so
    # @(ConvertFrom-Json '[]').Count is 1, while the assigned value counts as 0.
    $parsed = ConvertFrom-Json (Get-Content $pending -Raw -Encoding UTF8)
    $notices = @($parsed)
    if ($notices.Count -eq 0) {
        Write-Log 'No new notices.'
        exit 0
    }
    Write-Log "New notices: $(($notices | ForEach-Object { $_.subject }) -join ' | ')"

    if ((Get-CurrentBranch) -ne $branch) {
        throw "Current branch is not $branch; skipping so nothing is committed elsewhere"
    }
    if (& git status --porcelain -- lib test) {
        throw 'lib/ or test/ has uncommitted changes; skipping so they are not overwritten'
    }
    $script:ownsTree = $true

    $prompt = Get-Content (Join-Path $PSScriptRoot 'scheduled_update_prompt.md') -Raw -Encoding UTF8
    $allowed = @(
        'Read', 'Grep', 'Glob',
        'Edit(/lib/mission_data.dart)', 'Edit(/test/**)',
        'Edit(/.tool/bd2-update-result.txt)'
    )
    $claudeArgs = @('-p', $prompt.Replace('"', "'"), '--allowedTools') + $allowed
    if ((Invoke-Logged 'claude' $claudeArgs) -ne 0) { throw 'Claude run failed' }
    if (-not (Test-Path $result)) { throw 'Claude did not write a result file' }

    $lines = @(Get-Content $result -Encoding UTF8)
    $verdict = $lines[0].Trim()
    $summary = if ($lines.Count -gt 1) { $lines[1].Trim() } else { '' }
    $changed = [bool](& git status --porcelain -- lib test)
    Write-Log "Claude: $verdict - $summary"

    if ($verdict -ne 'CHANGED' -or -not $changed) {
        if ($changed) { Undo-Changes; Write-Log 'Reverted unexpected edits (verdict was not CHANGED).' }
        exit 0
    }

    $analyze = Invoke-Logged 'flutter' @('analyze')
    $test = if ($analyze -eq 0) { Invoke-Logged 'flutter' @('test') } else { 1 }
    if ($analyze -ne 0 -or $test -ne 0) {
        Undo-Changes
        Write-Log 'Analyze/test failed; changes reverted.'
        Show-Toast 'BD2 checklist update reverted' "Tests failed for: $summary. See .tool/logs/update-check.log"
        exit 1
    }

    & git add -- lib/mission_data.dart test | Out-Null
    $message = "$summary`n`nAutomated from official notices by Windows Task Scheduler.`n`nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
    if ((Invoke-Logged 'git' @('commit', '-q', '-m', $message)) -ne 0) { throw 'git commit failed' }
    $hash = (& git rev-parse --short HEAD).Trim()
    Write-Log "Committed $hash"
    Show-Toast 'BD2 checklist updated' "$summary ($hash). Pushing to $branch for your review; run flutter run to install."
    Push-Pending $true
} catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    # Restore seen state so these notices are retried next run.
    if (Test-Path $stateBackup) { Copy-Item $stateBackup $state -Force }
    Undo-Changes
    exit 1
}
