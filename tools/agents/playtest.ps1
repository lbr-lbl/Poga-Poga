# Playtester acceptance (local role): runtime checks
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $root
$godot = (Resolve-Path 'D:\*\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe').Path
$report = Join-Path $root 'docs\acceptance_playtest.md'
$lines = New-Object System.Collections.Generic.List[string]
$fail = 0
$lines.Add('# Playtester acceptance report')
$lines.Add('')
$lines.Add('Time: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$lines.Add('')
$lines.Add('## Runtime checks')

function Run-Check {
  param($title, [string[]]$argList, $regex)
  $out = & $godot --headless --path $root --fixed-fps 60 @argList 2>&1
  $text = $out -join "`n"
  $m = [regex]::Match($text, $regex)
  if ($m.Success) {
    $script:lines.Add('- [x] ' + $title + ': ' + $m.Value)
  } else {
    $script:lines.Add('- [ ] ' + $title + ' (expected output missing)'); $script:fail++
  }
}
Run-Check -title 'cap snap on empty rebound' -argList @('--','--autotest','--level=0','--stamina-check') -regex 'STAMINA_CHECK PASS[^\r\n]*'
Run-Check -title 'explode -> scatter -> reaggregate' -argList @('--','--autotest','--level=0','--explode-check') -regex 'EXPLODE_CHECK PASS[^\r\n]*'
Run-Check -title 'Esc pause really freezes race' -argList @('--','--autotest','--level=0','--pause-check') -regex 'PAUSE_CHECK PASS[^\r\n]*'
Run-Check -title 'fusion / detach / reabsorb mechanics' -argList @('--','--autotest','--pattern=mechanics') -regex 'MECHANICS fused_at=[^\r\n]*'

$lines.Add('')
if ($fail -eq 0) { $lines.Add('**Verdict: PLAYTEST PASS**') } else { $lines.Add('**Verdict: PLAYTEST FAIL (' + $fail + ')**') }
$lines -join "`n" | Set-Content -Path $report -Encoding UTF8
Write-Host ($lines -join "`n")
if ($fail -ne 0) { exit 1 }