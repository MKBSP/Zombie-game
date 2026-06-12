extends Node

## Autoload singleton holding cross-scene game state.
## Set from the main menu, read by world.gd when the match starts.

enum Role { HUMAN, ZOMBIE }

var role: Role = Role.HUMAN
