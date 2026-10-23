# Unattended BD2 checklist update check, run by Windows Task Scheduler every 2 hours.
# 1. A Node script looks for new official notices (no Claude usage when there are none).
# 2. Claude reads the new notices and edits lib/mission_data.dart only when routines change.
# 3. This script runs analyze + tests, then commits or reverts, and shows a Windows toast.
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

# Only ever revert edits made during this run, never the user's own work.
$script:ownsTree = $false
function Undo-Changes {
    if ($script:ownsTree) { & git checkout -- lib test 2>&1 | Out-Null }
}

try {
    if (Test-Path $state) { Copy-Item $state $stateBackup -Force }
    Remove-Item $pending, $result -ErrorAction SilentlyContinue

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
    Show-Toast 'BD2 checklist updated' "$summary ($hash). Run flutter run to install on your phone."
} catch {
    Write-Log "ERROR: $($_.Exception.Message)"
    # Restore seen state so these notices are retried next run.
    if (Test-Path $stateBackup) { Copy-Item $stateBackup $state -Force }
    Undo-Changes
    exit 1
}
