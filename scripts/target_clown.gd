class_name TargetClown
extends TargetBase
## The main clown target.
##
## In CF37-61 the clown is a thin STATIONARY subclass of TargetBase — it adds
## NO behaviour of its own. This file exists now only so the inherited scene has
## a stable script identity to grow into. Nothing to implement in this story.
##
## CF37-12 fills this in: it overrides `_patrol` to break the metronome and adds
## the de-metronome exports (pause_chance, midpoint_chance, pause_min, pause_max
## — decision D7) and re-values patrol_speed / path_min_x / path_max_x on
## CF37-73 evidence.
