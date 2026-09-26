class_name ImpactFeedback
extends RefCounted

enum Tier { LIGHT, HEAVY, SMASH }

var stable_a := 0
var stable_b := 0
var world_position := Vector3.ZERO
var direction := Vector3.ZERO
var impulse_magnitude := 0.0
var normalized_strength := 0.0
var tier: Tier = Tier.LIGHT
var player_delivered := false
var player_received := false
