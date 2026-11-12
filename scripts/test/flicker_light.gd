extends Light3D
## Gives a static light an unsteady life — Brief 11 night scenes.
##
## Deliberately not a random flicker per frame, which reads as a broken bulb.
## Two slow sines at incommensurate rates drift in and out of phase, so the
## light breathes without ever repeating on an obvious beat, plus a rare, brief
## dip so it is not perfectly regular either.

## Fraction of base energy the shimmer swings by.
@export_range(0.0, 0.8, 0.01) var shimmer: float = 0.14
@export_range(0.1, 10.0, 0.1) var shimmer_speed: float = 1.8
## Chance per second of a short dip, as a failing fixture would.
@export_range(0.0, 3.0, 0.05) var dip_chance: float = 0.25
@export_range(0.0, 0.9, 0.05) var dip_depth: float = 0.45

var _base := 1.0
var _time := 0.0
var _dip := 0.0


func _ready() -> void:
	_base = light_energy
	# Offset so several lights in one scene never breathe in lockstep.
	_time = randf() * 100.0


func _process(delta: float) -> void:
	_time += delta

	if _dip > 0.0:
		_dip = maxf(_dip - delta * 6.0, 0.0)
	elif randf() < dip_chance * delta:
		_dip = 1.0

	var a := sin(_time * shimmer_speed)
	var b := sin(_time * shimmer_speed * 2.31 + 0.9)
	var wave := 1.0 + shimmer * (a * 0.6 + b * 0.4)
	light_energy = _base * wave * (1.0 - dip_depth * _dip)
