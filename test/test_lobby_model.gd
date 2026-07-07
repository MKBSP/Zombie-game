extends SceneTree

func _init() -> void:
	var LM = load("res://scripts/lobby_model.gd")
	var fail := 0

	# start state
	var s := { "zombie": 0, "shooters": [] as Array }

	# claim zombie
	s = LM.claim(s, 10, 1, 4)  # peer 10 -> ZOMBIE
	if s["zombie"] != 10: push_error("zombie not claimed"); fail += 1

	# claim two shooters
	s = LM.claim(s, 20, 0, 4)  # HUMAN
	s = LM.claim(s, 30, 0, 4)
	if s["shooters"] != [20, 30]: push_error("shooters wrong: %s" % [s["shooters"]]); fail += 1

	# can_start now true
	if not LM.can_start(s): push_error("should be startable"); fail += 1

	# occupied zombie refuses; sender keeps its shooter slot
	var s2: Dictionary = LM.claim(s, 20, 1, 4)
	if s2["zombie"] != 10 or 20 not in s2["shooters"]: push_error("occupied zombie should refuse, keep shooter"); fail += 1

	# shooter 30 switches to zombie after zombie freed
	var s3: Dictionary = LM.remove(s, 10)   # free zombie
	s3 = LM.claim(s3, 30, 1, 4)             # 30 -> ZOMBIE, drops shooter slot
	if s3["zombie"] != 30 or 30 in s3["shooters"]: push_error("switch to zombie failed"); fail += 1

	# capacity: 5th shooter refused
	var s4 := { "zombie": 1, "shooters": [2, 3, 4, 5] as Array }
	s4 = LM.claim(s4, 6, 0, 4)
	if s4["shooters"].size() != 4: push_error("5th shooter should be refused"); fail += 1

	# can_start false without zombie / without shooters
	if LM.can_start({ "zombie": 0, "shooters": [2] as Array }): push_error("no zombie -> not startable"); fail += 1
	if LM.can_start({ "zombie": 1, "shooters": [] as Array }): push_error("no shooters -> not startable"); fail += 1

	# duplicate claim is idempotent
	var s5: Dictionary = LM.claim({ "zombie": 0, "shooters": [7] as Array }, 7, 0, 4)
	if s5["shooters"] != [7]: push_error("duplicate shooter claim should be idempotent"); fail += 1

	if fail == 0: print("test_lobby_model: OK")
	quit(fail)
