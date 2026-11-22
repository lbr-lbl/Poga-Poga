# Judge acceptance (local role): full regression + docs/deliverable consistency
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $root
$report = Join-Path $root 'docs\acceptance_judge.md'
$lines = New-Object System.Collections.Generic.List[string]
$fail = 0
$lines.Add('# Judge acceptance report')
$lines.Add('')
$lines.Add('Time: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$lines.Add('')
$lines.Add('## Full regression')
$out = & '.\tools\verify.ps1' 2>&1
$verifyExit = $LASTEXITCODE
$text = $out -join "`n"
$results = [regex]::Matches($text, 'AUTOTEST_RESULT[^\r\n]*')
if ($verifyExit -eq 0) {
  $lines.Add('- [x] verify.ps1: PASS (exit 0)')
} else {
  $lines.Add('- [ ] verify.ps1: FAIL (exit ' + $verifyExit + ')'); $script:fail++
}
foreach ($r in $results) { $lines.Add('  - ' + $r.Value) }
foreach ($c in [regex]::Matches($text, '(PAUSE_CHECK|STAMINA_CHECK|EXPLODE_CHECK) PASS[^\r\n]*')) { $lines.Add('  - ' + $c.Value) }

$lines.Add('')
$lines.Add('## Docs and deliverables')
$readme = Get-Content 'README.md' -Raw
$specFile = Get-ChildItem -File -Filter '*.md' | Where-Object { $_.Name -match '^[\u4e00-\u9fff]' } | Select-Object -First 1
$spec = if ($specFile) { Get-Content $specFile.FullName -Raw } else { '' }
$checks = @(
  @('README version v0.15', ($readme -match 'v0\.15')),
  @('Spec version v1.12', ($spec -match 'v1\.12')),
  @('README has explosion/scatter rule', ($readme -match 'scatter|explosion|STAMINA_EXPLODE')),
  @('README links face_states.png', ($readme -match 'face_states')),
  @('GLOBAL_REQUIREMENTS exists', (Test-Path 'GLOBAL_REQUIREMENTS.md')),
  @('No temp scripts', (-not (Get-ChildItem -Recurse -Filter '_*.py' -File | Where-Object { $_.FullName -notmatch '\.godot' })))
)
foreach ($c in $checks) {
  if ($c[1]) { $lines.Add('- [x] ' + $c[0]) } else { $lines.Add('- [ ] ' + $c[0]); $script:fail++ }
}

$lines.Add('')
if ($fail -eq 0) { $lines.Add('**Verdict: JUDGE PASS**') } else { $lines.Add('**Verdict: JUDGE FAIL (' + $fail + ')**') }
$lines -join "`n" | Set-Content -Path $report -Encoding UTF8
Write-Host ($lines -join "`n")
if ($fail -ne 0) { exit 1 }