param(
    [ValidateSet("player", "world", "docs", "all")]
    [string]$Scope = "all"
)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$failures = [System.Collections.Generic.List[string]]::new()
$levels = @{ player = 1; world = 2; docs = 3; all = 3 }
$level = $levels[$Scope]
function Add-Failure([string]$Message) { $script:failures.Add($Message) }
function Require-File([string]$RelativePath) {
    $path = Join-Path $script:projectRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Add-Failure "Missing file: $RelativePath" }
}
function Require-Match([string]$RelativePath, [string]$Pattern, [string]$Description) {
    $path = Join-Path $script:projectRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Add-Failure "Cannot check $Description because $RelativePath is missing"; return }
    $content = Get-Content -Raw -Encoding UTF8 -LiteralPath $path
    if ($content -notmatch $Pattern) { Add-Failure "${RelativePath}: $Description" }
}
if ($level -ge 1) {
    @("project.godot", "scripts/player/player_controller.gd", "scenes/player/player.tscn", "tests/stage0/test_stage0.gd") | ForEach-Object { Require-File $_ }
    Require-Match "project.godot" 'config/name="Equilibrium Arena"' "application name is not Equilibrium Arena"
    foreach ($action in @("move_forward", "move_back", "move_left", "move_right")) { Require-Match "project.godot" "(?m)^$action=\{" "missing input action $action" }
    Require-Match "scripts/player/player_controller.gd" 'extends CharacterBody3D' "controller must extend CharacterBody3D"
    Require-Match "scripts/player/player_controller.gd" 'Input\.get_vector\(\s*"move_left",\s*"move_right",\s*"move_forward",\s*"move_back"\s*\)' "movement must use the four mapped actions"
    Require-Match "scripts/player/player_controller.gd" 'spring_arm\.add_excluded_object\(get_rid\(\)\)' "spring arm must exclude the player RID"
    Require-Match "scripts/player/player_controller.gd" 'Input\.mouse_mode == Input\.MOUSE_MODE_CAPTURED' "mouse look must be gated by captured mode"
    Require-Match "scripts/player/player_controller.gd" 'KEY_ESCAPE' "Escape release handling is missing"
    Require-Match "scripts/player/player_controller.gd" 'MOUSE_BUTTON_LEFT' "left-click recapture handling is missing"
    Require-Match "scripts/player/player_controller.gd" 'const MOVE_SPEED := 5\.0' "move speed must be 5 m/s"
    Require-Match "scripts/player/player_controller.gd" 'const ACCELERATION := 20\.0' "acceleration must be 20 m/s squared"
    Require-Match "scripts/player/player_controller.gd" 'const DECELERATION := 24\.0' "deceleration must be 24 m/s squared"
    $controllerPath = Join-Path $projectRoot "scripts/player/player_controller.gd"
    if (Test-Path -LiteralPath $controllerPath -PathType Leaf) {
        $controller = Get-Content -Raw -Encoding UTF8 -LiteralPath $controllerPath
        $moveCalls = [regex]::Matches($controller, '\bmove_and_slide\(\)').Count
        if ($moveCalls -ne 1) { Add-Failure "player_controller.gd: expected exactly one move_and_slide() call, found $moveCalls" }
    }
    Require-Match "scenes/player/player.tscn" '\[node name="Player" type="CharacterBody3D"\]' "Player root must be CharacterBody3D"
    Require-Match "scenes/player/player.tscn" 'type="CapsuleShape3D"' "capsule collision shape is missing"
    Require-Match "scenes/player/player.tscn" 'type="CapsuleMesh"' "capsule mesh is missing"
    Require-Match "scenes/player/player.tscn" 'radius = 0\.4' "capsule radius must be 0.4"
    Require-Match "scenes/player/player.tscn" 'height = 1\.8' "capsule height must be 1.8"
    Require-Match "scenes/player/player.tscn" 'spring_length = 4\.5' "spring arm length must be 4.5"
    Require-Match "scenes/player/player.tscn" 'collision_mask = 1' "spring arm collision mask must be layer 1"
    Require-Match "scenes/player/player.tscn" 'current = true' "Camera3D must be current"
    Require-Match "tests/stage0/test_stage0.gd" '_test_player_contract' "Godot player contract test is missing"
}
if ($level -ge 2) {
    Require-File "scenes/main/main.tscn"
    Require-Match "project.godot" 'run/main_scene="res://scenes/main/main\.tscn"' "main scene entrypoint is missing"
    Require-Match "scenes/main/main.tscn" 'path="res://scenes/player/player\.tscn"' "main scene must instance the reusable player"
    Require-Match "scenes/main/main.tscn" '\[node name="Ground" type="StaticBody3D"' "collision ground is missing"
    Require-Match "scenes/main/main.tscn" 'type="BoxShape3D"' "ground collision shape is missing"
    Require-Match "scenes/main/main.tscn" '\[node name="WorldEnvironment" type="WorldEnvironment"' "world environment is missing"
    Require-Match "scenes/main/main.tscn" '\[node name="DirectionalLight3D" type="DirectionalLight3D"' "directional light is missing"
    Require-Match "scenes/main/main.tscn" 'shadow_enabled = true' "directional light shadows must be enabled"
    Require-Match "tests/stage0/test_stage0.gd" '_test_main_scene_contract' "Godot world contract test is missing"
}
if ($level -ge 3) {
    foreach ($document in @("README.md", "docs/PROJECT_RULES.md", "docs/GAME_DESIGN.md", "docs/TODO.md")) { Require-File $document }
    Require-Match "README.md" 'Godot 4\.7' "README must state the configured Godot version"
    Require-Match "README.md" '单击游戏窗口' "README must explain mouse recapture"
    Require-Match "README.md" '输出.*调试器' "README must request both Output and Debugger details"
    Require-Match "docs/PROJECT_RULES.md" '不依赖.*第三方插件' "project rules must prohibit third-party plugins"
    Require-Match "docs/GAME_DESIGN.md" '阶段 0' "game design must state the current stage boundary"
    Require-Match "docs/TODO.md" '阶段 4' "roadmap must cover through Stage 4"
    Require-Match ".gitignore" '(?m)^\.godot/\r?$' ".godot cache must be ignored"
    foreach ($forbiddenDirectory in @("scripts/ai", "scripts/game", "scripts/ui", "resources/games", "scenes/arena", "scenes/game_nodes", "scenes/ui")) { if (Test-Path -LiteralPath (Join-Path $projectRoot $forbiddenDirectory)) { Add-Failure "Out-of-scope directory exists in Stage 0: $forbiddenDirectory" } }
    $trackedCache = @(& git -C $projectRoot ls-files -- ".godot/*")
    if ($LASTEXITCODE -ne 0) { Add-Failure "git ls-files failed while checking .godot cache" } elseif ($trackedCache.Count -gt 0) { Add-Failure "Tracked .godot cache entries: $($trackedCache -join ', ')" }
    $trackedAddons = @(& git -C $projectRoot ls-files -- "addons/*")
    if ($LASTEXITCODE -ne 0) { Add-Failure "git ls-files failed while checking addons" } elseif ($trackedAddons.Count -gt 0) { Add-Failure "Tracked third-party addon entries: $($trackedAddons -join ', ')" }
    $projectConfig = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $projectRoot "project.godot")
    if ($projectConfig -match '(?m)^\[editor_plugins\]') { Add-Failure "project.godot must not enable editor plugins in Stage 0" }
}
if ($failures.Count -gt 0) { foreach ($failure in $failures) { Write-Output "[FAIL] $failure" }; Write-Output "Stage 0 $Scope verification failed with $($failures.Count) issue(s)."; exit 1 }
Write-Output "[PASS] Stage 0 $Scope contract verification passed."
exit 0
