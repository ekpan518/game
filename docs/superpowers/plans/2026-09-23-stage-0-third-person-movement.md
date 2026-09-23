# Equilibrium Arena Stage 0 Third-Person Movement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Stage 0 Godot 4.7 prototype with a lit collision floor, a capsule player, camera-relative WASD movement, a collision-aware third-person camera, and honest Windows testing instructions.

**Architecture:** Keep the reusable `CharacterBody3D` player and controller in their own scene, then instantiate that scene from a minimal world scene. A repository-local PowerShell contract verifier provides executable red/green checks when Godot is unavailable; a dependency-free GDScript runner provides engine-level checks whenever a Godot 4.7 console executable is available.

**Tech Stack:** Godot 4.7, GDScript, `.tscn` text scenes, PowerShell 5.1+, Git.

**Spec:** `docs/superpowers/specs/2026-09-23-stage-0-third-person-movement-design.md`

## Global Constraints

- Target Windows 11 and Godot 4.7 stable; keep the existing GL Compatibility, D3D12, and Jolt settings.
- Use GDScript and built-in Godot meshes, materials, lights, environment, and physics only.
- Do not add external assets, plugins, online services, Blender files, AI, game nodes, timers, scores, Energy, Utility, or round logic.
- Use English identifiers in code and Chinese for player-facing instructions, troubleshooting, and delivery notes.
- Keep game rules separate from presentation code and stop after Stage 0.
- Do not create empty placeholder directories or commit `.godot/` cache contents.
- Preserve the unrelated untracked `addons/` local-tool directory without modifying, enabling, staging, or committing it.
- Never report an engine or gameplay check as passing unless that exact check was run successfully.

## Review Focus

- Released mouse: mouse motion must not rotate the camera; a left click must recapture it, and Escape must release it again. Task 1 pins the ignored-motion path in the GDScript runner and the branch structure in the static verifier.
- Diagonal input: `Vector2(1, -1)` must produce a unit-length world direction rather than a diagonal speed boost. Task 1 tests this through `calculate_move_direction`.
- Extreme pitch input: values below `-60°` and above `45°` must clamp at those exact limits. Task 1 tests both boundaries.
- Camera collision configuration: the spring arm must use layer 1, length `4.5`, and exclude the player's RID. Task 1 checks the scene properties and controller call.
- Missing Godot executable: static checks must still run, while README and delivery text must label engine startup and input checks as unverified. Task 3 checks this wording and records the conditional engine commands.

## File Map

- Modify `project.godot`: set the application name, add four movement actions, then add the main scene path.
- Create `scripts/player/player_controller.gd`: own movement, gravity, camera rotation, pitch clamp, and mouse capture.
- Create `scenes/player/player.tscn`: own the capsule mesh/collision and camera rig.
- Create `scenes/main/main.tscn`: own environment, light, collision floor, and the player instance.
- Create `tests/stage0/test_stage0.gd`: dependency-free Godot checks for player math, input policy, scene composition, and entrypoint configuration.
- Create `tools/verify_stage0.ps1`: static contract checks with `player`, `world`, and `all` scopes.
- Create `README.md`: own opening, running, controls, acceptance, and error-reporting instructions.
- Create `docs/PROJECT_RULES.md`: own technical and workflow constraints.
- Create `docs/GAME_DESIGN.md`: own the retained gameplay baseline and Stage 0 boundary.
- Create `docs/TODO.md`: own Stage 0–4 progress.
- Track the existing `.editorconfig`, `.gitattributes`, `.gitignore`, `icon.svg`, and `icon.svg.import`; do not alter them unless a verification check proves a required correction.
- Leave the current untracked `addons/` tree untouched; the project must not enable or depend on it.

---

### Task 1: Player Contract, Input Map, and Reusable Controller

**Files:**
- Create: `tools/verify_stage0.ps1`
- Create: `tests/stage0/test_stage0.gd`
- Create: `scripts/player/player_controller.gd`
- Create: `scenes/player/player.tscn`
- Modify: `project.godot`
- Track unchanged: `.editorconfig`, `.gitattributes`, `.gitignore`, `icon.svg`, `icon.svg.import`

**Interfaces:**
- Consumes: existing Godot 4.7 project configuration and default 3D gravity setting.
- Produces: input actions `move_forward`, `move_back`, `move_left`, `move_right`; scene `res://scenes/player/player.tscn`; `calculate_move_direction(input_vector: Vector2) -> Vector3`; `clamp_pitch_radians(angle: float) -> float`; verifier command `powershell -ExecutionPolicy Bypass -File tools/verify_stage0.ps1 -Scope player`.

- [ ] **Step 1: Write the failing static contract verifier**

Create `tools/verify_stage0.ps1` with the following complete content:

```powershell
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

function Add-Failure([string]$Message) {
    $script:failures.Add($Message)
}

function Require-File([string]$RelativePath) {
    $path = Join-Path $script:projectRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Missing file: $RelativePath"
    }
}

function Require-Match([string]$RelativePath, [string]$Pattern, [string]$Description) {
    $path = Join-Path $script:projectRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Failure "Cannot check $Description because $RelativePath is missing"
        return
    }
    $content = Get-Content -Raw -Encoding UTF8 -LiteralPath $path
    if ($content -notmatch $Pattern) {
        Add-Failure "${RelativePath}: $Description"
    }
}

if ($level -ge 1) {
    @(
        "project.godot",
        "scripts/player/player_controller.gd",
        "scenes/player/player.tscn",
        "tests/stage0/test_stage0.gd"
    ) | ForEach-Object { Require-File $_ }

    Require-Match "project.godot" 'config/name="Equilibrium Arena"' "application name is not Equilibrium Arena"
    foreach ($action in @("move_forward", "move_back", "move_left", "move_right")) {
        Require-Match "project.godot" "(?m)^$action=\{" "missing input action $action"
    }

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
        if ($moveCalls -ne 1) {
            Add-Failure "player_controller.gd: expected exactly one move_and_slide() call, found $moveCalls"
        }
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
    foreach ($document in @("README.md", "docs/PROJECT_RULES.md", "docs/GAME_DESIGN.md", "docs/TODO.md")) {
        Require-File $document
    }
    Require-Match "README.md" 'Godot 4\.7' "README must state the configured Godot version"
    Require-Match "README.md" '单击游戏窗口' "README must explain mouse recapture"
    Require-Match "README.md" '输出.*调试器' "README must request both Output and Debugger details"
    Require-Match "docs/PROJECT_RULES.md" '不依赖.*第三方插件' "project rules must prohibit third-party plugins"
    Require-Match "docs/GAME_DESIGN.md" '阶段 0' "game design must state the current stage boundary"
    Require-Match "docs/TODO.md" '阶段 4' "roadmap must cover through Stage 4"
    Require-Match ".gitignore" '(?m)^\.godot/$' ".godot cache must be ignored"

    foreach ($forbiddenDirectory in @(
        "scripts/ai", "scripts/game", "scripts/ui", "resources/games",
        "scenes/arena", "scenes/game_nodes", "scenes/ui"
    )) {
        if (Test-Path -LiteralPath (Join-Path $projectRoot $forbiddenDirectory)) {
            Add-Failure "Out-of-scope directory exists in Stage 0: $forbiddenDirectory"
        }
    }

    $trackedCache = @(& git -C $projectRoot ls-files -- ".godot/*")
    if ($LASTEXITCODE -ne 0) {
        Add-Failure "git ls-files failed while checking .godot cache"
    } elseif ($trackedCache.Count -gt 0) {
        Add-Failure "Tracked .godot cache entries: $($trackedCache -join ', ')"
    }

    $trackedAddons = @(& git -C $projectRoot ls-files -- "addons/*")
    if ($LASTEXITCODE -ne 0) {
        Add-Failure "git ls-files failed while checking addons"
    } elseif ($trackedAddons.Count -gt 0) {
        Add-Failure "Tracked third-party addon entries: $($trackedAddons -join ', ')"
    }

    $projectConfig = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $projectRoot "project.godot")
    if ($projectConfig -match '(?m)^\[editor_plugins\]') {
        Add-Failure "project.godot must not enable editor plugins in Stage 0"
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Output "[FAIL] $failure"
    }
    Write-Output "Stage 0 $Scope verification failed with $($failures.Count) issue(s)."
    exit 1
}

Write-Output "[PASS] Stage 0 $Scope contract verification passed."
exit 0
```

- [ ] **Step 2: Run the static verifier and confirm the red state**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/verify_stage0.ps1 -Scope player
```

Expected: exit code `1`, including failures for missing `scripts/player/player_controller.gd`, `scenes/player/player.tscn`, and movement input actions. Do not continue if the verifier unexpectedly passes.

- [ ] **Step 3: Write the dependency-free Godot test runner**

Create `tests/stage0/test_stage0.gd`. The `player` scope runs before the world exists; the `world` scope is used by Task 2.

```gdscript
extends SceneTree

var failures: Array[String] = []
var scope := "all"


func _init() -> void:
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--scope="):
            scope = argument.trim_prefix("--scope=")
    call_deferred("_run")


func _run() -> void:
    if scope in ["player", "world", "all"]:
        await _test_player_contract()
    if scope in ["world", "all"]:
        await _test_main_scene_contract()

    if failures.is_empty():
        print("[PASS] Godot Stage 0 %s checks passed." % scope)
        quit(0)
        return

    for failure in failures:
        push_error("[FAIL] %s" % failure)
    quit(1)


func _expect(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)


func _test_player_contract() -> void:
    var packed_player := load("res://scenes/player/player.tscn") as PackedScene
    _expect(packed_player != null, "player.tscn must load as a PackedScene")
    if packed_player == null:
        return

    var player = packed_player.instantiate()
    root.add_child(player)
    await process_frame

    _expect(player is CharacterBody3D, "Player root must be CharacterBody3D")

    var forward: Vector3 = player.call("calculate_move_direction", Vector2(0.0, -1.0))
    _expect(forward.is_equal_approx(Vector3.FORWARD), "Forward input must follow camera forward at zero yaw")

    var yaw_for_direction := player.get_node("CameraYaw") as Node3D
    yaw_for_direction.rotation.y = PI / 2.0
    var turned_forward: Vector3 = player.call("calculate_move_direction", Vector2(0.0, -1.0))
    _expect(turned_forward.is_equal_approx(Vector3.LEFT), "Forward input must rotate with camera yaw")
    yaw_for_direction.rotation.y = 0.0

    var diagonal: Vector3 = player.call("calculate_move_direction", Vector2(1.0, -1.0))
    _expect(is_equal_approx(diagonal.length(), 1.0), "Diagonal movement direction must be normalized")

    var min_pitch: float = player.call("clamp_pitch_radians", -PI)
    var max_pitch: float = player.call("clamp_pitch_radians", PI)
    _expect(is_equal_approx(min_pitch, deg_to_rad(-60.0)), "Pitch must clamp to -60 degrees")
    _expect(is_equal_approx(max_pitch, deg_to_rad(45.0)), "Pitch must clamp to 45 degrees")

    var spring_arm := player.get_node("CameraYaw/CameraPitch/SpringArm3D") as SpringArm3D
    _expect(is_equal_approx(spring_arm.spring_length, 4.5), "Spring arm length must be 4.5")
    _expect(spring_arm.collision_mask == 1, "Spring arm must collide with physics layer 1")

    Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    var yaw := player.get_node("CameraYaw") as Node3D
    var pitch := player.get_node("CameraYaw/CameraPitch") as Node3D
    var yaw_before := yaw.rotation.y
    var pitch_before := pitch.rotation.x
    var motion := InputEventMouseMotion.new()
    motion.relative = Vector2(100.0, 50.0)
    player.call("_unhandled_input", motion)
    _expect(is_equal_approx(yaw.rotation.y, yaw_before), "Released mouse motion must not change yaw")
    _expect(is_equal_approx(pitch.rotation.x, pitch_before), "Released mouse motion must not change pitch")

    if DisplayServer.get_name() != "headless":
        var click := InputEventMouseButton.new()
        click.button_index = MOUSE_BUTTON_LEFT
        click.pressed = true
        player.call("_unhandled_input", click)
        _expect(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Left click must recapture the mouse")

        var escape := InputEventKey.new()
        escape.keycode = KEY_ESCAPE
        escape.pressed = true
        player.call("_unhandled_input", escape)
        _expect(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Escape must release the mouse")

    player.queue_free()
    await process_frame

func _test_main_scene_contract() -> void:
    _expect(
        ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/main/main.tscn",
        "project.godot must point to the Stage 0 main scene"
    )

    var packed_main := load("res://scenes/main/main.tscn") as PackedScene
    _expect(packed_main != null, "main.tscn must load as a PackedScene")
    if packed_main == null:
        return

    var main = packed_main.instantiate()
    root.add_child(main)
    await process_frame

    var environment := main.get_node_or_null("WorldEnvironment") as WorldEnvironment
    var light := main.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
    var ground := main.get_node_or_null("Ground") as StaticBody3D
    var ground_mesh_node := main.get_node_or_null("Ground/MeshInstance3D") as MeshInstance3D
    var ground_shape_node := main.get_node_or_null("Ground/CollisionShape3D") as CollisionShape3D
    var player := main.get_node_or_null("Player") as CharacterBody3D

    _expect(environment != null and environment.environment != null, "WorldEnvironment must have an Environment")
    _expect(light != null and light.shadow_enabled, "DirectionalLight3D must cast shadows")
    _expect(ground != null and is_equal_approx(ground.position.y, -0.25), "Ground body must put its top at y = 0")
    _expect(player != null and is_equal_approx(player.position.y, 0.9), "Player capsule must start on the ground")

    var ground_mesh: BoxMesh = null
    var ground_shape: BoxShape3D = null
    if ground_mesh_node != null:
        ground_mesh = ground_mesh_node.mesh as BoxMesh
    if ground_shape_node != null:
        ground_shape = ground_shape_node.shape as BoxShape3D
    _expect(ground_mesh != null and ground_mesh.size.is_equal_approx(Vector3(24.0, 0.5, 24.0)), "Ground mesh must be 24 x 0.5 x 24")
    _expect(ground_shape != null and ground_shape.size.is_equal_approx(Vector3(24.0, 0.5, 24.0)), "Ground collision must match the mesh")

    main.queue_free()
    await process_frame
```

- [ ] **Step 4: Run the Godot player test in red when an engine is available**

Run this detector:

```powershell
$godot = Get-Command godot, godot4, godot_console -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $godot) {
    Write-Output "SKIP: no Godot command is available; retain this as an unrun engine check."
} else {
    & $godot.Source --headless --path . --script res://tests/stage0/test_stage0.gd -- --scope=player
}
```

Expected when Godot exists: non-zero exit because `res://scenes/player/player.tscn` is missing. Expected in the current environment: the explicit `SKIP` line; do not convert it into a pass claim.

- [ ] **Step 5: Add the movement actions and player controller**

In `project.godot`, change `config/name` and add the `[input]` section. Preserve every existing display, physics, and rendering setting.

```ini
[application]

config/name="Equilibrium Arena"
config/features=PackedStringArray("4.7", "GL Compatibility")
config/icon="res://icon.svg"

[input]

move_forward={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":87,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
move_back={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":83,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
move_left={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":65,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
move_right={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":68,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```

Create `scripts/player/player_controller.gd`:

```gdscript
extends CharacterBody3D

const MOVE_SPEED := 5.0
const ACCELERATION := 20.0
const DECELERATION := 24.0
const MOUSE_SENSITIVITY := 0.0025
const MIN_PITCH := deg_to_rad(-60.0)
const MAX_PITCH := deg_to_rad(45.0)

@onready var camera_yaw: Node3D = $CameraYaw
@onready var camera_pitch: Node3D = $CameraYaw/CameraPitch
@onready var spring_arm: SpringArm3D = $CameraYaw/CameraPitch/SpringArm3D

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _ready() -> void:
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
    spring_arm.add_excluded_object(get_rid())


func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
        get_viewport().set_input_as_handled()
        return

    if (
        event is InputEventMouseButton
        and event.pressed
        and event.button_index == MOUSE_BUTTON_LEFT
        and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
    ):
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
        get_viewport().set_input_as_handled()
        return

    if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        camera_yaw.rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
        camera_pitch.rotation.x = clamp_pitch_radians(
            camera_pitch.rotation.x - event.relative.y * MOUSE_SENSITIVITY
        )


func _physics_process(delta: float) -> void:
    if is_on_floor():
        velocity.y = 0.0
    else:
        velocity.y -= gravity * delta

    var input_vector := Input.get_vector(
        "move_left", "move_right", "move_forward", "move_back"
    )
    var direction := calculate_move_direction(input_vector)
    var target_velocity := direction * MOVE_SPEED
    var change_rate := ACCELERATION if not direction.is_zero_approx() else DECELERATION

    velocity.x = move_toward(velocity.x, target_velocity.x, change_rate * delta)
    velocity.z = move_toward(velocity.z, target_velocity.z, change_rate * delta)
    move_and_slide()


func calculate_move_direction(input_vector: Vector2) -> Vector3:
    var forward := -camera_yaw.global_transform.basis.z
    var right := camera_yaw.global_transform.basis.x
    forward.y = 0.0
    right.y = 0.0
    forward = forward.normalized()
    right = right.normalized()

    var direction := right * input_vector.x + forward * -input_vector.y
    if direction.length_squared() > 1.0:
        direction = direction.normalized()
    return direction


func clamp_pitch_radians(angle: float) -> float:
    return clampf(angle, MIN_PITCH, MAX_PITCH)
```

- [ ] **Step 6: Create the reusable player scene**

Create `scenes/player/player.tscn`:

```ini
[gd_scene load_steps=5 format=3]

[ext_resource type="Script" path="res://scripts/player/player_controller.gd" id="1_controller"]

[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_player"]
albedo_color = Color(0.18, 0.62, 0.92, 1)
roughness = 0.75

[sub_resource type="CapsuleMesh" id="CapsuleMesh_player"]
material = SubResource("StandardMaterial3D_player")
radius = 0.4
height = 1.8

[sub_resource type="CapsuleShape3D" id="CapsuleShape3D_player"]
radius = 0.4
height = 1.8

[node name="Player" type="CharacterBody3D"]
floor_snap_length = 0.2
script = ExtResource("1_controller")

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
shape = SubResource("CapsuleShape3D_player")

[node name="BodyMesh" type="MeshInstance3D" parent="."]
mesh = SubResource("CapsuleMesh_player")

[node name="CameraYaw" type="Node3D" parent="."]
position = Vector3(0, 1.3, 0)

[node name="CameraPitch" type="Node3D" parent="CameraYaw"]
rotation = Vector3(-0.174533, 0, 0)

[node name="SpringArm3D" type="SpringArm3D" parent="CameraYaw/CameraPitch"]
spring_length = 4.5
margin = 0.15
collision_mask = 1

[node name="Camera3D" type="Camera3D" parent="CameraYaw/CameraPitch/SpringArm3D"]
current = true
fov = 70.0
```

- [ ] **Step 7: Run the player checks and confirm green**

Run the static verifier again:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/verify_stage0.ps1 -Scope player
```

Expected: exit code `0` and `[PASS] Stage 0 player contract verification passed.`

If a Godot command was found in Step 4, rerun:

```powershell
& $godot.Source --headless --path . --script res://tests/stage0/test_stage0.gd -- --scope=player
```

Expected: exit code `0` and `[PASS] Godot Stage 0 player checks passed.` If Godot remains unavailable, record this engine test as skipped rather than passed.

- [ ] **Step 8: Commit the independently testable player foundation**

Review the exact staged set, then commit:

```powershell
git add -- .editorconfig .gitattributes .gitignore icon.svg icon.svg.import project.godot tools/verify_stage0.ps1 tests/stage0/test_stage0.gd scripts/player/player_controller.gd scenes/player/player.tscn
git diff --cached --check
git diff --cached --stat
git commit -m "feat: add stage 0 player controller"
```

Expected: one commit containing the preserved starter files plus the input/controller/player test slice; no `.godot/` path in `git diff --cached --stat`.

### Task 2: Main World, Lighting, Collision Floor, and Project Entrypoint

**Files:**
- Create: `scenes/main/main.tscn`
- Modify: `project.godot`
- Test: `tools/verify_stage0.ps1`
- Test: `tests/stage0/test_stage0.gd`

**Interfaces:**
- Consumes: `res://scenes/player/player.tscn` from Task 1 and the `world` scopes already present in both test runners.
- Produces: `res://scenes/main/main.tscn` and `application/run/main_scene = res://scenes/main/main.tscn`; F5 becomes the project launch path.

- [ ] **Step 1: Run the world tests and confirm the red state**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/verify_stage0.ps1 -Scope world
```

Expected: exit code `1` with missing `scenes/main/main.tscn` and missing `run/main_scene` failures, while the Task 1 player checks remain green.

When Godot is available, also run:

```powershell
& $godot.Source --headless --path . --script res://tests/stage0/test_stage0.gd -- --scope=world
```

Expected: non-zero exit because the main scene is absent. If no Godot command exists, record `SKIP` exactly as in Task 1.

- [ ] **Step 2: Create the lit collision world**

Create `scenes/main/main.tscn`:

```ini
[gd_scene load_steps=8 format=3]

[ext_resource type="PackedScene" path="res://scenes/player/player.tscn" id="1_player"]

[sub_resource type="StandardMaterial3D" id="StandardMaterial3D_ground"]
albedo_color = Color(0.18, 0.32, 0.22, 1)
roughness = 0.9

[sub_resource type="BoxMesh" id="BoxMesh_ground"]
material = SubResource("StandardMaterial3D_ground")
size = Vector3(24, 0.5, 24)

[sub_resource type="BoxShape3D" id="BoxShape3D_ground"]
size = Vector3(24, 0.5, 24)

[sub_resource type="ProceduralSkyMaterial" id="ProceduralSkyMaterial_stage0"]
sky_top_color = Color(0.08, 0.18, 0.34, 1)
sky_horizon_color = Color(0.56, 0.68, 0.78, 1)
ground_bottom_color = Color(0.04, 0.05, 0.07, 1)
ground_horizon_color = Color(0.38, 0.42, 0.45, 1)

[sub_resource type="Sky" id="Sky_stage0"]
sky_material = SubResource("ProceduralSkyMaterial_stage0")

[sub_resource type="Environment" id="Environment_stage0"]
background_mode = 2
sky = SubResource("Sky_stage0")
ambient_light_source = 3
ambient_light_energy = 0.7

[node name="Main" type="Node3D"]

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("Environment_stage0")

[node name="DirectionalLight3D" type="DirectionalLight3D" parent="."]
rotation = Vector3(-0.959931, -0.523599, 0)
light_energy = 1.2
shadow_enabled = true

[node name="Ground" type="StaticBody3D" parent="."]
position = Vector3(0, -0.25, 0)

[node name="MeshInstance3D" type="MeshInstance3D" parent="Ground"]
mesh = SubResource("BoxMesh_ground")

[node name="CollisionShape3D" type="CollisionShape3D" parent="Ground"]
shape = SubResource("BoxShape3D_ground")

[node name="Player" parent="." instance=ExtResource("1_player")]
position = Vector3(0, 0.9, 0)
```

- [ ] **Step 3: Configure the project entrypoint**

Add the main scene directly below `config/name` in the existing `[application]` section of `project.godot`:

```ini
[application]

config/name="Equilibrium Arena"
run/main_scene="res://scenes/main/main.tscn"
config/features=PackedStringArray("4.7", "GL Compatibility")
config/icon="res://icon.svg"
```

- [ ] **Step 4: Run world, import, and startup checks**

Run the executable static world check:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/verify_stage0.ps1 -Scope world
```

Expected: exit code `0` and `[PASS] Stage 0 world contract verification passed.`

If Godot is available, run all three commands and require exit code `0` from each:

```powershell
& $godot.Source --headless --path . --script res://tests/stage0/test_stage0.gd -- --scope=world
& $godot.Source --headless --path . --editor --quit
& $godot.Source --headless --path . --quit-after 3
```

Expected: the GDScript runner prints `[PASS] Godot Stage 0 world checks passed.`; the editor command reports no parse/resource errors; the startup command loads the configured main scene without an error. If no Godot command is available, explicitly record all three as unrun.

- [ ] **Step 5: Commit the independently launchable world slice**

```powershell
git add -- project.godot scenes/main/main.tscn
git diff --cached --check
git diff --cached --stat
git commit -m "feat: add stage 0 arena scene"
```

Expected: only `project.godot` and `scenes/main/main.tscn` are included in this commit.

### Task 3: Player Documentation, Project Rules, Roadmap, and Final Verification

**Files:**
- Create: `README.md`
- Create: `docs/PROJECT_RULES.md`
- Create: `docs/GAME_DESIGN.md`
- Create: `docs/TODO.md`
- Test: `tools/verify_stage0.ps1`
- Inspect: all Stage 0 tracked files and Git status

**Interfaces:**
- Consumes: the player/world implementation and both verification scopes from Tasks 1–2.
- Produces: Chinese user instructions, persistent project constraints, retained future gameplay rules, an explicit Stage 0 verification status, and the final `all` verification result.

- [ ] **Step 1: Run the full verifier and confirm the documentation red state**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/verify_stage0.ps1 -Scope all
```

Expected: exit code `1` listing `README.md`, `docs/PROJECT_RULES.md`, `docs/GAME_DESIGN.md`, and `docs/TODO.md` as missing. Player and world contract checks must not regress.

- [ ] **Step 2: Write the Windows opening, controls, and error-reporting guide**

Create `README.md`:

```markdown
# Equilibrium Arena（均衡竞技场）

这是一个分阶段开发的单机 3D 博弈原型。当前只完成阶段 0：水平地面、胶囊角色、第三人称镜头和基础移动。

## 版本与状态

- 工程配置版本：Godot 4.7，渲染方式为 GL Compatibility，3D 物理引擎为 Jolt。
- 本次开发环境未检测到可调用的 Godot 可执行文件，因此尚未在引擎中确认资源导入、画面和真实输入；下列手动验收需要在 Windows Godot 中完成。
- 工程不依赖外部模型、付费素材、网络服务或第三方插件。

## 在 Windows 中打开并运行

1. 启动 Godot 4.7 stable。
2. 在项目管理器中点击“导入”，选择本目录的 `project.godot`。
3. 打开项目，等待右上角资源导入完成。
4. 按 F5 运行项目；如果 Godot 询问主场景，应选择 `scenes/main/main.tscn`。
5. 预期看到一块有光照的绿色地面和一个蓝色胶囊角色。

## 操作

- `W / A / S / D`：按当前镜头方向移动。
- 移动鼠标：水平旋转并上下查看；上下角度有限制。
- `Esc`：释放鼠标，方便操作编辑器或关闭窗口。
- 释放后单击游戏窗口：再次捕获鼠标并恢复视角控制。

## 阶段 0 验收

1. 角色开始时站在地面上，不应持续下落。
2. 同时按两个方向键时，斜向移动不应明显快于直线移动。
3. 鼠标可以环绕角色旋转，向上和向下查看不会翻转镜头。
4. 靠近地面观察时，镜头不应穿进地面；胶囊本身不应把镜头顶到近处。
5. 按 Esc 后移动鼠标不再旋转视角；单击游戏窗口后视角控制恢复。

## 出错时请提供

请提供 Godot 的完整版本号、发生问题前的操作步骤、运行窗口截图，以及 Godot 底部“输出”和“调试器”面板中的完整报错文本。若问题与操作有关，请同时说明按了哪些键、是否先按过 Esc、问题能否每次复现。

## 可执行检查

静态契约检查：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/verify_stage0.ps1 -Scope all
```

如果 `godot` 已加入 PATH，可运行编辑器级检查：

```powershell
godot --headless --path . --editor --quit
godot --headless --path . --script res://tests/stage0/test_stage0.gd -- --scope=all
```

头部模式不能代替 F5 画面和操作验收。
```

- [ ] **Step 3: Write the persistent project rules**

Create `docs/PROJECT_RULES.md`:

```markdown
# 项目规则

## 技术边界

- 使用 Windows 11 上的 Godot 4.x 稳定版；当前工程配置为 Godot 4.7。
- 使用 GDScript，不引入 C#、原生扩展或需要额外构建链的代码。
- 游戏为单机离线体验，不实现联网、账号、语音聊天或大模型调用。
- 画面优先使用 Godot 自带基础 Mesh、材质、灯光与环境，不依赖 Blender、外部模型、付费素材、在线服务或第三方插件。
- 不提交 `.godot/`、导出构建和其他可再生成缓存。

## 结构与命名

- 角色移动、场景表现、玩法规则和 UI 保持职责分离。
- 双人收益规则以后使用配置数据与统一结算接口；公共品使用独立结算器接入同一回合流程。
- 代码标识符使用清晰的英文；中文用于玩家说明、错误提示和交付报告。
- 注释解释规则边界和不直观的选择，不写逐行复述代码的注释。
- 不为规划中的功能创建空目录、空脚本或占位资源。

## 分阶段开发

- 一次只实现一个明确获准的阶段，阶段完成后停止并等待试玩反馈。
- 修改下一阶段时保留已经验收的功能，不顺便加入后续玩法。
- 阶段 0 只包含工程、地面、灯光、胶囊玩家、第三人称镜头和基础移动。
- 阶段 1 才增加三处可识别地点；阶段 2–4 才逐步增加节点互动、结算、AI 和完整回合。

## 验证与汇报

- 只把实际运行且退出成功的检查标为通过。
- 头部模式可验证资源和脚本解析，但不能替代 F5 的画面与输入验收。
- 没有 Godot 命令时，应明确列出未运行的引擎检查并给出 Windows 手动步骤。
- 提交前运行契约检查、`git diff --check`，并确认 `.godot/` 未被追踪。
```

- [ ] **Step 4: Preserve the future gameplay baseline without implementing it**

Create `docs/GAME_DESIGN.md`:

```markdown
# Equilibrium Arena 初版玩法基线

## 当前边界

阶段 0 只实现第三人称移动原型。本文其余规则用于约束后续阶段，不代表这些功能已经存在。

## 一局游戏

- 一局 5 回合，角色为玩家、AI Alpha、AI Beta。
- 三者初始 Utility 为 0，初始 Energy 为 10；第五回合后只按 Utility 排名，允许负分和并列第一。
- 阶段 4 启用 Energy：每回合开始恢复 2 点，上限 10 点；移动和双人博弈不消耗 Energy。
- 每回合开放囚徒困境、胆小鬼博弈和公共品三个地点。
- 移动阶段 15 秒：玩家进入范围后按 E 锁定地点，可在截止前更改；未锁定视为不参与。
- 决策阶段 10 秒：选择可在截止前更改，截止后一次性揭晓并且只结算一次。
- 玩家超时默认选择为囚徒困境“合作”、胆小鬼“让路”、公共品“贡献 0”。
- 暂停时计时必须停止；第五回合后显示排名并允许完全重开。

## 地点占用

- 双人节点恰好两人时结算，第三人进入已满节点时被阻止并提示“人数已满”。
- 公共品允许 2–3 名参与者。
- 空节点或只有一人的节点不结算，并提示“无人应局”。
- 玩家选择空地点时按“无人应局”处理；AI 的目标地点在地图和界面中公开显示。

## AI 位置表

| 回合 | Alpha | Beta |
|---:|---|---|
| 1 | 囚徒困境 | 胆小鬼博弈 |
| 2 | 公共品 | 囚徒困境 |
| 3 | 胆小鬼博弈 | 公共品 |
| 4 | 囚徒困境 | 胆小鬼博弈 |
| 5 | 公共品 | 囚徒困境 |

## 双人收益

每格依次为参与者 A / 参与者 B 的 Utility 变化；结算不能依赖谁是人类玩家。

### 囚徒困境

| A / B | B 合作 | B 掠夺 |
|---|---:|---:|
| A 合作 | +3 / +3 | -1 / +5 |
| A 掠夺 | +5 / -1 | 0 / 0 |

### 胆小鬼博弈

| A / B | B 前进 | B 让路 |
|---|---:|---:|
| A 前进 | -4 / -4 | +4 / 0 |
| A 让路 | 0 / +4 | +1 / +1 |

双人收益只改变 Utility，不改变 Energy。

## 公共品

- 每位参与者秘密贡献 0–3 Energy，不得超过当前持有量。
- 两人时总贡献达到 3 成功；三人时总贡献达到 5 成功。
- 成功时每位实际参与者获得 +4 Utility，包括贡献 0 的参与者；失败时所有参与者获得 0 Utility。
- 无论成功或失败，贡献的 Energy 都会扣除且不退还；未参与者不得分。
- 公共品使用独立多人结算器，但与双人节点共用“收集选择、截止、揭晓、返回变化”的外部流程。

## AI 与可见信息

- Alpha 在双人节点约 70% 倾向合作或让路；Beta 两种策略约各 50%。具体概率以后写入配置并固定每局随机种子。
- AI 的目标地点公开，但当前回合策略必须在决策截止后才揭晓。
- 初版不实现谈判、承诺、撒谎、声誉判断、报复型 AI 或联网。
```

- [ ] **Step 5: Record the staged roadmap and verification state**

Create `docs/TODO.md`:

```markdown
# 开发路线

- [x] 阶段 0：工程与第三人称移动
  - 文件、配置和静态契约已完成。
  - 当前开发环境未找到 Godot 命令；编辑器导入、F5 画面和真实输入等待用户手动验收。
- [ ] 阶段 1：中央广场、三处可识别区域、可行走道路与桥梁
- [ ] 阶段 2：通用双人节点、囚徒困境、隐藏选择与首次揭晓
- [ ] 阶段 3：胆小鬼博弈、公共品结算器与统一揭晓界面
- [ ] 阶段 4：两名 AI、五回合流程、倒计时、Energy、积分榜与重开

阶段 0 交付后停止；只有用户明确要求“开始阶段 1”才继续。
```

- [ ] **Step 6: Run the complete verification matrix**

Run the static contract and whitespace checks fresh:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/verify_stage0.ps1 -Scope all
git diff --check
git status --short --branch
git ls-files -- ".godot/*"
git ls-files -- "addons/*"
```

Expected:

- Static verifier exits `0` with `[PASS] Stage 0 all contract verification passed.`
- `git diff --check` prints nothing and exits `0`.
- `git ls-files -- ".godot/*"` prints nothing.
- `git ls-files -- "addons/*"` prints nothing.
- Git status contains the intended Task 3 documentation changes and may also show the preserved unrelated `?? addons/` directory; the addon must remain unstaged and unmodified.

Probe Godot again rather than relying on the earlier result:

```powershell
$godot = Get-Command godot, godot4, godot_console -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -eq $godot) {
    Write-Output "UNVERIFIED: Godot import, script parsing, startup, visuals, and input require Windows manual acceptance."
} else {
    & $godot.Source --version
    & $godot.Source --headless --path . --editor --quit
    & $godot.Source --headless --path . --script res://tests/stage0/test_stage0.gd -- --scope=all
    & $godot.Source --headless --path . --quit-after 3
}
```

Expected in the current environment: the `UNVERIFIED` line. If Godot becomes available, capture each command's exit code and full error output; fix any engine-reported issue before proceeding.

- [ ] **Step 7: Commit documentation and the verified Stage 0 status**

```powershell
git add -- README.md docs/PROJECT_RULES.md docs/GAME_DESIGN.md docs/TODO.md
git diff --cached --check
git diff --cached --stat
git commit -m "docs: add stage 0 player guide"
```

Expected: the commit contains exactly the four user/project documentation files.

- [ ] **Step 8: Perform final scope and handoff checks**

Run:

```powershell
git log --oneline --decorate -5
git status --short --branch
powershell -NoProfile -ExecutionPolicy Bypass -File tools/verify_stage0.ps1 -Scope all
```

Expected: the design, plan, player, world, and documentation commits are present; tracked Stage 0 files are clean; the full static verifier passes. The preserved unrelated `addons/` directory may remain untracked and must be disclosed. Do not add any Stage 1 content. Report the manual F5 checklist from README and stop for user feedback.
