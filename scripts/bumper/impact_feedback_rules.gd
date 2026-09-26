class_name ImpactFeedbackRules
extends RefCounted

static func normalized_strength(impulse_magnitude: float) -> float:
	return clampf(impulse_magnitude / BumperRules.MAX_KNOCKBACK_SPEED, 0.0, 1.0)

static func tier_for_strength(strength: float) -> ImpactFeedback.Tier:
	if strength >= 0.55:
		return ImpactFeedback.Tier.SMASH
	if strength >= 0.22:
		return ImpactFeedback.Tier.HEAVY
	return ImpactFeedback.Tier.LIGHT

static func cooldown_for_tier(tier: ImpactFeedback.Tier) -> float:
	if tier == ImpactFeedback.Tier.LIGHT:
		return 0.16
	return 0.10

static func should_present(now: float, previous_time: float, previous_strength: float, strength: float, tier: ImpactFeedback.Tier) -> bool:
	if previous_time < 0.0:
		return true
	return now - previous_time >= cooldown_for_tier(tier) or strength - previous_strength >= 0.18
