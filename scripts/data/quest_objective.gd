class_name QuestObjective
extends Resource
## One trackable objective inside a quest stage.
## target meaning by type:
##   TALK    -> npc id
##   KILL    -> enemy tag or enemy id
##   COLLECT -> item id (counts items held)
##   CAPTURE -> creature id, or "any"
##   REACH   -> location id
##   FLAG    -> flag name that must be set
##   SUMMON  -> creature id, or "any"

enum Type { TALK, KILL, COLLECT, CAPTURE, REACH, FLAG, SUMMON }

@export var type: Type = Type.TALK
@export var target: StringName
@export var count: int = 1
@export var description: String = ""
## Location id used for the map marker / quest compass.
@export var marker_location: StringName
