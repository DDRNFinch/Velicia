class_name ItemDefinition
extends Resource
## Data definition for any item: weapons, armour, trinkets, consumables,
## materials, creature rings and quest items. Stored in res://data/items.

enum ItemType { WEAPON, ARMOR, TRINKET, CONSUMABLE, MATERIAL, RING, QUEST }

@export var id: StringName
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var type: ItemType = ItemType.MATERIAL
## Placeholder icon colour until icon artwork exists.
@export var icon_color: Color = Color.WHITE
@export var max_stack: int = 99
@export var value: int = 1

@export_group("Weapon")
## Visual/animation family: sword, spear, axe, great_axe, dagger, staff, hookblade, fists.
@export var weapon_kind: StringName = &"sword"
@export var damage: float = 0.0
@export var attack_speed: float = 1.0
@export var stamina_cost_mult: float = 1.0
@export var reach: float = 2.3

@export_group("Armour")
@export var defense: float = 0.0
@export var armor_color: Color = Color(0.45, 0.38, 0.3)

@export_group("Trinket")
@export var bonus_health: float = 0.0
@export var bonus_stamina: float = 0.0

@export_group("Consumable")
@export var heal_amount: float = 0.0
@export var stamina_restore: float = 0.0

@export_group("Ring")
@export var ring_tier: int = 1
@export var capture_power: float = 1.0


func is_equippable() -> bool:
	return type == ItemType.WEAPON or type == ItemType.ARMOR or type == ItemType.TRINKET


func equip_slot() -> String:
	match type:
		ItemType.WEAPON:
			return "weapon"
		ItemType.ARMOR:
			return "armor"
		ItemType.TRINKET:
			return "trinket"
	return ""


func type_name() -> String:
	return ItemType.keys()[type].capitalize()
