extends Node

## Autoload singleton holding cross-scene game state.
## Set from the main menu, read by world.gd when the match starts.

enum Role { HUMAN, ZOMBIE }

var role: Role = Role.HUMAN

## True while a multiplayer session (host or client) is active.
var multiplayer_active: bool = false

## True only on the dedicated headless server (launched with --server). The
## server runs the authoritative simulation but is not a player, so it skips all
## camera / HUD / fog / input setup.
var is_dedicated_server: bool = false

## RNG seed shared by both peers so scenery (props) matches visually.
var world_seed: int = 0
