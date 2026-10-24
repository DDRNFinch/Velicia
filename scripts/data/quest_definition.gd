class_name QuestDefinition
extends Resource
## A main or side quest made of sequential stages.

@export var id: StringName
@export var title: String = ""
@export_multiline var summary: String = ""
@export var is_main: bool = false
## Draft story content awaiting the author's approval.
@export var is_draft: bool = true
@export var stages: Array[QuestStage] = []

@export_group("Rewards")
@export var reward_xp: int = 0
## item_id -> count
@export var reward_items: Dictionary = {}
@export var reward_flags: PackedStringArray = PackedStringArray()
## faction_id -> amount
@export var reward_reputation: Dictionary = {}
## Quest started automatically when this one completes.
@export var next_quest: StringName
