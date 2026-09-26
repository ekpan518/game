# Arcade Impact Feedback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add tiered collision, speed, knockout, and power-up feedback that makes the existing single-player bumper-car loop feel fast and satisfying without changing gameplay rules or physics.

**Architecture:** `MatchController` remains authoritative and emits resolved presentation data once per car pair. Pure feedback rules classify intensity; a separate `GameFeelDirector` rate-limits and coordinates pooled effects, procedural audio, camera requests, HUD cues, and safe slow motion. Vehicle, camera, and HUD components render their own local presentation and never recalculate combat outcomes.

**Tech Stack:** Godot 4.7.2, GDScript, GL Compatibility renderer, built-in meshes/materials/particles, runtime-generated `AudioStreamWAV`, existing native SceneTree test harness.

**Spec:** `docs/superpowers/specs/2026-09-26-arcade-impact-feedback-design.md`

## Global Constraints

- Do not change vehicle maximum speeds, steering, knockback formula, AI decisions, match results, kill-credit rules, or arena collision.
- Use Godot built-in nodes, procedural materials, and procedural audio only; add no external assets or plugins.
- Presentation failures must never suppress collision, knockback, elimination, buffs, or match completion.
- Keep GL Compatibility rendering and Godot 4.7.2 support.
- A restart, scene exit, or interrupted slow-motion sequence must leave `Engine.time_scale == 1.0`.
- Existing `rules`, `vehicle`, `match`, `ai`, `world`, and `all` native checks must keep passing.

## Review Focus

- Sustained contact for two seconds: presentation obeys pair cooldown while physics contacts continue; pinned in Task 4 director tests.
- Simultaneous player/last-AI elimination: the existing defeat result remains authoritative and no reward slow motion plays; pinned in Tasks 2 and 4.
- Restart during slow motion: the outgoing and incoming scenes both run at normal time; pinned in Tasks 4 and 7.
- Missing audio device or presentation node: combat and match signals complete without null dereferences; pinned in Tasks 3, 4, and 7.
- Several same-frame impacts: effects stay capped, camera strength is bounded, and no unbounded nodes remain; pinned in Tasks 4 and 7.

---

## File Map

- `scripts/bumper/impact_feedback.gd`: immutable-by-convention data for one resolved car-pair contact.
- `scripts/bumper/impact_feedback_rules.gd`: pure normalization, tier, cooldown, and presentation gating rules.
- `scripts/game/match_controller.gd`: creates authoritative impact/elimination presentation events after normal rule processing.
- `scripts/effects/impact_burst.gd` and `scenes/effects/impact_burst.tscn`: reusable procedural collision visual and positional sound player.
- `scripts/audio/arcade_sound_factory.gd`: creates and caches short procedural impact streams.
- `scripts/game/game_feel_director.gd`: rate limiting, effect pool, cue routing, and slow-motion ownership.
- `scripts/effects/tire_trail.gd`: bounded, fading two-wheel ground traces.
- `scripts/camera/player_camera.gd`: additive camera trauma/FOV feedback and speed-line intensity.
- `scripts/vehicles/bumper_car.gd`: exposes speed/steering presentation state and animates power pulses.
- `scripts/ui/match_hud.gd`: short gameplay cue queue below the persistent counters.
- `scripts/game/bumper_arena.gd` and scene files: explicit assembly and signal wiring.
- `tests/bumper/suites/test_game_feel.gd`: dedicated rules/director/effect/audio tests, exposed as native scope `feel`.

### Task 1: Feedback Data and Pure Classification Rules

**Files:**
- Create: `scripts/bumper/impact_feedback.gd`
- Create: `scripts/bumper/impact_feedback_rules.gd`
- Create: `tests/bumper/suites/test_game_feel.gd`
- Modify: `tests/bumper/test_bumper_arena.gd`
- Modify: `tools/verify_bumper_arena.ps1`

**Interfaces:**
- Produces: `ImpactFeedback.Tier { LIGHT, HEAVY, SMASH }` and fields `stable_a`, `stable_b`, `world_position`, `direction`, `impulse_magnitude`, `normalized_strength`, `tier`, `player_delivered`, `player_received`.
- Produces: `ImpactFeedbackRules.normalized_strength(impulse_magnitude: float) -> float` using `BumperRules.MAX_KNOCKBACK_SPEED`.
- Produces: `tier_for_strength(strength: float) -> ImpactFeedback.Tier`, `cooldown_for_tier(tier: ImpactFeedback.Tier) -> float`, and `should_present(now: float, previous_time: float, previous_strength: float, strength: float, tier: ImpactFeedback.Tier) -> bool`.

- [ ] **Step 1: Add failing pure-rule tests**

  Add `test_game_feel.gd` cases for negative/zero/max/oversized impulse normalization; exact tier boundaries `0.22` and `0.55`; cooldowns `0.16` for light and `0.10` for heavy/smash; and early presentation only when strength improves by at least `0.18`.

- [ ] **Step 2: Register the `feel` scope and verify RED**

  Run: `& $godot --headless --path . --script res://tests/bumper/test_bumper_arena.gd -- --scope=feel`  
  Expected: exit `1` because the feedback scripts do not exist; `--scope=typo` must still exit `1`.

- [ ] **Step 3: Implement the data class and pure rules**

  Keep both scripts free of scene-tree access. Clamp normalized strength to `0.0..1.0`; compare threshold equality into the higher tier; treat a missing previous timestamp as immediately presentable.

- [ ] **Step 4: Verify GREEN and static scope registration**

  Run the native `feel`, native `rules`, and PowerShell `-Scope all` checks; all must exit `0`.

- [ ] **Step 5: Commit**

  Commit: `feat: add impact feedback classification rules`

### Task 2: Authoritative Match Presentation Events

**Files:**
- Modify: `scripts/game/match_controller.gd`
- Modify: `tests/bumper/suites/test_match_controller.gd`
- Modify: `tests/bumper/suites/test_game_feel.gd`

**Interfaces:**
- Consumes: Task 1 `ImpactFeedback` and `ImpactFeedbackRules`.
- Produces: `signal impact_resolved(feedback: ImpactFeedback)` and `signal eliminations_resolved(batch: EliminationBatchResult)`.

- [ ] **Step 1: Add failing controller event tests**

  Assert one `impact_resolved` event per pair/frame despite two reporters; midpoint position and dominant impulse direction; strength derived from the larger applied impulse; player delivered/received flags including mutual effective attacks; and no event for invalid/dead/unregistered cars.

- [ ] **Step 2: Add failing elimination-event regression tests**

  Assert the emitted batch preserves `killers_by_victim`, `buffed_killer_ids`, and defeat precedence for simultaneous player/last-AI death; ordinary match signals and knockback must still fire.

- [ ] **Step 3: Run match and feel scopes to verify RED**

  Expected failures must name missing `impact_resolved` or `eliminations_resolved`, not unrelated setup failures.

- [ ] **Step 4: Emit events after authoritative calculations**

  Construct one `ImpactFeedback` at the end of each accepted pair in `_flush_contacts()`. Emit `eliminations_resolved` after elimination/buff application but before final `match_ended`; do not move or duplicate existing state transitions.

- [ ] **Step 5: Verify match, feel, and all scopes**

  Run native `match`, `feel`, and `all`; each must exit `0`.

- [ ] **Step 6: Commit**

  Commit: `feat: expose resolved match feedback events`

### Task 3: Procedural Impact Visual and Audio Resources

**Files:**
- Create: `scripts/audio/arcade_sound_factory.gd`
- Create: `scripts/effects/impact_burst.gd`
- Create: `scenes/effects/impact_burst.tscn`
- Modify: `tests/bumper/suites/test_game_feel.gd`

**Interfaces:**
- Consumes: Task 1 `ImpactFeedback`.
- Produces: `ArcadeSoundFactory.get_impact_stream(tier: ImpactFeedback.Tier) -> AudioStreamWAV` with cached 22,050 Hz mono streams shorter than `0.40` seconds.
- Produces: `ImpactBurst.play(feedback: ImpactFeedback) -> void`, `reset_for_pool() -> void`, and `signal finished(effect: ImpactBurst)`.

- [ ] **Step 1: Add failing sound and scene tests**

  Assert all tiers return cached, nonempty mono WAV streams with increasing RMS energy; muted audio or the headless dummy driver does not raise an error; the burst scene loads; it contains no `CollisionObject3D`; all `GeometryInstance3D` descendants have shadow casting off; and calling `play()` then `reset_for_pool()` leaves it hidden and inactive.

- [ ] **Step 2: Run feel scope to verify RED**

  Expected: missing factory/effect resources.

- [ ] **Step 3: Implement deterministic procedural sound generation**

  Combine a seeded noise transient and decaying low-frequency sine. Keep tier identity in amplitude/frequency/duration; cache one base stream per tier and leave small playback pitch variation to the director.

- [ ] **Step 4: Build the reusable effect scene**

  Use built-in particles/meshes/materials for sparks and a short expanding ring. Configure by tier and strength, auto-emit `finished`, and make repeated `play/reset` calls safe.

- [ ] **Step 5: Verify feel scope and headless resource loading**

  Run native `feel` and `& $godot --headless --path . --quit-after 5`; both must exit `0` without shader or resource errors.

- [ ] **Step 6: Commit**

  Commit: `feat: add procedural impact effects and audio`

### Task 4: Game Feel Director, Rate Limiting, and Slow Motion

**Files:**
- Create: `scripts/game/game_feel_director.gd`
- Modify: `tests/bumper/suites/test_game_feel.gd`

**Interfaces:**
- Consumes: Task 2 signals and Task 3 effect/sound resources.
- Produces: `bind_match(controller: MatchController, player: BumperCar) -> void`, `reset_presentation() -> void`.
- Produces: signals `camera_feedback_requested(strength: float, delivered: bool, received: bool)` and `hud_cue_requested(text: String, priority: int)`.
- Produces: cue priorities `PRIORITY_HEAVY = 10`, `PRIORITY_POWER = 20`, and `PRIORITY_KNOCKOUT = 30`.

- [ ] **Step 1: Add failing director tests**

  Cover two-second sustained pair contact, `0.18` strength upgrade bypass, pair independence, maximum 16 active effects, null/missing presentation targets, safe rebinding without duplicate signal connections, bounded aggregated camera strength, player-only reward routing, full-stack no false `强化 +1`, and simultaneous-defeat no reward.

- [ ] **Step 2: Add failing slow-motion lifecycle tests**

  A surviving player kill must set `Engine.time_scale` to `0.38` then restore it after `0.24` real seconds. `reset_presentation()`, `_exit_tree()`, repeated kills, and deletion during the tween must each restore exactly `1.0`.

- [ ] **Step 3: Run feel scope to verify RED**

  Expected failures must identify the missing director.

- [ ] **Step 4: Implement presentation coordination**

  Key cooldown state by `BumperRules.pair_key`; pool at most 16 `ImpactBurst` instances; recycle the oldest active instance at capacity; play positional audio through the effect; emit camera/HUD requests without assuming listeners exist.

- [ ] **Step 5: Implement sole ownership of slow motion**

  Use an ignore-time-scale tween/timer for recovery. Always call one idempotent restoration function before restart, rebinding, exit, or starting a replacement slow-motion sequence.

- [ ] **Step 6: Verify feel and all scopes**

  Run native `feel` and `all`; assert the process ends with `Engine.time_scale == 1.0`.

- [ ] **Step 7: Commit**

  Commit: `feat: coordinate arcade game feel feedback`

### Task 5: Additive Player Camera Feedback and Speed Lines

**Files:**
- Modify: `scripts/camera/player_camera.gd`
- Modify: `scenes/vehicles/player_car.tscn`
- Modify: `tests/bumper/suites/test_bumper_car.gd`
- Modify: `tests/bumper/suites/test_game_feel.gd`

**Interfaces:**
- Consumes: Task 4 `camera_feedback_requested`.
- Produces: `apply_impact_feedback(strength: float, delivered: bool, received: bool) -> void`, `set_speed_ratio(ratio: float) -> void`, and `reset_feedback() -> void`.

- [ ] **Step 1: Add failing camera behavior tests**

  Assert light/delivered-only input stays below the shake threshold; received feedback exceeds delivered feedback at the same strength; combined flags use the stronger bounded response; trauma decays to zero; and yaw/pitch/FOV return to their user-controlled baselines.

- [ ] **Step 2: Add failing speed-line structure tests**

  Assert the player scene contains a full-rect, mouse-filter-ignore speed-line overlay on a negative canvas layer; intensity is zero below `0.58` speed ratio, rises smoothly above it, and clamps at one.

- [ ] **Step 3: Run vehicle and feel scopes to verify RED**

- [ ] **Step 4: Implement additive camera feedback**

  Preserve existing mouse input as the baseline transform. Apply deterministic decay plus bounded local noise after input, with a maximum rotational offset of `2.5` degrees and maximum FOV kick of `4.0` degrees.

- [ ] **Step 5: Add the procedural speed-line overlay**

  Drive it from the parent player car's horizontal speed divided by `BumperCar.MAX_FORWARD_SPEED`; hide it on elimination/result and ensure it never consumes input.

- [ ] **Step 6: Verify camera input regressions and all tests**

  Run native `vehicle`, `feel`, `world`, and `all`; all must exit `0`.

- [ ] **Step 7: Commit**

  Commit: `feat: add impact camera and speed feedback`

### Task 6: Bounded Tire Trails and Power Pulses

**Files:**
- Create: `scripts/effects/tire_trail.gd`
- Modify: `scenes/vehicles/bumper_car.tscn`
- Modify: `scripts/vehicles/bumper_car.gd`
- Modify: `tests/bumper/suites/test_bumper_car.gd`
- Modify: `tests/bumper/suites/test_game_feel.gd`

**Interfaces:**
- Produces: `TireTrail.set_trail_state(active: bool, left_world: Vector3, right_world: Vector3, delta: float) -> void` and `clear() -> void`.
- Produces: `BumperCar.play_power_pulse() -> void`; `set_power_stacks()` calls it only when the clamped value actually increases.

- [ ] **Step 1: Add failing vehicle presentation tests**

  Assert two rear-wheel emit points exist; traces begin only while grounded at or above `7.0 m/s`; each side retains at most 48 samples; samples older than `1.2` seconds fade/remove; leaving the ground, elimination, freeze, and clear stop new samples.

- [ ] **Step 2: Add failing power-pulse tests**

  Assert increasing stacks triggers one pulse, equal/decreasing assignments do not, repeated increases replace rather than stack tweens, and the final emission multiplier matches the persistent stack value.

- [ ] **Step 3: Run vehicle and feel scopes to verify RED**

- [ ] **Step 4: Implement bounded procedural trails**

  Render thin, non-shadowing, non-colliding ground ribbons from the two rear emit points. Update only the bounded sample arrays; never create one permanent node per sample.

- [ ] **Step 5: Implement replaceable power pulse**

  Animate only the duplicated per-car body material and restore the existing stack-derived emission after the pulse.

- [ ] **Step 6: Verify vehicle, feel, and all scopes**

- [ ] **Step 7: Commit**

  Commit: `feat: add tire trails and power pulse feedback`

### Task 7: HUD Cues, Scene Assembly, Restart Safety, and Acceptance

**Files:**
- Modify: `scripts/ui/match_hud.gd`
- Modify: `scenes/ui/match_hud.tscn`
- Modify: `scripts/game/bumper_arena.gd`
- Modify: `scenes/main/main.tscn`
- Modify: `tests/bumper/suites/test_bumper_world.gd`
- Modify: `tests/bumper/suites/test_game_feel.gd`
- Modify: `tools/verify_bumper_arena.ps1`
- Modify: `README.md`

**Interfaces:**
- Consumes: Tasks 2, 4, 5, and 6 public signals/methods.
- Produces: `MatchHUD.show_gameplay_cue(text: String, priority: int) -> void` and `clear_gameplay_cues() -> void`.

- [ ] **Step 1: Add failing HUD and integration tests**

  Assert cue priorities are `击落！ = 30`, `强化 +1 = 20`, and `重击！ = 10`; cues expire after `0.85` real seconds without covering persistent counters; result display clears cues and stays above the negative-layer speed overlay; the main scene contains exactly one director; required signals have exactly one connection; missing optional camera/HUD nodes do not block match completion.

- [ ] **Step 2: Add failing restart and burst-load integration tests**

  Start slow motion then request restart and assert the fresh scene has four cars, zero stacks, hidden result/cue UI, no active effects, and `Engine.time_scale == 1.0`. Emit several same-frame impacts and assert at most 16 active effects and bounded camera trauma.

- [ ] **Step 3: Run feel and world scopes to verify RED**

- [ ] **Step 4: Implement HUD cue queue and explicit root wiring**

  `BumperArena` binds the director after registering cars, connects director requests to camera/HUD presentation, and calls `reset_presentation()` before `reload_current_scene()`. The result panel has higher canvas/layer order than speed lines and transient cues; HUD cue expiry ignores game time scale.

- [ ] **Step 5: Extend static verification and README acceptance steps**

  Register every new tracked source/scene in the verifier. Document the `feel` scope and manual checks for the three impact tiers, sustained contact, speed cues, player kill slow motion, full-stack kill, defeat, and immediate restart.

- [ ] **Step 6: Run complete automated verification**

  Run, in order: editor import; Godot version; native `feel`; native `all`; native invalid `typo` expecting nonzero; PowerShell `all`; PowerShell invalid `typo` expecting nonzero; five-frame headless startup; `git diff --check`; tracked cache/UID/addon hygiene.

- [ ] **Step 7: Perform runtime visual acceptance**

  Record representative frames/video at 1152×648. Verify light/heavy/smash readability, no contact spam, visible high-speed trails/lines, player-only reward slow motion, readable HUD, and normal speed after restart. Any failed criterion returns to the owning task and repeats its tests.

- [ ] **Step 8: Commit**

  Commit: `feat: integrate arcade impact feedback`

### Task 8: Whole-Branch Review and Final Verification

**Files:**
- Review all files changed by Tasks 1–7.
- Modify only files required by confirmed review findings.

**Interfaces:**
- Consumes: the complete feature branch.
- Produces: a reviewed, fully verified implementation matching the approved spec.

- [ ] **Step 1: Dispatch a fresh whole-branch reviewer**

  Review against the spec, this plan, the base commit before Task 1, and final branch HEAD. Require explicit Critical/Important/Minor findings and a merge verdict.

- [ ] **Step 2: Fix every Critical and Important finding with RED/GREEN evidence**

  Add or strengthen a regression test first, verify it fails for the reported behavior, implement the fix, then rerun the owning scope.

- [ ] **Step 3: Repeat the complete Task 7 verification sequence**

  Do not claim completion from earlier test output. Capture fresh results after all review fixes.

- [ ] **Step 4: Confirm repository hygiene and intended diff**

  Ensure commits contain only planned files; preserve unrelated user changes and untracked editor-generated files without staging or deleting them.
