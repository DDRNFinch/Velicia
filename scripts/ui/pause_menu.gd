class_name PauseMenu
extends CanvasLayer
## The in-game menu (pauses the game): inventory and equipment, creatures and
## rings, character progression, quest journal and lore, region map,
## settings and save/load.

signal closed

var player: Player
var game: Node

var _bg: ColorRect
var _tabs: TabContainer
var _pages: Dictionary = {}
var _status: Label
var _selected_item: String = ""
var _selected_creature: int = -1
var _map: MapView

const TAB_ORDER := ["inventory", "creatures", "character", "journal", "map", "settings", "system"]
const TAB_NAMES := {
	"inventory": "Inventory", "creatures": "Rings", "character": "Character",
	"journal": "Journal", "map": "Map", "settings": "Settings", "system": "Game",
}


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_bg = ColorRect.new()
	_bg.color = Color(0.02, 0.03, 0.05, 0.82)
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.theme = UiTheme.get_theme()
	add_child(_bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28 if side != "top" else 18)
	_bg.add_child(margin)
	var v := VBoxContainer.new()
	margin.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var t := UiTheme.title("VELICIA")
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	_status = UiTheme.label("", 18, UiTheme.TEXT_DIM)
	top.add_child(_status)
	top.add_child(UiTheme.button("Resume ✕", close, 150))
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_tabs)
	for id in TAB_ORDER:
		var page: Control
		if id == "settings":
			page = SettingsPanel.new()
		elif id == "map":
			page = VBoxContainer.new()
		else:
			var scroll := ScrollContainer.new()
			scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			page = scroll
		page.name = TAB_NAMES[id]
		_tabs.add_child(page)
		_pages[id] = page
	_tabs.tab_changed.connect(func(_i): _refresh_current())


func open(tab: String = "inventory") -> void:
	visible = true
	get_tree().paused = true
	var idx := TAB_ORDER.find(tab)
	_tabs.current_tab = maxi(idx, 0)
	_refresh_current()
	AudioManager.play_ui()


func close() -> void:
	visible = false
	get_tree().paused = false
	GameState.remove_meta("at_shrine")
	closed.emit()


func is_open() -> bool:
	return visible


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()


func _refresh_current() -> void:
	var id: String = TAB_ORDER[_tabs.current_tab]
	_status.text = "Lv %d · %s played" % [GameState.get_level(), _fmt_time(GameState.play_time)]
	match id:
		"inventory":
			_build_inventory()
		"creatures":
			_build_creatures()
		"character":
			_build_character()
		"journal":
			_build_journal()
		"map":
			_build_map()
		"system":
			_build_system()


func _clear(page: Control) -> VBoxContainer:
	for c in page.get_children():
		page.remove_child(c)
		c.queue_free()
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_child(v)
	return v


func _columns(parent: Control) -> Array:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 24)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(h)
	var a := VBoxContainer.new()
	a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b := VBoxContainer.new()
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(a)
	h.add_child(b)
	return [a, b]


func _wrap(text: String, size: int = 19, color: Color = UiTheme.TEXT) -> Label:
	var l := UiTheme.label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(360, 0)
	return l


# -------------------------------------------------------------- Inventory

func _build_inventory() -> void:
	var v := _clear(_pages.inventory)
	var cols := _columns(v)
	var left: VBoxContainer = cols[0]
	var right: VBoxContainer = cols[1]
	left.add_child(UiTheme.label("Equipment", 24, UiTheme.GOLD))
	for slot in ["weapon", "armor", "trinket"]:
		var id: String = GameState.equipment.get(slot, "")
		var def := Database.item(id)
		var row := HBoxContainer.new()
		var l := UiTheme.label("%s: %s" % [slot.capitalize(), def.display_name if def else "—"], 20)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		if def:
			var s: String = slot
			row.add_child(UiTheme.button("Unequip", func():
				GameState.unequip(s)
				_build_inventory(), 130))
		left.add_child(row)
	left.add_child(UiTheme.label("Damage %d · Defence %d · Health %d · Stamina %d" % [GameState.get_weapon_damage(), GameState.get_defense(), GameState.get_max_health(), GameState.get_max_stamina()], 17, UiTheme.TEXT_DIM))
	left.add_child(UiTheme.label("Items", 24, UiTheme.GOLD))
	var ids := GameState.inventory.keys()
	ids.sort()
	if ids.is_empty():
		left.add_child(UiTheme.label("Your pack is empty.", 18, UiTheme.TEXT_DIM))
	for id in ids:
		var def := Database.item(id)
		if def == null:
			continue
		var item_id: String = id
		var b := UiTheme.button("%s  ×%d   (%s)" % [def.display_name, GameState.count_item(id), def.type_name()], func():
			_selected_item = item_id
			_build_inventory())
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if id == _selected_item:
			b.add_theme_stylebox_override("normal", UiTheme.button_style(Color(0.24, 0.2, 0.12), UiTheme.GOLD))
		left.add_child(b)
	var sel := Database.item(_selected_item)
	if sel and GameState.count_item(_selected_item) > 0:
		right.add_child(UiTheme.label(sel.display_name, 26, sel.icon_color.lightened(0.2)))
		right.add_child(_wrap(sel.description))
		var stats := ""
		match sel.type:
			ItemDefinition.ItemType.WEAPON:
				stats = "Damage %d · Speed %.2f · Reach %.1f m" % [sel.damage, sel.attack_speed, sel.reach]
			ItemDefinition.ItemType.ARMOR:
				stats = "Defence %d" % sel.defense
			ItemDefinition.ItemType.TRINKET:
				stats = "+%d health · +%d stamina" % [sel.bonus_health, sel.bonus_stamina]
			ItemDefinition.ItemType.CONSUMABLE:
				stats = "Restores %d health, %d stamina" % [sel.heal_amount, sel.stamina_restore]
			ItemDefinition.ItemType.RING:
				stats = "Ring tier %d · Capture power ×%.2f" % [sel.ring_tier, sel.capture_power]
		if not stats.is_empty():
			right.add_child(UiTheme.label(stats, 18, UiTheme.TEXT_DIM))
		if sel.is_equippable():
			right.add_child(UiTheme.button("Equip", func():
				GameState.equip_item(_selected_item)
				_build_inventory()))
		elif sel.type == ItemDefinition.ItemType.CONSUMABLE:
			right.add_child(UiTheme.button("Use", func():
				GameState.use_consumable(_selected_item, player)
				_build_inventory()))
		elif sel.type == ItemDefinition.ItemType.RING:
			var b := UiTheme.button("Wear ring (%d/%d worn)" % [GameState.ring_slots.size(), GameState.MAX_RING_SLOTS], func():
				if GameState.equip_ring(_selected_item):
					EventBus.notify.emit("You slip on the %s." % Database.item(_selected_item).display_name)
				_build_inventory())
			b.disabled = GameState.ring_slots.size() >= GameState.MAX_RING_SLOTS
			right.add_child(b)
	else:
		right.add_child(_wrap("Select an item to inspect it.", 18, UiTheme.TEXT_DIM))


# -------------------------------------------------------------- Creatures

func _build_creatures() -> void:
	var v := _clear(_pages.creatures)
	var at_shrine: bool = GameState.has_meta("at_shrine")
	var cols := _columns(v)
	var left: VBoxContainer = cols[0]
	var right: VBoxContainer = cols[1]
	left.add_child(UiTheme.label("Worn rings", 24, UiTheme.GOLD))
	if GameState.ring_slots.is_empty():
		left.add_child(_wrap("You wear no rings.", 18, UiTheme.TEXT_DIM))
	for i in GameState.ring_slots.size():
		var ring := GameState.ring_definition(i)
		var inst := GameState.creature_in_slot(i)
		var label := "%s%s — %s" % ["▶ " if i == GameState.active_ring else "", ring.display_name if ring else "Ring", inst.display_name() + " (Lv %d)" % inst.level if inst else "empty"]
		var slot := i
		var b := UiTheme.button(label, func():
			GameState.active_ring = slot
			if GameState.creature_in_slot(slot):
				_selected_creature = GameState.creature_in_slot(slot).uid
			EventBus.creatures_changed.emit()
			_build_creatures())
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		left.add_child(b)
	left.add_child(UiTheme.label("Guild vault", 24, UiTheme.GOLD))
	var any_vault := false
	for c in GameState.creatures:
		if c.ring_slot < 0:
			any_vault = true
			var uid: int = c.uid
			var b := UiTheme.button("%s (Lv %d)" % [c.display_name(), c.level], func():
				_selected_creature = uid
				_build_creatures())
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			left.add_child(b)
	if not any_vault:
		left.add_child(_wrap("No creatures resting in the vault.", 18, UiTheme.TEXT_DIM))
	left.add_child(_wrap("Weaken a wild creature below its capture threshold, then use CAPTURE with an empty ring." + ("" if at_shrine else " Swap creatures between rings and the vault at a Ring Stone."), 16, UiTheme.TEXT_DIM))

	var sel := GameState.find_creature(_selected_creature)
	if sel == null:
		sel = GameState.creature_in_slot(GameState.active_ring)
	if sel == null:
		right.add_child(_wrap("No creature selected.", 18, UiTheme.TEXT_DIM))
		return
	var def := sel.definition()
	right.add_child(UiTheme.label(sel.display_name(), 28, def.accent_color.lightened(0.2)))
	if def.is_placeholder:
		right.add_child(UiTheme.label("TEMPORARY TEST CREATURE — awaiting the official roster", 15, Color(1, 0.6, 0.3)))
	right.add_child(_wrap(def.description, 18))
	right.add_child(UiTheme.label("%s · %s temperament" % [def.rarity_name(), def.temperament_name()], 18, UiTheme.TEXT_DIM))
	right.add_child(UiTheme.label("Level %d   XP %d / %d" % [sel.level, sel.xp, sel.xp_to_next()], 20))
	var xpbar := UiTheme.make_bar(UiTheme.GOLD, 320, 10)
	xpbar.value = 100.0 * sel.xp / maxf(sel.xp_to_next(), 1)
	right.add_child(xpbar)
	right.add_child(UiTheme.label("Bond level %d" % sel.bond_level(), 20, UiTheme.RING))
	var bondbar := UiTheme.make_bar(UiTheme.RING, 320, 10)
	bondbar.value = sel.bond_progress() * 100.0
	right.add_child(bondbar)
	var status := "Exhausted — resting (%ds)" % ceili(sel.exhausted_until - GameState.play_time) if sel.is_exhausted() else "Ready"
	right.add_child(UiTheme.label("Health %d / %d · Attack %.1f · Defence %.1f · %s" % [sel.health, sel.max_health(), sel.attack(), sel.defense(), status], 17, UiTheme.TEXT_DIM))
	right.add_child(UiTheme.label("Abilities", 22, UiTheme.GOLD))
	for a in def.abilities:
		var unlocked: bool = a.required_level <= sel.level and a.required_bond <= sel.bond_level()
		var req := "" if unlocked else "  (needs Lv %d, bond %d)" % [a.required_level, a.required_bond]
		right.add_child(_wrap(("✓ " if unlocked else "✗ ") + a.display_name + " — " + a.description + req, 17, UiTheme.TEXT if unlocked else UiTheme.TEXT_DIM))
	if at_shrine:
		if sel.ring_slot >= 0:
			right.add_child(UiTheme.button("Send to vault", func():
				if player.rings.companion and player.rings.companion.instance == sel:
					player.rings.dismiss(true)
				GameState.move_creature(sel.uid, -1)
				_build_creatures()))
		else:
			var empty := GameState.first_empty_ring(1)
			var b := UiTheme.button("Bind to an empty ring", func():
				GameState.move_creature(sel.uid, GameState.first_empty_ring(1))
				_build_creatures())
			b.disabled = empty < 0
			right.add_child(b)


# -------------------------------------------------------------- Character

func _build_character() -> void:
	var v := _clear(_pages.character)
	var cols := _columns(v)
	var left: VBoxContainer = cols[0]
	var right: VBoxContainer = cols[1]
	left.add_child(UiTheme.label("Warrior of the Emoria Guild", 24, UiTheme.GOLD))
	left.add_child(UiTheme.label("Level %d" % GameState.get_level(), 22))
	var xpbar := UiTheme.make_bar(UiTheme.GOLD, 360, 12)
	xpbar.value = 100.0 * int(GameState.player.xp) / maxf(GameState.xp_to_next(), 1)
	left.add_child(xpbar)
	left.add_child(UiTheme.label("XP %d / %d" % [int(GameState.player.xp), GameState.xp_to_next()], 17, UiTheme.TEXT_DIM))
	left.add_child(UiTheme.label("Attribute points: %d" % int(GameState.player.stat_points), 20, UiTheme.RING))
	for attr in GameState.ATTRIBUTE_NAMES:
		var row := HBoxContainer.new()
		var l := UiTheme.label("%s: %d" % [GameState.ATTRIBUTE_NAMES[attr], GameState.attribute(attr)], 19)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var a: String = attr
		var b := UiTheme.button("+", func():
			GameState.spend_stat_point(a)
			_build_character(), 64)
		b.disabled = int(GameState.player.stat_points) <= 0
		row.add_child(b)
		left.add_child(row)
	left.add_child(UiTheme.label("Health %d · Stamina %d · Damage %d · Defence %d" % [GameState.get_max_health(), GameState.get_max_stamina(), GameState.get_weapon_damage(), GameState.get_defense()], 17, UiTheme.TEXT_DIM))
	left.add_child(UiTheme.label("Reputation", 22, UiTheme.GOLD))
	for f in GameState.reputation:
		left.add_child(UiTheme.label("%s: %d" % [GameState.faction_name(f).capitalize(), int(GameState.reputation[f])], 18))
	right.add_child(UiTheme.label("Guild arts", 24, UiTheme.GOLD))
	var abilities := Database.abilities.values()
	abilities.sort_custom(func(a, b): return a.unlock_level < b.unlock_level)
	for ab in abilities:
		var unlocked: bool = GameState.get_level() >= ab.unlock_level
		var kind := "Active" if ab.kind == AbilityDefinition.Kind.ACTIVE else "Passive"
		right.add_child(_wrap("%s %s (%s, Lv %d)\n%s" % ["✓" if unlocked else "✗", ab.display_name, kind, ab.unlock_level, ab.description], 17, UiTheme.TEXT if unlocked else UiTheme.TEXT_DIM))
		if ab.kind == AbilityDefinition.Kind.ACTIVE and unlocked:
			var equipped := String(GameState.player.get("equipped_skill", "")) == String(ab.id)
			var id := String(ab.id)
			var b := UiTheme.button("Equipped" if equipped else "Equip as skill", func():
				GameState.player.equipped_skill = id
				_build_character())
			b.disabled = equipped
			right.add_child(b)


# ---------------------------------------------------------------- Journal

func _build_journal() -> void:
	var v := _clear(_pages.journal)
	var cols := _columns(v)
	var left: VBoxContainer = cols[0]
	var right: VBoxContainer = cols[1]
	left.add_child(UiTheme.label("Active quests", 24, UiTheme.GOLD))
	var active := QuestManager.active_quests()
	if active.is_empty():
		left.add_child(_wrap("No active quests.", 18, UiTheme.TEXT_DIM))
	for q in active:
		var tracked := String(q.id) == GameState.tracked_quest
		left.add_child(UiTheme.label(("◆ " if q.is_main else "◇ ") + q.title + ("  (tracked)" if tracked else ""), 21, UiTheme.GOLD if tracked else UiTheme.TEXT))
		var stage := QuestManager.current_stage(q.id)
		if stage:
			left.add_child(_wrap(stage.journal_text, 17, UiTheme.TEXT_DIM))
		left.add_child(_wrap("\n".join(QuestManager.objective_lines(q.id)), 17))
		if not tracked:
			var id := String(q.id)
			left.add_child(UiTheme.button("Track", func():
				GameState.tracked_quest = id
				EventBus.quest_updated.emit(StringName(id))
				_build_journal(), 140))
		if q.is_draft:
			left.add_child(UiTheme.label("Draft story content", 14, Color(0.65, 0.6, 0.5)))
	var done := QuestManager.completed_quests()
	if not done.is_empty():
		left.add_child(UiTheme.label("Completed", 22, UiTheme.GOLD))
		for q in done:
			left.add_child(UiTheme.label("✓ " + q.title, 18, UiTheme.TEXT_DIM))
	right.add_child(UiTheme.label("Lore", 24, UiTheme.GOLD))
	if GameState.lore.is_empty():
		right.add_child(_wrap("Read inscriptions and relics to fill your journal.", 18, UiTheme.TEXT_DIM))
	for id in GameState.lore:
		var e := Database.lore_entry(id)
		right.add_child(UiTheme.label(String(e.get("title", id)), 20, UiTheme.GOLD.lightened(0.2)))
		right.add_child(_wrap(String(e.get("text", "")), 17))
	right.add_child(UiTheme.label("Discovered places: %d" % GameState.discovered.size(), 18, UiTheme.TEXT_DIM))


# -------------------------------------------------------------------- Map

func _build_map() -> void:
	var page: VBoxContainer = _pages.map
	for c in page.get_children():
		page.remove_child(c)
		c.queue_free()
	_map = MapView.new()
	_map.player = player
	page.add_child(_map)


# ----------------------------------------------------------------- System

func _build_system() -> void:
	var v := _clear(_pages.system)
	v.add_child(UiTheme.label("Save and load", 24, UiTheme.GOLD))
	var summary := SaveManager.read_summary()
	if summary.is_empty():
		v.add_child(_wrap("No saved game yet.", 18, UiTheme.TEXT_DIM))
	else:
		v.add_child(_wrap("Last save: %s · Level %d" % [String(summary.get("saved_at", "")).replace("T", " "), int(summary.get("level", 1))], 18, UiTheme.TEXT_DIM))
	var save_b := UiTheme.button("Save game", func():
		if CombatDirector.in_combat():
			EventBus.notify.emit("You cannot save during combat.")
		elif SaveManager.save_game():
			EventBus.notify.emit("Game saved.")
		else:
			EventBus.notify.emit("Save failed: " + SaveManager.last_error)
		_build_system(), 320)
	v.add_child(save_b)
	if CombatDirector.in_combat():
		v.add_child(UiTheme.label("Saving is unavailable during combat.", 16, UiTheme.DANGER))
	var load_b := UiTheme.button("Load last save", func():
		close()
		GameState.continue_game(), 320)
	load_b.disabled = not SaveManager.has_save()
	v.add_child(load_b)
	v.add_child(UiTheme.label("", 10))
	v.add_child(UiTheme.button("Quit to main menu", func():
		close()
		GameState.quit_to_menu(), 320))
	v.add_child(_wrap("Progress is saved when you rest at a Ring Stone or choose Save game. Unsaved progress is lost when you quit.", 16, UiTheme.TEXT_DIM))


static func _fmt_time(t: float) -> String:
	var m := int(t / 60.0)
	return "%dh %02dm" % [m / 60, m % 60]
