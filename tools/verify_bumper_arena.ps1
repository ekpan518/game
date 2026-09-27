param(
    [ValidateSet("rules", "vehicle", "match", "ai", "world", "feel", "docs", "all")]
    [string]$Scope = "all"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure([string]$Message) {
    $script:failures.Add($Message)
}

function Require-File([string]$RelativePath) {
    $path = Join-Path $script:projectRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "缺少文件：$RelativePath"
    }
}

function Require-Absent([string]$RelativePath) {
    $path = Join-Path $script:projectRoot $RelativePath
    if (Test-Path -LiteralPath $path) {
        Add-Failure "旧路径仍然存在：$RelativePath"
    }
}

function Read-Utf8([string]$RelativePath) {
    $path = Join-Path $script:projectRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $null
    }
    return Get-Content -Raw -Encoding UTF8 -LiteralPath $path
}

function Require-Match([string]$RelativePath, [string]$Pattern, [string]$Description) {
    $content = Read-Utf8 $RelativePath
    if ($null -eq $content) {
        Add-Failure "无法检查 $Description，因为缺少 $RelativePath"
        return
    }
    if ($content -notmatch $Pattern) {
        Add-Failure "${RelativePath}：$Description"
    }
}

function Require-Count([string]$RelativePath, [string]$Pattern, [int]$Expected, [string]$Description) {
    $content = Read-Utf8 $RelativePath
    if ($null -eq $content) {
        Add-Failure "无法检查 $Description，因为缺少 $RelativePath"
        return
    }
    $actual = [regex]::Matches($content, $Pattern).Count
    if ($actual -ne $Expected) {
        Add-Failure "${RelativePath}：$Description（期望 $Expected，实际 $actual）"
    }
}

function Test-TrackedHygiene {
    foreach ($entry in @(
        @{ Glob = ".godot/*"; Label = ".godot 缓存" },
        @{ Glob = "*.uid"; Label = ".uid 文件" },
        @{ Glob = "addons/*"; Label = "addons 内容" }
    )) {
        $tracked = @(& git -C $script:projectRoot ls-files -- $entry.Glob)
        if ($LASTEXITCODE -ne 0) {
            Add-Failure "git ls-files 检查失败：$($entry.Label)"
        }
        elseif ($tracked.Count -gt 0) {
            Add-Failure "不应跟踪$($entry.Label)：$($tracked -join ', ')"
        }
    }
}

function Test-LegacyReferences {
    $scanRoots = @("project.godot", "scripts", "scenes", "tests", "README.md", "docs/PROJECT_RULES.md", "docs/GAME_DESIGN.md", "docs/TODO.md")
    $existingRoots = @()
    foreach ($relative in $scanRoots) {
        $candidate = Join-Path $script:projectRoot $relative
        if (Test-Path -LiteralPath $candidate) {
            $existingRoots += $candidate
        }
    }
    $toolsRoot = Join-Path $script:projectRoot "tools"
    if (Test-Path -LiteralPath $toolsRoot) {
        $existingRoots += @(Get-ChildItem -LiteralPath $toolsRoot -File | Where-Object { $_.FullName -ne $PSCommandPath } | ForEach-Object { $_.FullName })
    }
    if ($existingRoots.Count -gt 0) {
        $pathMatches = @(& rg -n --no-heading --color never 'scenes/player|scripts/player|tests/stage0|verify_stage0' @existingRoots 2>$null)
        if ($LASTEXITCODE -eq 0 -and $pathMatches.Count -gt 0) {
            Add-Failure "活动范围仍引用旧 Stage 0 路径：$($pathMatches -join ' | ')"
        }
        elseif ($LASTEXITCODE -notin @(0, 1)) {
            Add-Failure "rg 检查旧路径引用失败"
        }
    }

    $runtimeFiles = @()
    foreach ($relative in @("scripts", "scenes", "tests")) {
        $root = Join-Path $script:projectRoot $relative
        if (Test-Path -LiteralPath $root) {
            $runtimeFiles += @(Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $_.Extension -in @(".gd", ".tscn") } | ForEach-Object { $_.FullName })
        }
    }
    if ($runtimeFiles.Count -gt 0) {
        $legacyMatches = @(& rg -n --no-heading --color never 'Utility|Energy|Prisoner|Chicken|PublicGoods|scripts/player/player_controller\.gd' @runtimeFiles 2>$null)
        if ($LASTEXITCODE -eq 0 -and $legacyMatches.Count -gt 0) {
            Add-Failure "运行时或原生测试仍含旧玩法标识：$($legacyMatches -join ' | ')"
        }
        elseif ($LASTEXITCODE -notin @(0, 1)) {
            Add-Failure "rg 检查旧玩法标识失败"
        }
    }
}

$runRules = $Scope -in @("rules", "all")
$runVehicle = $Scope -in @("vehicle", "all")
$runMatch = $Scope -in @("match", "all")
$runAi = $Scope -in @("ai", "all")
$runWorld = $Scope -in @("world", "all")
$runFeel = $Scope -in @("feel", "all")
$runDocs = $Scope -in @("docs", "all")

if ($runRules) {
    foreach ($file in @(
        "scripts/bumper/drive_command.gd",
        "scripts/bumper/impact_result.gd",
        "scripts/bumper/bumper_rules.gd",
        "tests/bumper/test_bumper_arena.gd",
        "tests/bumper/suites/test_bumper_rules.gd"
    )) { Require-File $file }
    foreach ($action in @("drive_forward", "drive_back", "drive_left", "drive_right")) {
        Require-Match "project.godot" "(?m)^$action=\{" "缺少输入动作 $action"
    }
}

if ($runVehicle) {
    foreach ($file in @(
        "scripts/drivers/driver_controller.gd",
        "scripts/drivers/human_driver.gd",
        "scripts/vehicles/bumper_car.gd",
        "scripts/camera/player_camera.gd",
        "scenes/vehicles/bumper_car.tscn",
        "scenes/vehicles/player_car.tscn",
        "tests/bumper/suites/test_bumper_car.gd"
    )) { Require-File $file }
}

if ($runFeel) {
    foreach ($file in @(
        "scripts/bumper/impact_feedback.gd",
        "scripts/bumper/impact_feedback_rules.gd",
        "scripts/audio/arcade_sound_factory.gd",
        "scripts/effects/impact_burst.gd",
        "scripts/effects/tire_trail.gd",
        "scripts/game/game_feel_director.gd",
        "scripts/camera/player_camera.gd",
        "scripts/ui/match_hud.gd",
        "scenes/effects/impact_burst.tscn",
        "scenes/vehicles/bumper_car.tscn",
        "scenes/vehicles/player_car.tscn",
        "scenes/ui/match_hud.tscn",
        "scenes/main/main.tscn",
        "tests/bumper/suites/test_game_feel.gd"
    )) { Require-File $file }
}

if ($runMatch) {
    foreach ($file in @(
        "scripts/game/elimination_batch_result.gd",
        "scripts/game/match_state.gd",
        "scripts/game/match_controller.gd",
        "scripts/game/death_zone.gd",
        "scripts/ui/match_hud.gd",
        "scenes/ui/match_hud.tscn",
        "tests/bumper/suites/test_match_controller.gd"
    )) { Require-File $file }
}

if ($runAi) {
    foreach ($file in @(
        "scripts/drivers/ai_driver.gd",
        "scenes/vehicles/ai_car.tscn",
        "tests/bumper/suites/test_ai_driver.gd"
    )) { Require-File $file }
}

if ($runWorld) {
    foreach ($file in @(
        "scripts/game/bumper_arena.gd",
        "scenes/arena/arena.tscn",
        "scenes/main/main.tscn",
        "tests/bumper/suites/test_bumper_world.gd"
    )) { Require-File $file }
    Require-Match "project.godot" 'config/name="Bumper Arena"' "项目名必须为 Bumper Arena"
    Require-Match "project.godot" 'run/main_scene="res://scenes/main/main\.tscn"' "主场景路径不正确"
    foreach ($action in @("move_forward", "move_back", "move_left", "move_right")) {
        $projectConfig = Read-Utf8 "project.godot"
        if ($null -ne $projectConfig -and $projectConfig -match "(?m)^$action=\{") {
            Add-Failure "project.godot：旧输入动作 $action 必须删除"
        }
    }
    Require-Match "scenes/arena/arena.tscn" '\[node name="Platform" type="StaticBody3D"' "缺少静态圆形平台"
    Require-Match "scenes/arena/arena.tscn" 'type="CylinderMesh"' "平台必须使用 CylinderMesh"
    Require-Match "scenes/arena/arena.tscn" 'type="CylinderShape3D"' "平台必须使用 CylinderShape3D"
    Require-Match "scenes/arena/arena.tscn" '\[node name="DeathZone" type="Area3D"' "缺少死亡区"
    Require-Match "scenes/arena/arena.tscn" 'size = Vector3\(32, 2, 32\)' "死亡区尺寸必须为 32 x 2 x 32"
    foreach ($spawn in @("SpawnPlayer", "SpawnAI1", "SpawnAI2", "SpawnAI3")) {
        Require-Match "scenes/arena/arena.tscn" ('\[node name="{0}" type="Marker3D"' -f $spawn) "缺少出生点 $spawn"
    }
    Require-Match "scenes/main/main.tscn" '\[node name="BumperArena" type="Node3D"\]' "主场景根节点必须为 BumperArena"
    Require-Match "scenes/main/main.tscn" 'path="res://scripts/game/bumper_arena\.gd"' "主场景必须使用 BumperArena 脚本"
    Require-Match "scenes/main/main.tscn" 'path="res://scenes/arena/arena\.tscn"' "主场景必须实例化 Arena"
    Require-Match "scenes/main/main.tscn" 'path="res://scenes/ui/match_hud\.tscn"' "主场景必须实例化 HUD"
    Require-Match "scenes/main/main.tscn" '\[node name="MatchController" type="Node"' "主场景必须包含 MatchController"
    Require-Match "scenes/main/main.tscn" 'type="ProceduralSkyMaterial"' "主场景必须使用程序化天空"
    Require-Match "scenes/main/main.tscn" 'shadow_enabled = true' "方向光必须启用阴影"
    Require-Count "scenes/main/main.tscn" '\[node name="PlayerCar" parent="\." instance=ExtResource\(' 1 "必须恰有一个玩家车辆实例"
    Require-Count "scenes/main/main.tscn" '\[node name="AI[123]" parent="\." instance=ExtResource\(' 3 "必须恰有三个 AI 车辆实例"
    $arenaScript = Read-Utf8 "scripts/game/bumper_arena.gd"
    if ($null -ne $arenaScript) {
        $reloadCalls = [regex]::Matches($arenaScript, '\.reload_current_scene\(\)').Count
        if ($reloadCalls -ne 1) {
            Add-Failure "scripts/game/bumper_arena.gd：reload_current_scene() 必须恰好调用一次（实际 $reloadCalls）"
        }
    }
    $otherScripts = @()
    $scriptsRoot = Join-Path $projectRoot "scripts"
    if (Test-Path -LiteralPath $scriptsRoot) {
        $otherScripts = @(Get-ChildItem -LiteralPath $scriptsRoot -Recurse -Filter "*.gd" -File | Where-Object { $_.FullName -ne (Join-Path $projectRoot "scripts/game/bumper_arena.gd") })
    }
    foreach ($scriptFile in $otherScripts) {
        if ((Get-Content -Raw -Encoding UTF8 -LiteralPath $scriptFile.FullName) -match '\.reload_current_scene\(') {
            Add-Failure "只有 bumper_arena.gd 可以调用 reload_current_scene()：$($scriptFile.FullName)"
        }
    }
}

if ($runDocs) {
    foreach ($file in @("README.md", "docs/PROJECT_RULES.md", "docs/GAME_DESIGN.md", "docs/TODO.md")) {
        Require-File $file
    }
    foreach ($pattern in @(
        'Bumper Arena|碰碰竞技场',
        'Godot 4\.7\.2',
        'W.*S.*A.*D|W/S/A/D',
        '鼠标',
        'Esc',
        '单击',
        '一名玩家|1 名玩家|1名玩家',
        '三辆 AI|3 辆 AI|3辆 AI',
        '坠落',
        '4\.0 秒|4 秒|四秒',
        '三层|3 层|3层',
        '胜利',
        '失败',
        '重新开始',
        'verify_bumper_arena\.ps1',
        '--scope=all',
        '版本',
        '复现步骤',
        '截图',
        '输出',
        '调试器'
    )) { Require-Match "README.md" $pattern "README 缺少必需说明：$pattern" }
    for ($step = 1; $step -le 6; $step++) {
        Require-Match "README.md" "(?m)^$step\.\s" "人工验收清单必须包含第 $step 步"
    }
    Require-Match "README.md" '待人工.*F5|F5.*待人工|尚待.*F5' "必须明确人工 F5/手感仍待验收"
    Require-Match "docs/GAME_DESIGN.md" '非目标|不包含' "设计摘要必须明确非目标"
    Require-Match "docs/GAME_DESIGN.md" '一命制|一条命' "设计摘要必须说明淘汰规则"
    Require-Match "docs/TODO.md" '(?m)^- \[x\].*移动' "TODO 必须标记移动基础完成"
    Require-Match "docs/TODO.md" '(?m)^- \[x\].*碰碰|(?m)^- \[x\].*Bumper Arena' "TODO 必须标记首版完成"
    foreach ($future in @("音频", "地图", "AI")) {
        Require-Match "docs/TODO.md" "(?m)^- \[ \].*$future" "TODO 必须保留未完成的${future}后续项"
    }
    foreach ($rule in @("GDScript", "内置", "插件", "网络", "英文", "中文", "诚实|如实", "MatchController", "BumperCar")) {
        Require-Match "docs/PROJECT_RULES.md" $rule "项目规则缺少：$rule"
    }
}

if ($Scope -eq "all") {
    foreach ($legacyPath in @(
        "scenes/player/player.tscn",
        "scripts/player/player_controller.gd",
        "tests/stage0/test_stage0.gd",
        "tools/verify_stage0.ps1",
        "docs/superpowers/specs/2026-09-23-stage-0-third-person-movement-design.md",
        "docs/superpowers/plans/2026-09-23-stage-0-third-person-movement.md"
    )) { Require-Absent $legacyPath }
    Require-Match ".gitignore" '(?m)^\.godot/\r?$' ".godot 缓存必须被忽略"
    $projectConfig = Read-Utf8 "project.godot"
    if ($null -ne $projectConfig -and $projectConfig -match '(?m)^\[editor_plugins\]') {
        Add-Failure "project.godot 不得启用 editor_plugins"
    }
    Test-TrackedHygiene
    Test-LegacyReferences
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Output "[FAIL] $failure"
    }
    Write-Output "Bumper Arena $Scope 静态验证失败，共 $($failures.Count) 项。"
    exit 1
}

Write-Output "[PASS] Bumper Arena $Scope 静态验证通过。"
exit 0
