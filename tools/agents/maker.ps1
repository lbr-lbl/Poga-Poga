# Maker acceptance (local role): compile + static feature checks + deliverables
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $root
$godot = 'D:\下载\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
$report = Join-Path $root 'docs\acceptance_maker.md'
$lines = New-Object System.Collections.Generic.List[string]
$fail = 0
$lines.Add('# Maker acceptance report')
$lines.Add('')
$lines.Add('Time: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$lines.Add('')

function Check-Pattern($path, $pattern, $desc) {
  if ((Get-Content $path -Raw) -match $pattern) { $script:lines.Add('- [x] ' + $desc); return $true }
  $script:lines.Add('- [ ] ' + $desc); $script:fail++; return $false
}
function Check-File($path, $desc) {
  if (Test-Path $path) { $script:lines.Add('- [x] ' + $desc); return $true }
  $script:lines.Add('- [ ] ' + $desc); $script:fail++; return $false
}

$lines.Add('## Build')
$out = & $godot --headless --path $root --quit-after 3 2>&1
if ($LASTEXITCODE -eq 0 -and ($out -join "`n") -notmatch 'SCRIPT ERROR') {
  $lines.Add('- [x] headless boot, no SCRIPT ERROR')
} else {
  $lines.Add('- [ ] headless boot failed'); $script:fail++
}

$lines.Add('')
$lines.Add('## Feature checks')
Check-Pattern 'src\sim\racer.gd' 'scattered_timer' 'explosion scatter state'
Check-Pattern 'src\sim\racer.gd' '_draw_tired' 'low-stamina half-lidded eyes'
Check-Pattern 'src\sim\racer.gd' '_draw_exhausted' 'exhausted closed eyes'
Check-Pattern 'src\sim\racer.gd' 'func _draw_squint' 'collision >< expression'
Check-Pattern 'src\sim\racer.gd' 'STAMINA_EXPLODE_STAMINA' 'reaggregate stamina/cap restore'
Check-Pattern 'src\sim\racer.gd' 'DRAIN_CAP_CRITICAL' 'cap keeps draining below 30 percent'
Check-Pattern 'src\data\tuning.gd' 'STAMINA_CAP_FLOOR := 0.10' 'cap can drop below 30 percent'
Check-Pattern 'src\core\game_state.gd' 'guide_enabled' 'guide checkbox persisted'
Check-Pattern 'src\ui\level_select.gd' 'guide_enabled' 'level select guide checkbox'
Check-Pattern 'src\ui\tutorial.gd' 'STEP_MIN_SHOW := 0.12' 'tutorial advances immediately on key'

$lines.Add('')
$lines.Add('## Deliverables')
Check-File 'docs\screenshots\face_states.png' 'face state sheet'
Check-File 'docs\screenshots\tip.png' 'contextual tip focus screenshot'
Check-File 'docs\screenshots\map_finale.png' 'FINALE map overview'
Check-File 'GLOBAL_REQUIREMENTS.md' 'global requirements doc'

$lines.Add('')
if ($fail -eq 0) { $lines.Add('**Verdict: MAKER PASS**') } else { $lines.Add('**Verdict: MAKER FAIL (' + $fail + ')**') }
$lines -join "`n" | Set-Content -Path $report -Encoding UTF8
Write-Host ($lines -join "`n")
if ($fail -ne 0) { exit 1 }