extends Node
## Original additive synthesis. No downloaded recordings or sample libraries.
var voice: AudioStreamPlayer
var sea: AudioStreamPlayer
var cues: Dictionary = {}

func _ready() -> void:
	voice = AudioStreamPlayer.new()
	voice.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	add_child(voice)
	sea = AudioStreamPlayer.new()
	sea.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	sea.volume_db = -26.0
	add_child(sea)
	var stream: AudioStreamWAV = make_tone([53.0, 79.0, 107.0], 4.0, true)
	sea.stream = stream
	sea.play()

func play_cue(kind: String) -> void:
	if cues.has(kind):
		voice.stream = cues[kind]
		voice.play()
		return
	var tones: Array = [220.0, 330.0]
	var length: float = 0.28
	match kind:
		"win":
			tones = [330.0, 415.3, 494.0, 660.0]
			length = 1.25
		"loss":
			tones = [73.4, 110.0, 116.5]
			length = 0.75
		"undo":
			tones = [196.0, 293.66]
		"wait":
			tones = [146.83]
		"tide":
			tones = [110.0, 164.81, 220.0, 329.63]
			length = 0.85
	voice.stream = make_tone(tones, length)
	cues[kind] = voice.stream
	voice.volume_db = -14.0
	voice.play()

func make_tone(frequencies: Array, seconds: float, loop: bool = false) -> AudioStreamWAV:
	const RATE: int = 22050
	var count: int = int(seconds * RATE)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(count * 2)
	for i in range(count):
		var t: float = float(i) / RATE
		var value: float = 0.0
		for index in range(frequencies.size()):
			var f: float = float(frequencies[index])
			var onset: float = 0.0 if loop else index * minf(0.085, seconds / 8.0)
			var local: float = maxf(0.0, t - onset)
			value += (sin(TAU * f * local) * 0.75 + sin(TAU * f * 2.0 * local) * 0.12) * minf(local * 60.0, 1.0)
		value /= frequencies.size()
		var envelope: float = minf(t * 30.0, 1.0) * exp(-4.0 * t / seconds)
		if loop:
			envelope = 0.35 + 0.25 * sin(TAU * t / seconds)
		var sample: int = clampi(int(value * envelope * 24000.0), -32768, 32767)
		bytes[i * 2] = sample & 255
		bytes[i * 2 + 1] = (sample >> 8) & 255
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = count
	return stream
