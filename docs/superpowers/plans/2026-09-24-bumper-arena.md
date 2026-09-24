# Bumper Arena Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Stage 0 capsule prototype with a complete single-player bumper-car elimination match: one human car versus three AI cars on a finite circular platform, deterministic knockback, four-second kill credit, capped kill buffs, victory/defeat, and restart.

**Architecture:** Keep vehicles as `CharacterBody3D` nodes and separate driver commands, vehicle motion, pure impact math, authoritative match state, AI decisions, arena assembly, and HUD updates. Cars report contacts; `MatchController` resolves each unordered pair once per physics frame from stable velocity snapshots, batches same-frame deaths, and is the only authority for kill credit, buffs, and results.

**Tech Stack:** Godot 4.7.2 stable, GDScript, Jolt Physics, GL Compatibility, built-in Godot nodes/resources, dependency-free headless Godot tests, and a supplemental Windows PowerShell structural verifier.

**Spec:** `docs/superpowers/specs/2026-09-24-bumper-arena-design.md`

## Global Constraints

- Target Windows 11 and Godot `4.7.2.stable`; preserve `GL Compatibility`, Windows `d3d12`, and `Jolt Physics` project settings.
- Use GDScript and Godot built-in nodes, meshes, materials, signals, and UI only.
- Do not track or depend on `addons/`, external assets, paid assets, online services, networking, native extensions, or C#.
- First version is exactly one human car and three AI cars on one unguarded circular platform.
- Controls are W/S for forward, brake, and reverse, and A/D for steering; no dash, drift action, weapons, pickups, respawns, spectators, or vehicle selection.
- A car is eliminated once when it falls; the player loses whenever the player is among same-frame deaths, otherwise the player wins when no AI remains.
- Kill credit uses the last effective opponent attack within `4.0` match seconds; self-falls grant no buff.
- Each surviving killer gains one power stack, capped at three; each stack gives `+15%` outgoing knockback and `-8%` incoming knockback, with no speed change.
- AI uses the same motion and combat values as the player, attacks the nearest live opponent, and gives edge recovery higher priority than pursuit.
- Player-facing text and delivery documentation are Chinese; code identifiers are English.
- The old game-theory runtime and active design/plan are removed from the final tracked tree and retained only in Git history.
- Preserve the user's untracked root `addons/`, `node_3d.tscn`, and generated `.uid` sidecars; an isolated execution worktree must not copy, modify, stage, or delete them.
- Native Godot tests are behavioral evidence; the PowerShell verifier is only a structural, scope, and repository-hygiene guard.

## Review Focus

- Duplicate bilateral or multi-slide contact reports: `(A,B)` and `(B,A)` in one physics frame must produce exactly one resolution, while a later physics frame must resolve normally; Task 3 pins this with a reversed-pair test.
- Grazing, zero-length, or reversed contact direction: sub-threshold/tangential contact must not refresh kill credit or create a wrongly directed impulse; Task 1 pins this in pure rule tests.
- Four-second boundary and simultaneous deaths: age exactly `4.0` remains credited, slightly older does not, dead killers receive no usable stack, and player death overrides same-frame victory; Task 3 pins all four cases.
- AI edge and target failures: outward motion near the edge must override pursuit, the center-point zero vector must stay finite, and freed/dead/no targets must not be dereferenced; Task 4 pins these cases.
- Restart re-entry and residual state: button plus Enter may request restart repeatedly, but only one request is accepted and a fresh scene starts at four alive/zero stacks; Task 3 pins the latch and Task 5 pins fresh-scene state.

---

### Task 1: Pure Commands, Impact Rules, Input Map, and Native Test Runner

**Files:**
- Create: `scripts/bumper/drive_command.gd`
- Create: `scripts/bumper/impact_result.gd`
- Create: `scripts/bumper/bumper_rules.gd`
- Create: `tests/bumper/test_bumper_arena.gd`
- Create: `tests/bumper/suites/test_bumper_rules.gd`
- Modify: `project.godot`

**Interfaces:**
- Consumes: Godot `Vector2`, `Vector3`, and the spec constants only; no scene nodes.
- Produces: `DriveCommand.create(throttle: float, steering: float) -> DriveCommand`; `BumperRules.clamp_stacks(stacks: int) -> int`; `outgoing_multiplier(stacks: int) -> float`; `incoming_multiplier(stacks: int) -> float`; `pair_key(first_id: int, second_id: int) -> String`; `calculate_attack(attacker_velocity: Vector3, defender_velocity: Vector3, attacker_to_defender: Vector3, attacker_stacks: int, defender_stacks: int) -> ImpactResult`.

- [ ] **Step 1: Add the rules scope and failing pure-rule suite**

Create a dependency-free `SceneTree` runner that accepts only `rules` and `all` at this task, rejects every unknown scope with exit `1`, loads `test_bumper_rules.gd`, prints each failure with `[FAIL]`, and prints `[PASS] Godot Bumper Arena <scope> checks passed.` only when at least one suite ran and no failures exist.

Use this runner structure and extend only its `suite_scripts` selection in later tasks:

```gdscript
extends SceneTree

const RULES_SUITE = preload("res://tests/bumper/suites/test_bumper_rules.gd")
var scope := "all"

func _init() -> void:
    for argument in OS.get_cmdline_user_args():
        if argument.begins_with("--scope="):
            scope = argument.trim_prefix("--scope=")
    call_deferred("_run")

func _run() -> void:
    if scope not in ["rules", "all"]:
        push_error("[FAIL] Unsupported Bumper Arena test scope: %s." % scope)
        quit(1)
        return
    var suite_scripts: Array[Script] = [RULES_SUITE]
    var failures: Array[String] = []
    for suite_script in suite_scripts:
        var suite_failures: Array[String] = await suite_script.new().run(self)
        failures.append_array(suite_failures)
    if failures.is_empty():
        print("[PASS] Godot Bumper Arena %s checks passed." % scope)
        quit(0)
        return
    for failure in failures:
        push_error("[FAIL] %s" % failure)
    quit(1)
```

The rules suite must contain these assertions before production files exist:

```gdscript
func run(tree: SceneTree) -> Array[String]:
    await tree.process_frame
    var failures: Array[String] = []
    var command_script = load("res://scripts/bumper/drive_command.gd")
    var rules = load("res://scripts/bumper/bumper_rules.gd")
    _expect(command_script != null, "DriveCommand script must load", failures)
    _expect(rules != null, "BumperRules script must load", failures)
    if command_script == null or rules == null:
        return failures
    var command = command_script.create(2.0, -2.0)
    _expect(is_equal_approx(command.throttle, 1.0), "Throttle must clamp to 1", failures)
    _expect(is_equal_approx(command.steering, -1.0), "Steering must clamp to -1", failures)
    _expect(is_equal_approx(rules.outgoing_multiplier(3), 1.45), "Three stacks must deal 1.45x", failures)
    _expect(is_equal_approx(rules.incoming_multiplier(3), 0.76), "Three stacks must receive 0.76x", failures)
    _expect(rules.clamp_stacks(-3) == 0 and rules.clamp_stacks(9) == 3, "Stacks must clamp to 0 through 3", failures)
    _expect(rules.pair_key(9, 2) == rules.pair_key(2, 9), "Pair keys must be unordered", failures)
    var direct = rules.calculate_attack(Vector3(8, 0, 0), Vector3.ZERO, Vector3.RIGHT, 0, 0)
    _expect(direct.effective, "Fast direct approach must be effective", failures)
    _expect(direct.impulse.dot(Vector3.RIGHT) > 0.0, "Direct impulse must point toward defender", failures)
    var graze = rules.calculate_attack(Vector3(0, 0, 8), Vector3.ZERO, Vector3.RIGHT, 0, 0)
    _expect(not graze.effective, "Tangential motion must not be an effective attack", failures)
    _expect(graze.impulse.is_zero_approx(), "Tangential motion must not create directional knockback", failures)
    var below = rules.calculate_attack(Vector3(1.99, 0, 0), Vector3.ZERO, Vector3.RIGHT, 0, 0)
    _expect(not below.effective, "Approach below 2 m/s must not refresh credit", failures)
    var stationary = rules.calculate_attack(Vector3.ZERO, Vector3(8, 0, 0), Vector3.LEFT, 0, 0)
    _expect(not stationary.effective and stationary.impulse.is_zero_approx(), "A stationary defender must not become the attacker", failures)
    var zero_direction = rules.calculate_attack(Vector3(8, 0, 0), Vector3.ZERO, Vector3.ZERO, 0, 0)
    _expect(not zero_direction.effective and zero_direction.impulse.is_zero_approx(), "Zero direction must be safe", failures)
    var capped = rules.calculate_attack(Vector3(100, 0, 0), Vector3.ZERO, Vector3.RIGHT, 3, 0)
    _expect(capped.impulse.length() <= rules.MAX_KNOCKBACK_SPEED + 0.001, "Knockback must be capped", failures)
    return failures

func _expect(condition: bool, message: String, failures: Array[String]) -> void:
    if not condition:
        failures.append(message)
```

- [ ] **Step 2: Run the rules suite and capture the red state**

Run:

```powershell
$godot = 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
& $godot --headless --path . --script res://tests/bumper/test_bumper_arena.gd -- --scope=rules
```

Expected: exit `1` because the three production rule scripts do not exist. Also run `--scope=typo` and require exit `1`; a zero-test pass is forbidden.

- [ ] **Step 3: Implement the clamped drive command and typed impact result**

`drive_command.gd` must be a `RefCounted` value object:

```gdscript
class_name DriveCommand
extends RefCounted

var throttle: float
var steering: float

static func create(raw_throttle: float, raw_steering: float) -> DriveCommand:
    var command := DriveCommand.new()
    command.throttle = clampf(raw_throttle, -1.0, 1.0)
    command.steering = clampf(raw_steering, -1.0, 1.0)
    return command
```

`impact_result.gd` must expose initialized, typed fields:

```gdscript
class_name ImpactResult
extends RefCounted

var effective := false
var approach_speed := 0.0
var impulse := Vector3.ZERO
```

- [ ] **Step 4: Implement pure impact and multiplier rules**

`bumper_rules.gd` must contain these constants and semantics:

```gdscript
class_name BumperRules
extends RefCounted

const MAX_POWER_STACKS := 3
const EFFECTIVE_ATTACK_SPEED := 2.0
const IMPULSE_PER_MPS := 0.9
const MAX_KNOCKBACK_SPEED := 14.0

static func clamp_stacks(stacks: int) -> int:
    return clampi(stacks, 0, MAX_POWER_STACKS)

static func outgoing_multiplier(stacks: int) -> float:
    return 1.0 + 0.15 * clamp_stacks(stacks)

static func incoming_multiplier(stacks: int) -> float:
    return 1.0 - 0.08 * clamp_stacks(stacks)

static func pair_key(first_id: int, second_id: int) -> String:
    return "%d:%d" % [mini(first_id, second_id), maxi(first_id, second_id)]
```

`calculate_attack` must horizontally normalize `attacker_to_defender`, return a zero result for a zero direction, compute relative closing speed for magnitude, and calculate the attacker's own projected approach speed separately. If the attacker's own approach is zero, return no impulse; otherwise build the impulse from relative closing speed. Require the attacker's own projected speed and relative closing speed to both meet `2.0` for `effective`, multiply by outgoing and incoming stack factors, clamp the final magnitude to `14.0`, and return an impulse pointing from attacker to defender. This one-way calculation is called twice for a bilateral collision, so a stationary defender must not receive attack credit or outgoing impulse merely for being struck.

- [ ] **Step 5: Add vehicle-specific input actions without removing legacy actions yet**

Add physical-key mappings to `project.godot`:

```ini
drive_forward={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":87,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
drive_back={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":83,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
drive_left={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":65,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
drive_right={
"deadzone": 0.5,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":68,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)
]
}
```

Use the same complete serialized `InputEventKey` format already present in the file. Keep the old four `move_*` actions until Task 5 removes the old runtime in one atomic integration slice.

- [ ] **Step 6: Run green rules checks and commit**

Run the rules scope, invalid scope, and editor import. Require `rules` exit `0`, invalid scope exit `1`, and import exit `0`:

```powershell
& $godot --headless --path . --script res://tests/bumper/test_bumper_arena.gd -- --scope=rules
& $godot --headless --path . --script res://tests/bumper/test_bumper_arena.gd -- --scope=typo
& $godot --headless --path . --editor --quit
git diff --check
git add -- project.godot scripts/bumper tests/bumper
git commit -m "feat: add bumper arena rule foundation"
```

Do not stage generated `.uid` files.

---

### Task 2: Reusable Bumper Car, Human Driver, and Camera

**Files:**
- Create: `scripts/drivers/driver_controller.gd`
- Create: `scripts/drivers/human_driver.gd`
- Create: `scripts/vehicles/bumper_car.gd`
- Create: `scripts/camera/player_camera.gd`
- Create: `scenes/vehicles/bumper_car.tscn`
- Create: `scenes/vehicles/player_car.tscn`
- Create: `tests/bumper/suites/test_bumper_car.gd`
- Modify: `tests/bumper/test_bumper_arena.gd`

**Interfaces:**
- Consumes: `DriveCommand` and `BumperRules` from Task 1.
- Produces: `DriverController.get_command(car: BumperCar, delta: float) -> DriveCommand`; `BumperCar.set_driver(driver: DriverController) -> void`; `apply_knockback(impulse: Vector3) -> void`; `set_power_stacks(stacks: int) -> void`; `eliminate() -> bool`; `freeze_for_result() -> void`; `get_combat_velocity() -> Vector3`; `get_snapshot_for_frame(physics_frame: int) -> Vector3`; and `contact_reported(reporter, other, contact_normal, reporter_velocity, physics_frame)`.

- [ ] **Step 1: Add failing vehicle behavior and scene tests**

Extend the runner with `vehicle` and make `all` execute `rules` then `vehicle`. The vehicle suite must load the base and player scenes and assert:

```gdscript
var car_scene := load("res://scenes/vehicles/bumper_car.tscn") as PackedScene
var player_scene := load("res://scenes/vehicles/player_car.tscn") as PackedScene
_expect(car_scene != null and player_scene != null, "Both bumper car scenes must load", failures)
var script = load("res://scripts/vehicles/bumper_car.gd")
_expect(is_equal_approx(script.step_longitudinal_speed(0.0, 1.0, 0.25), 4.5), "Forward acceleration must be 18 m/s squared", failures)
_expect(is_equal_approx(script.step_longitudinal_speed(4.0, -1.0, 0.25), 0.0), "S must brake before reversing", failures)
_expect(is_equal_approx(script.step_longitudinal_speed(0.0, -1.0, 0.25), -4.5), "Reverse must accelerate from rest", failures)
_expect(is_equal_approx(script.step_longitudinal_speed(4.0, 0.0, 0.25), 2.0), "Coasting drag must be 8 m/s squared", failures)
_expect(is_equal_approx(script.steering_rate_for_speed(0.0), deg_to_rad(42.0)), "Low-speed steering must retain 35 percent", failures)
_expect(is_equal_approx(script.steering_rate_for_speed(12.0), deg_to_rad(120.0)), "Full-speed steering must be 120 degrees per second", failures)
```

Instantiate the base car and additionally assert collision layer `2`, collision mask `3`, `apply_knockback(Vector3(100,0,0))` caps at `18 m/s`, power stacks clamp to three, the first `eliminate()` returns true, the second returns false, and elimination disables car collision. Instantiate the player car and assert it contains `HumanDriver`, `CameraYaw/CameraPitch/SpringArm3D/Camera3D`, a current camera, and a `4.5 m` spring arm with collision mask `1`.

- [ ] **Step 2: Run the vehicle scope and capture the red state**

```powershell
& $godot --headless --path . --script res://tests/bumper/test_bumper_arena.gd -- --scope=vehicle
```

Expected: exit `1` because the driver, vehicle scripts, and scenes are missing while the rules scope stays green.

- [ ] **Step 3: Implement the driver contract and human input**

`DriverController` returns a neutral command by default. `HumanDriver` reads the new actions only:

```gdscript
class_name HumanDriver
extends DriverController

func get_command(_car: BumperCar, _delta: float) -> DriveCommand:
    return DriveCommand.create(
        Input.get_axis("drive_back", "drive_forward"),
        Input.get_axis("drive_left", "drive_right")
    )
```

Keep input production separate from car motion; neither driver may write transforms, velocity, power stacks, or alive state.

- [ ] **Step 4: Implement the reusable `CharacterBody3D` car**

Use these exact tuning constants and state boundaries:

```gdscript
class_name BumperCar
extends CharacterBody3D

signal contact_reported(reporter: BumperCar, other: BumperCar, contact_normal: Vector3, reporter_velocity: Vector3, physics_frame: int)

const MAX_FORWARD_SPEED := 12.0
const MAX_REVERSE_SPEED := 5.0
const DRIVE_ACCELERATION := 18.0
const BRAKE_DECELERATION := 24.0
const COAST_DECELERATION := 8.0
const MAX_STEERING_RATE := deg_to_rad(120.0)
const MIN_STEERING_FACTOR := 0.35
const KNOCKBACK_DECAY := 10.0
const MAX_EXTERNAL_SPEED := 18.0
```

The script must:

- expose `@export var stable_id: int`, `@export var body_color: Color`, and `@export var driver_path: NodePath` so assembly and deterministic AI recovery do not infer identity from node names;
- keep signed `longitudinal_speed` separate from horizontal `external_velocity`;
- brake toward zero before S begins reverse acceleration;
- rotate around Y by `-command.steering * steering_rate_for_speed(abs(longitudinal_speed)) * delta`;
- capture horizontal combat velocity and physics-frame number before `move_and_slide()`;
- retain exact combat snapshots for the current and previous physics frame so deferred contact resolution never consumes a different frame's velocity;
- combine forward driving, external knockback, and vertical gravity only once per physics tick;
- emit one contact report for every slide collision whose collider is a live `BumperCar`;
- decay and cap external velocity independently of throttle;
- duplicate the body material before changing per-instance color or emission;
- update a `Label3D` to show `0`, `1`, `2`, or `3` power stacks;
- make `eliminate()` idempotent, disable collision, stop physics, and hide the car;
- make `freeze_for_result()` stop driver input and motion without marking a survivor dead.

- [ ] **Step 5: Create the base and player scenes**

The base scene node contract is:

```text
BumperCar (CharacterBody3D, group bumper_cars, layer 2, mask 3)
├── CollisionShape3D (BoxShape3D size 1.4 × 0.8 × 2.2)
├── Visuals (Node3D)
│   ├── Body (MeshInstance3D using BoxMesh)
│   ├── FrontBumper (MeshInstance3D using BoxMesh)
│   ├── RearBumper (MeshInstance3D using BoxMesh)
│   ├── WheelFL / WheelFR / WheelRL / WheelRR (MeshInstance3D using CylinderMesh)
│   └── PowerLabel (Label3D)
```

The inherited player scene adds `HumanDriver` and this direct spring-arm chain:

```text
PlayerCar
├── HumanDriver
└── CameraYaw
    └── CameraPitch
        └── SpringArm3D (spring_length 4.5, collision_mask 1, margin 0.05)
            └── Camera3D (current true)
```

`player_camera.gd` captures the mouse on ready, excludes the car RID from the spring arm, applies yaw and `-60°/+45°` pitch limits only while captured, releases on non-echo Escape, and recaptures on left click. Preserve the proven Stage 0 input behavior without retaining the old capsule scene.

- [ ] **Step 6: Run vehicle and regression checks and commit**

```powershell
& $godot --headless --path . --script res://tests/bumper/test_bumper_arena.gd -- --scope=vehicle
& $godot --headless --path . --script res://tests/bumper/test_bumper_arena.gd -- --scope=all
& $godot --headless --path . --editor --quit
git diff --check
git add -- scripts/drivers scripts/vehicles scripts/camera scenes/vehicles tests/bumper
git commit -m "feat: add reusable bumper car"
```

Expected: both valid scopes exit `0`, import exits `0`, and no generated `.uid` is staged.

---

### Task 3: Authoritative Match State, Contact Deduplication, Death, and HUD

**Files:**
- Create: `scripts/game/elimination_batch_result.gd`
- Create: `scripts/game/match_state.gd`
- Create: `scripts/game/match_controller.gd`
- Create: `scripts/game/death_zone.gd`
- Create: `scripts/ui/match_hud.gd`
- Create: `scenes/ui/match_hud.tscn`
- Create: `tests/bumper/suites/test_match_controller.gd`
- Modify: `tests/bumper/test_bumper_arena.gd`

**Interfaces:**
- Consumes: `BumperRules`, `ImpactResult`, and `BumperCar`.
- Produces: `MatchState.register_car(stable_id: int, is_player: bool) -> void`; `record_attack(attacker_id: int, victim_id: int, at_time: float) -> void`; `resolve_eliminations(victim_ids: Array[int], at_time: float) -> EliminationBatchResult`; `MatchController.register_car(car: BumperCar, stable_id: int, is_player: bool) -> void`; `report_contact(reporter: BumperCar, other: BumperCar, contact_normal: Vector3, reporter_velocity: Vector3, physics_frame: int) -> void`; `queue_elimination(car: BumperCar, source: StringName = &"death_zone") -> bool`; `get_live_opponents_for(requester: BumperCar) -> Array[BumperCar]`; `request_restart() -> bool`; `advance_match_time(delta: float) -> void`; `MatchHUD.set_alive_count(alive: int, total: int) -> void`; `set_power_stacks(stacks: int) -> void`; `show_result(result: StringName) -> void`; and `request_restart() -> bool`.

- [ ] **Step 1: Add failing state, controller, and HUD tests**

Extend the runner with `match`. The suite must test the pure state first:

```gdscript
var state = MatchState.new()
state.register_car(1, true)
state.register_car(2, false)
state.register_car(3, false)
state.register_car(4, false)
state.record_attack(1, 2, 1.0)
var boundary = state.resolve_eliminations([2], 5.0)
_expect(boundary.killers_by_victim.get(2, -1) == 1, "Exactly four seconds must retain kill credit", failures)
_expect(state.get_power_stacks(1) == 1, "Living killer must gain one stack", failures)
_expect(not state.resolve_eliminations([2], 5.1).accepted_any, "Repeated death must be ignored", failures)
```

Use fresh states to assert age `4.001` gives no killer, three credited kills cap at three stacks, an attacker included in the same death batch receives no usable stack, and `[last_ai_id, player_id]` resolves to `defeat` regardless of array order.

Instantiate a controller with two real cars and assert reversed contact reports at frame `100` create one knockback application, another report at frame `101` applies again, and a tangential contact does not update kill credit. Instantiate the HUD and assert initial text, power text, Chinese victory/defeat copy, and two immediate restart requests emit only once.

- [ ] **Step 2: Run the match scope and capture the red state**

```powershell
& $godot --headless --path . --script res://tests/bumper/test_bumper_arena.gd -- --scope=match
```

Expected: exit `1` because match state, controller, death zone, and HUD do not exist.

- [ ] **Step 3: Implement batch-safe pure match state**

`MatchState` must store stable IDs, player flags, alive flags, power stacks, and last-hit records. `resolve_eliminations` must:

1. deduplicate the supplied IDs;
2. keep only registered, currently alive victims;
3. determine each victim's credited killer using `at_time - hit_time <= 4.0`;
4. mark every accepted victim dead before awarding any power;
5. award one capped stack only to credited killers still alive after the whole batch;
6. return `defeat` if the player is dead, otherwise `victory` only if the player is the sole survivor, otherwise `playing`;
7. return `accepted_any = false` for a batch containing only repeated or unknown IDs.

`EliminationBatchResult` must expose typed fields `accepted_any`, `eliminated_ids`, `killers_by_victim`, `buffed_killer_ids`, and `result: StringName`.

- [ ] **Step 4: Implement deferred contact and death authority**

`MatchController` signals and public methods must be exactly:

```gdscript
signal alive_count_changed(alive: int, total: int)
signal player_power_changed(stacks: int)
signal match_ended(result: StringName)
signal restart_accepted

func register_car(car: BumperCar, stable_id: int, is_player: bool) -> void
func report_contact(reporter: BumperCar, other: BumperCar, contact_normal: Vector3, reporter_velocity: Vector3, physics_frame: int) -> void
func queue_elimination(car: BumperCar, source: StringName = &"death_zone") -> bool
func get_live_opponents_for(requester: BumperCar) -> Array[BumperCar]
func request_restart() -> bool
func advance_match_time(delta: float) -> void
```

`register_car` validates a positive unique stable ID and connects that car's `contact_reported` signal exactly once. For contact resolution, store one entry per `BumperRules.pair_key(stable_a, stable_b)` and physics frame, then defer the flush until all car physics callbacks have completed. At flush time, derive the horizontal A→B direction from car centers; use the reported horizontal contact normal only when the centers coincide. Read both cars' snapshots for that exact frame, calculate A→B and B→A separately, record only effective attacks, and apply each resulting impulse once. `BumperCar` retains snapshots for the current and previous physics frame; if either exact snapshot is still unavailable at deferred flush, discard that pair rather than use order-dependent stale velocity. Clear only the flushed frame so the pair can collide again next frame.

For deaths, queue unique cars by physics frame and defer a batch flush. Also queue any live car below `y = -12.0` as a fallback. Apply the returned batch to car visibility/collision and power stacks, emit the state signals, and freeze all survivors once a result is final. The controller must not reference HUD or the death-zone node directly; Task 5 wires its signals one way through `BumperArena`. Do not emit `restart_accepted` until `request_restart()` accepts the first request.

- [ ] **Step 5: Implement death-zone and one-way HUD adapters**

`death_zone.gd` extends `Area3D`, emits `car_entered_death_zone(car: BumperCar)`, and ignores all other bodies. It never changes car state directly.

`MatchHUD` must provide:

```gdscript
signal restart_requested

func set_alive_count(alive: int, total: int) -> void
func set_power_stacks(stacks: int) -> void
func show_result(result: StringName) -> void
func request_restart() -> bool
```

The scene contains `AliveLabel`, `PowerLabel`, and a hidden centered `ResultPanel` with `ResultLabel` and `RestartButton`. Copy is `剩余车辆：4/4`, `强化：0/3`, `胜利！`, `失败`, and `重新开始`. Button press and Enter both call the same latched `request_restart`; only the first call emits.

- [ ] **Step 6: Run match and full implemented scopes and commit**

```powershell
& $godot --headless --path . --script res://tests/bumper/test_bumper_arena.gd -- --scope=match
& $godot --headless --path . --script res://tests/bumper/test_bumper_arena.gd -- --scope=all
& $godot --headless --path . --editor --quit
git diff --check
git add -- scripts/game scripts/ui scenes/ui tests/bumper
git commit -m "feat: add bumper match rules"
```

Expected: match/rules/vehicle tests and import exit `0` with no leaked `.uid` files staged.

---

### Task 4: Edge-Aware Nearest-Target AI

**Files:**
- Create: `scripts/drivers/ai_driver.gd`
- Create: `scenes/vehicles/ai_car.tscn`
- Create: `tests/bumper/suites/test_ai_driver.gd`
- Modify: `tests/bumper/test_bumper_arena.gd`

**Interfaces:**
- Consumes: `DriverController`, `DriveCommand`, `BumperCar`, and `MatchController.get_live_opponents_for()`.
- Produces: `AIDriver.bind_match(match: MatchController) -> void`; `set_arena_center(center: Vector3) -> void`; `get_command(car: BumperCar, delta: float) -> DriveCommand`; and an inherited `ai_car.tscn` scene with `driver_path` bound to its AI driver.

- [ ] **Step 1: Add failing AI decision tests**

Extend the runner with `ai`. The suite must use real car nodes at controlled positions and assert:

- the nearest of two live opponents becomes the target;
- no opponents returns exactly `DriveCommand.create(0, 0)`;
- an opponent eliminated or freed between frames is never dereferenced and causes safe reselection;
- at radius `9.6` with outward radial velocity, the command steers toward the center even when the target is farther outward;
- at radius `10.9`, emergency recovery overrides pursuit regardless of radial velocity;
- a car at the exact arena center never produces NaN steering;
- sustained commanded throttle with speed below `0.5 m/s` for `1.25 s` enters a `0.75 s` reverse-and-turn recovery, then resets;
- the inherited AI scene loads, has an `AIDriver`, has no current camera, and uses the same `BumperCar` constants as the player.

- [ ] **Step 2: Run the AI scope and capture the red state**

```powershell
& $godot --headless --path . --script res://tests/bumper/test_bumper_arena.gd -- --scope=ai
```

Expected: exit `1` because the AI driver and scene are missing; rules, vehicle, and match remain green.

- [ ] **Step 3: Implement nearest-target pursuit with edge priority**

Use these constants:

```gdscript
const ARENA_RADIUS := 12.0
const SAFE_RADIUS := 9.36
const EMERGENCY_RADIUS := 10.8
const TARGET_LEAD_SECONDS := 0.35
const STUCK_SPEED := 0.5
const STUCK_DELAY := 1.25
const RECOVERY_SECONDS := 0.75
```

Each command call must validate or reselect the nearest live opponent through the bound match controller. Compute pursuit toward `target.global_position + target.get_combat_velocity() * 0.35`. In the outer safe band, if radial velocity is not clearly inward, blend or replace pursuit with the direction to arena center and limit throttle to `0.65`; beyond the emergency radius, always choose center with full forward throttle. Convert the desired horizontal direction to steering using the car's `-basis.z` forward and `basis.x` right vectors. Reduce pursuit throttle when the target is behind rather than reversing during normal pursuit.

Stuck recovery accumulates only while requested throttle exceeds `0.5` and combat speed is below `0.5`; all other conditions reset the timer. Recovery returns full reverse and a stable left/right turn chosen from the car's stable ID, never randomness.

- [ ] **Step 4: Create the inherited AI car scene**

`ai_car.tscn` instances `bumper_car.tscn`, adds one `AIDriver` child, points `driver_path` to it, and does not add a camera. Do not duplicate motion constants or collision code in the scene or driver.

- [ ] **Step 5: Run AI and all implemented scopes and commit**

```powershell
& $godot --headless --path . --script res://tests/bumper/test_bumper_arena.gd -- --scope=ai
& $godot --headless --path . --script res://tests/bumper/test_bumper_arena.gd -- --scope=all
& $godot --headless --path . --editor --quit
git diff --check
git add -- scripts/drivers/ai_driver.gd scenes/vehicles/ai_car.tscn tests/bumper
git commit -m "feat: add bumper car AI"
```

---

### Task 5: Circular Arena Assembly, Legacy Removal, Documentation, and Final Verification

**Files:**
- Create: `scripts/game/bumper_arena.gd`
- Create: `scenes/arena/arena.tscn`
- Create: `tests/bumper/suites/test_bumper_world.gd`
- Create: `tools/verify_bumper_arena.ps1`
- Rewrite: `scenes/main/main.tscn`
- Modify: `project.godot`
- Modify: `.editorconfig`
- Rewrite: `README.md`
- Rewrite: `docs/PROJECT_RULES.md`
- Rewrite: `docs/GAME_DESIGN.md`
- Rewrite: `docs/TODO.md`
- Delete: `scenes/player/player.tscn`
- Delete: `scripts/player/player_controller.gd`
- Delete: `tests/stage0/test_stage0.gd`
- Delete: `tools/verify_stage0.ps1`
- Delete: `docs/superpowers/specs/2026-09-23-stage-0-third-person-movement-design.md`
- Delete: `docs/superpowers/plans/2026-09-23-stage-0-third-person-movement.md`
- Modify: `tests/bumper/test_bumper_arena.gd`

**Interfaces:**
- Consumes: every Task 1–4 interface.
- Produces: a launchable `res://scenes/main/main.tscn`, one player plus three bound AI cars, a `BumperArena` assembly root, complete `world`/`all` native tests, and `tools/verify_bumper_arena.ps1 -Scope all`.

- [ ] **Step 1: Add failing world integration and restart tests**

Extend the runner to final supported scopes `rules`, `vehicle`, `match`, `ai`, `world`, and `all`. Any other scope must exit `1`. The new world suite must load `project.godot` and `main.tscn`, instantiate the scene, and assert:

```gdscript
_expect(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/main/main.tscn", "Main scene path must remain stable", failures)
_expect(main.get_tree().get_nodes_in_group("bumper_cars").size() == 4, "World must contain four bumper cars", failures)
_expect(main.get_node_or_null("MatchController") != null, "World must contain MatchController", failures)
_expect(main.get_node_or_null("Arena/DeathZone") != null, "World must contain a death zone", failures)
_expect(main.get_node_or_null("HUD") != null, "World must contain HUD", failures)
```

Also assert exactly one current camera, one human driver, three AI drivers, unique stable IDs `1–4`, spawn XZ radii close to `6.0`, a `CylinderMesh` with `top_radius = 12.0`, `bottom_radius = 12.0`, and `height = 0.6`, a `CylinderShape3D` with `radius = 12.0` and `height = 0.6`, vehicle layer/masks, initial HUD `4/4` and `0/3`, and preserved renderer/physics settings.

Drive the public controller APIs to queue the last AI and player in the same frame and assert `defeat`. Create a separate scene instance, eliminate all three AI in separate frames, and assert `victory`. Verify the instantiated HUD is connected to the controller's restart path; Task 3 already proves repeated button/Enter requests emit and accept once. Instantiate the packed main scene again and assert it returns to four alive and zero stacks without invoking a real scene reload inside the test runner.

- [ ] **Step 2: Create the new static verifier first and confirm red**

`verify_bumper_arena.ps1` accepts `[ValidateSet("rules", "vehicle", "match", "ai", "world", "docs", "all")]`. It must require the new files and input actions, enforce project name `Bumper Arena`, main scene path, one player/three AI scene instances, circular arena/death zone/HUD/controller presence, Chinese README controls/results/error-reporting, no tracked `.godot`, `.uid`, or `addons`, no `[editor_plugins]`, and absence of the old runtime/test/verifier/spec/plan paths.

It must also search runtime `.gd` and `.tscn` files and fail on legacy gameplay identifiers `Utility`, `Energy`, `Prisoner`, `Chicken`, `PublicGoods`, or old `scripts/player/player_controller.gd` references. Documentation may explain the pivot but must not claim those systems are active.

Create the script with `apply_patch`, then mechanically encode it as UTF-8 with BOM for Windows PowerShell 5.1. Change the final EditorConfig override to:

```ini
[tools/verify_bumper_arena.ps1]
charset = utf-8-bom
```

Run before the migration and require exit `1` with missing arena/world/docs and legacy-file failures:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/verify_bumper_arena.ps1 -Scope all
& $godot --headless --path . --script res://tests/bumper/test_bumper_arena.gd -- --scope=world
```

- [ ] **Step 3: Build the circular arena scene**

`arena.tscn` must have this exact contract:

```text
Arena (Node3D)
├── Platform (StaticBody3D, layer 1, mask 2)
│   ├── MeshInstance3D (CylinderMesh top_radius 12.0, bottom_radius 12.0, height 0.6)
│   └── CollisionShape3D (CylinderShape3D radius 12.0, height 0.6)
├── DeathZone (Area3D at y = -5.0, mask 2)
│   └── CollisionShape3D (BoxShape3D size 32 × 2 × 32)
├── SpawnPlayer (Marker3D at 0, 0.7, 6)
├── SpawnAI1 (Marker3D at 6, 0.7, 0)
├── SpawnAI2 (Marker3D at 0, 0.7, -6)
└── SpawnAI3 (Marker3D at -6, 0.7, 0)
```

Rotate each spawn to face the origin. Use a dark blue-gray platform material, a procedural sky/environment, and one shadow-casting directional light in the main scene. No barriers or invisible edge collision are allowed.

- [ ] **Step 4: Assemble and wire the complete main scene**

`main.tscn` root uses `bumper_arena.gd` and contains `WorldEnvironment`, `DirectionalLight3D`, the arena instance, `MatchController`, HUD instance, one `player_car.tscn`, and three `ai_car.tscn` instances at the four markers. Assign stable IDs `1` for the player and `2–4` for AI, and four high-contrast colors.

`BumperArena._ready()` must connect controller state signals to HUD setters before registering cars, register all cars (which connects each car contact signal internally), bind all AI drivers to the controller and arena center, connect the death-zone signal to `queue_elimination`, connect the HUD restart signal to `request_restart`, and connect `restart_accepted` to its one reload handler. No scene child may independently reload, and the root must not connect a car contact signal a second time.

Update `project.godot` to `config/name="Bumper Arena"`, keep `run/main_scene`, remove all four old `move_*` actions, keep the four `drive_*` actions, and preserve GL Compatibility, D3D12, and Jolt exactly.

- [ ] **Step 5: Remove the obsolete runtime and active design artifacts**

Delete only the six tracked legacy paths listed in this task. Do not touch untracked root `node_3d.tscn`, `addons/`, or `.uid` files. Confirm no new scene or script references a deleted path:

```powershell
rg -n 'scenes/player|scripts/player|tests/stage0|verify_stage0' project.godot scenes scripts tests tools README.md docs
```

Expected: no runtime/document references except Git history, which `rg` does not scan.

- [ ] **Step 6: Rewrite the four active documents**

`README.md` must be Chinese and cover: Bumper Arena purpose; Godot 4.7.2; Windows import/F5; W/S/A/D; mouse/Esc/click recapture; one player versus three AI; fall elimination; four-second credit; three power stacks; victory/defeat/restart; automatic commands; a 6-step manual checklist; and a request for version, reproduction steps, screenshot, plus “输出”和“调试器” text when reporting errors.

`docs/GAME_DESIGN.md` must summarize the approved first-version rules and explicitly list all non-goals. `docs/TODO.md` must mark the original movement foundation and this bumper-arena first version complete only after all checks pass, then leave future polish such as audio, map variants, and additional AI tuning unchecked; it must not restore the old Stage 1–4 game-theory roadmap. `docs/PROJECT_RULES.md` must retain GDScript/built-ins/no-plugin/no-network/English-code/Chinese-copy/honest-verification rules and replace old settlement-specific constraints with vehicle/match separation rules.

- [ ] **Step 7: Run the complete fresh verification matrix**

Run every command and capture exit codes:

```powershell
$godot = 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
powershell -NoProfile -ExecutionPolicy Bypass -File tools/verify_bumper_arena.ps1 -Scope all
& $godot --version
& $godot --headless --path . --script res://tests/bumper/test_bumper_arena.gd -- --scope=all
& $godot --headless --path . --script res://tests/bumper/test_bumper_arena.gd -- --scope=typo
& $godot --headless --path . --editor --quit
& $godot --headless --path . --quit-after 5
git diff --check
git ls-files -- '.godot/*'
git ls-files -- '*.uid'
git ls-files -- 'addons/*'
git status --short --branch
```

Expected: static/all/native/import/startup exit `0`; invalid scope exits `1`; Git checks print no tracked cache, UID, or addon; status contains only intended Task 5 changes plus any explicitly preserved unrelated root items when running outside an isolated worktree. Headless success does not replace manual F5 feel/visual/input acceptance.

- [ ] **Step 8: Commit the complete playable pivot**

Stage only the paths named in this task, inspect the cached file list, and commit:

```powershell
git add -- .editorconfig project.godot README.md docs/PROJECT_RULES.md docs/GAME_DESIGN.md docs/TODO.md docs/superpowers/specs/2026-09-23-stage-0-third-person-movement-design.md docs/superpowers/plans/2026-09-23-stage-0-third-person-movement.md scenes/main/main.tscn scenes/arena scripts/game/bumper_arena.gd tests/bumper tools/verify_bumper_arena.ps1 scenes/player/player.tscn scripts/player/player_controller.gd tests/stage0/test_stage0.gd tools/verify_stage0.ps1
git diff --cached --check
git diff --cached --name-status
git commit -m "feat: build playable bumper arena"
```

After commit, rerun the static `all` scope and native `all` scope, inspect `git status`, and stop. Do not begin any excluded feature or future polish.
