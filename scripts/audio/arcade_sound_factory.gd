class_name ArcadeSoundFactory
extends RefCounted

const SAMPLE_RATE := 22050
static var _impact_streams: Dictionary = {}

static func get_impact_stream(tier: ImpactFeedback.Tier) -> AudioStreamWAV:
	if _impact_streams.has(tier):
		return _impact_streams[tier]
	var duration := 0.15
	var amplitude := 0.18
	var frequency := 105.0
	if tier == ImpactFeedback.Tier.HEAVY:
		duration = 0.22
		amplitude = 0.34
		frequency = 135.0
	elif tier == ImpactFeedback.Tier.SMASH:
		duration = 0.30
		amplitude = 0.55
		frequency = 175.0
	var sample_count := int(duration * SAMPLE_RATE)
	var pcm := PackedByteArray()
	pcm.resize(sample_count * 2)
	var noise := RandomNumberGenerator.new()
	noise.seed = 0x1A2B3C4D + tier * 7919
	for index in sample_count:
		var time := float(index) / SAMPLE_RATE
		var progress := time / duration
		var attack := minf(1.0, time * 350.0)
		var tone := sin(TAU * frequency * time) * exp(-5.0 * progress)
		var transient := noise.randf_range(-1.0, 1.0) * exp(-24.0 * progress)
		var sample := clampf(amplitude * attack * (0.82 * tone + 0.55 * transient), -1.0, 1.0)
		pcm.encode_s16(index * 2, int(round(sample * 32767.0)))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = pcm
	_impact_streams[tier] = stream
	return stream
