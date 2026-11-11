class_name QuestStage
extends Resource
## A stage completes when all its objectives are complete.

@export var id: StringName
@export_multiline var journal_text: String = ""
@export var objectives: Array[QuestObjective] = []
