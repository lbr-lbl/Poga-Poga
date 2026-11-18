# Poga Poga 工程验证脚本（Windows PowerShell）
#
# 用法：
#   powershell -NoProfile -File tools\verify.ps1              # 导入 + 3 关自动跑 + 机制验证
#   powershell -NoProfile -File tools\verify.ps1 -Shots       # 额外输出 3 张界面截图
#   $env:GODOT_EXE = "C:\path\to\godot_console.exe"; powershell -File tools\verify.ps1
#
# 说明：
# - 无头模式使用 --fixed-fps 60，跑得比真实时间快，结果可复现（AI 随机种子固定）；
# - 自动测试不写玩家存档（GameState.persistence_enabled = false）；
# - 任一检查失败脚本以非 0 退出，便于接入 CI。

param(
	[string]$GodotExe = "",
	[switch]$Shots
)

$ErrorActionPreference = "Continue"
$projectRoot = Split-Path -Parent $PSScriptRoot
$failures = New-Object System.Collections.ArrayList

if ([string]::IsNullOrWhiteSpace($GodotExe)) { $GodotExe = $env:GODOT_EXE }
if ([string]::IsNullOrWhiteSpace($GodotExe)) {
	$candidates = @(
		"D:\下载\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe",
		"C:\Program Files\Godot\Godot_v4.7.2-stable_win64_console.exe"
	)
	foreach ($candidate in $candidates) {
		if (Test-Path $candidate) { $GodotExe = $candidate; break }
	}
}
if ([string]::IsNullOrWhiteSpace($GodotExe) -or -not (Test-Path $GodotExe)) {
	Write-Host "找不到 Godot 可执行文件，请设置 GODOT_EXE 环境变量或传 -GodotExe。" -ForegroundColor Red
	exit 2
}

Write-Host "Godot  : $GodotExe" -ForegroundColor DarkGray
Write-Host "Project: $projectRoot" -ForegroundColor DarkGray
Write-Host ""

# 1. 资源导入（含音频）
Write-Host "==> 资源导入" -ForegroundColor Cyan
$importOut = & $GodotExe --headless --path $projectRoot --import --quit 2>&1
if ($LASTEXITCODE -ne 0) {
	[void]$failures.Add("资源导入退出码 $LASTEXITCODE")
	Write-Host ($importOut | Out-String) -ForegroundColor DarkRed
}

# 2. 主场景启动：脚本可解析、输入动作齐全
Write-Host "==> 主场景无头启动" -ForegroundColor Cyan
$smokeOut = & $GodotExe --headless --path $projectRoot --quit-after 5 2>&1
$smokeText = $smokeOut | Out-String
if ($smokeText -match "SCRIPT ERROR|Parse Error") {
	[void]$failures.Add("主场景存在脚本错误")
	Write-Host $smokeText -ForegroundColor DarkRed
}
if ($smokeText -match "缺少输入动作") {
	[void]$failures.Add("InputMap 缺少玩法输入动作")
}

# 3. 三关 AI 自动跑（普通难度）
$levels = @(0, 1, 2)
foreach ($level in $levels) {
	Write-Host "==> 第 $($level + 1) 关自动跑（普通）" -ForegroundColor Cyan
	$runOut = & $GodotExe --headless --path $projectRoot --fixed-fps 60 -- --autotest --level=$level --tier=1 2>&1
	$runText = $runOut | Out-String
	$resultLine = ($runText -split "`n" | Where-Object { $_ -match "AUTOTEST_RESULT" } | Select-Object -First 1)
	if ($resultLine) {
		Write-Host "    $($resultLine.Trim())" -ForegroundColor Green
	} else {
		[void]$failures.Add("第 $($level + 1) 关没有产出 AUTOTEST_RESULT")
	}
	if ($runText -match "SCRIPT ERROR") {
		[void]$failures.Add("第 $($level + 1) 关存在脚本错误")
	}
	$statsLine = ($runText -split "`n" | Where-Object { $_ -match "AUTOTEST_STATS" } | Select-Object -First 1)
	if ($statsLine) {
		Write-Host "    $($statsLine.Trim())" -ForegroundColor DarkGray
		if ($level -eq 0 -and $statsLine -notmatch "eye_coll=[1-9]") {
			[void]$failures.Add("第 1 关没有发生眼睛碰撞（核心机制未触发）")
		}
	} else {
		[void]$failures.Add("第 $($level + 1) 关没有产出 AUTOTEST_STATS")
	}
	$staminaLine = ($runText -split "`n" | Where-Object { $_ -match "AUTOTEST_STAMINA" } | Select-Object -First 1)
	if ($staminaLine) {
		Write-Host "    $($staminaLine.Trim())" -ForegroundColor DarkGray
		if ($level -eq 0) {
			if ($staminaLine -match "min=([\d.]+) max=([\d.]+)") {
				$staminaMin = [double]$matches[1]
				if ($staminaMin -ge 0.85) { [void]$failures.Add("第 1 关耐力几乎没变化（耐力条是摆设）") }
			} else {
				[void]$failures.Add("AUTOTEST_STAMINA 格式不符合预期")
			}
		}
	} else {
		[void]$failures.Add("第 $($level + 1) 关没有产出 AUTOTEST_STAMINA")
	}
}

# 4. 难度档位：简单档应当更容易赢（只做冒烟，不强制胜负）
Write-Host "==> 难度档位冒烟（简单 / 困难）" -ForegroundColor Cyan
foreach ($tier in 0, 2) {
	$tierOut = & $GodotExe --headless --path $projectRoot --fixed-fps 60 -- --autotest --level=0 --tier=$tier 2>&1
	$tierText = $tierOut | Out-String
	$tierLine = ($tierText -split "`n" | Where-Object { $_ -match "AUTOTEST_RESULT" } | Select-Object -First 1)
	if ($tierLine) {
		Write-Host "    $($tierLine.Trim())" -ForegroundColor DarkGray
	} else {
		[void]$failures.Add("难度档位 $tier 没有产出 AUTOTEST_RESULT")
	}
	if ($tierText -match "SCRIPT ERROR") { [void]$failures.Add("难度档位 $tier 存在脚本错误") }
}

# 5. 机制验证：融合 / 眼睛碰撞 / 主动散团 / 重新吸附 / 眼睛形态
Write-Host "==> 机制验证（融合 / 眼睛碰撞 / 散团 / 再吸附 / 形态）" -ForegroundColor Cyan
$mechOut = & $GodotExe --headless --path $projectRoot --fixed-fps 60 -- --autotest --pattern=mechanics --level=0 2>&1
$mechText = $mechOut | Out-String
$mechLine = ($mechText -split "`n" | Where-Object { $_ -match "MECHANICS fused_at" } | Select-Object -First 1)
if ($mechLine) {
	Write-Host "    $($mechLine.Trim())" -ForegroundColor Green
	if (($mechLine -match "fused_at=-1") -or ($mechLine -match "detach_at=-1") -or ($mechLine -match "reabsorb_at=-1")) {
		[void]$failures.Add("融合机制未完整通过（需要 自动吸附 + 主动脱离 + 重新吸附）")
	}
	if ($mechLine -match "eye_form=([\d.]+)\.\.([\d.]+)") {
		if ([double]$matches[1] -ge 0.95) { [void]$failures.Add("机制测试里加速形态未生效") }
		if ([double]$matches[2] -le 1.05) { [void]$failures.Add("机制测试里刹车形态未生效") }
	}
} else {
	[void]$failures.Add("机制验证没有产出 MECHANICS 结果")
}

# 6. 可选：界面截图（需要真实渲染）
if ($Shots) {
	Write-Host "==> 界面截图" -ForegroundColor Cyan
	$guiExe = $GodotExe -replace "_console\.exe$", ".exe"
	if (-not (Test-Path $guiExe)) { $guiExe = $GodotExe }
	$shotOut = & $guiExe --path $projectRoot --resolution 1280x720 -- --shots 2>&1
	$shotText = $shotOut | Out-String
	$shotDir = Join-Path $env:APPDATA "Godot\app_userdata\Poga Poga\shots"
	if (Test-Path $shotDir) {
		Get-ChildItem $shotDir -Filter "*.png" | ForEach-Object { Write-Host "    $($_.FullName)" -ForegroundColor Green }
	} else {
		[void]$failures.Add("没有找到截图输出目录")
	}
	if ($shotText -match "SHADER ERROR|SCRIPT ERROR") { [void]$failures.Add("截图流程存在 shader/脚本错误") }
}

Write-Host ""
if ($failures.Count -gt 0) {
	Write-Host "验证失败：" -ForegroundColor Red
	foreach ($item in $failures) { Write-Host "  - $item" -ForegroundColor Red }
	exit 1
}
Write-Host "全部检查通过。" -ForegroundColor Green
exit 0