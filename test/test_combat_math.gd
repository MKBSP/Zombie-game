extends SceneTree

func _init() -> void:
	var CombatMath = load("res://scripts/combat_math.gd")
	var failed := 0

	# In range, cooldown ready -> can attack
	if CombatMath.can_attack(30.0, 38.0, 0.0) != true:
		push_error("expected true for in-range, ready"); failed += 1
	# In range, cooldown not ready -> cannot
	if CombatMath.can_attack(30.0, 38.0, 0.4) != false:
		push_error("expected false for cooldown remaining"); failed += 1
	# Out of range, cooldown ready -> cannot
	if CombatMath.can_attack(50.0, 38.0, 0.0) != false:
		push_error("expected false for out of range"); failed += 1
	# Exactly at range boundary -> in range (<=)
	if CombatMath.can_attack(38.0, 38.0, 0.0) != true:
		push_error("expected true at boundary"); failed += 1

	if failed == 0:
		print("test_combat_math: PASS")
		quit(0)
	else:
		print("test_combat_math: FAIL (%d)" % failed)
		quit(1)
