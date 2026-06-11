# clever-cloud-assistant installer (Windows / PowerShell)
# Copies skills, agent, commands, and hook into ~/.claude.
# -RegisterHook also wires hooks/cc-pre-deploy-validate.sh into settings.json (with backup).
param(
    [switch]$RegisterHook,
    [string]$ClaudeDir = (Join-Path $HOME '.claude')
)

$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
$claude = $ClaudeDir

foreach ($dir in 'skills', 'agents', 'commands', 'hooks') {
    New-Item -ItemType Directory -Force (Join-Path $claude $dir) | Out-Null
}

$skills = 'cc-cicd', 'cc-deploy', 'cc-migrations', 'cc-healthcheck'
foreach ($s in $skills) {
    Copy-Item (Join-Path $src "skills\$s") (Join-Path $claude 'skills') -Recurse -Force
    Write-Host "  installed skill   $s"
}
Copy-Item (Join-Path $src 'agents\cc-ops.md') (Join-Path $claude 'agents') -Force
Write-Host '  installed agent   cc-ops'
foreach ($c in 'cc-deploy', 'cc-logs', 'cc-status') {
    Copy-Item (Join-Path $src "commands\$c.md") (Join-Path $claude 'commands') -Force
    Write-Host "  installed command /$c"
}
Copy-Item (Join-Path $src 'hooks\cc-pre-deploy-validate.sh') (Join-Path $claude 'hooks') -Force
Write-Host '  installed hook    cc-pre-deploy-validate.sh'

if ($RegisterHook) {
    $settingsPath = Join-Path $claude 'settings.json'
    $hookCmd = 'bash ~/.claude/hooks/cc-pre-deploy-validate.sh'
    if (-not (Test-Path $settingsPath)) {
        @{ hooks = @{ PreToolUse = @(@{ matcher = 'Bash'; hooks = @(@{ type = 'command'; command = $hookCmd }) }) } } |
            ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding utf8
        Write-Host '  created settings.json with hook registered'
    }
    else {
        Copy-Item $settingsPath "$settingsPath.bak" -Force
        $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
        $already = $settings.hooks.PreToolUse |
            ForEach-Object { $_.hooks } | Where-Object { $_.command -eq $hookCmd }
        if ($already) {
            Write-Host '  hook already registered in settings.json — skipped'
        }
        else {
            if (-not $settings.hooks) { $settings | Add-Member hooks ([pscustomobject]@{}) }
            if (-not $settings.hooks.PreToolUse) { $settings.hooks | Add-Member PreToolUse @() }
            $bashBlock = $settings.hooks.PreToolUse | Where-Object { $_.matcher -eq 'Bash' } | Select-Object -First 1
            $entry = [pscustomobject]@{ type = 'command'; command = $hookCmd }
            if ($bashBlock) {
                $bashBlock.hooks = @($bashBlock.hooks) + $entry
            }
            else {
                $settings.hooks.PreToolUse = @($settings.hooks.PreToolUse) + [pscustomobject]@{
                    matcher = 'Bash'; hooks = @($entry)
                }
            }
            $settings | ConvertTo-Json -Depth 20 | Set-Content $settingsPath -Encoding utf8
            Write-Host "  registered hook in settings.json (backup at settings.json.bak)"
        }
    }
}
else {
    Write-Host ''
    Write-Host 'Hook not registered. Either re-run with -RegisterHook, or add this to'
    Write-Host '~/.claude/settings.json under hooks.PreToolUse (matcher "Bash"):'
    Write-Host '  { "type": "command", "command": "bash ~/.claude/hooks/cc-pre-deploy-validate.sh" }'
}

Write-Host ''
Write-Host 'Done. Restart your Claude Code session to pick up the new skills.'
