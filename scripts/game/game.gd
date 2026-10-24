extends Node3D
## Gameplay scene controller: loads the region, spawns the player and camera,
## wires up the HUD and menu, restores saved position and handles respawning.

const REGIONS := {
	"hollow_march": "res://scenes/regions/hollow_march.tscn",
}

var region: Node3D
var player: Player
var camera_rig: CameraRig
var hud: HUD
var menu: PauseMenu


func _ready() -> void:
	GameState.session_active = true
	var path: String = REGIONS.get(GameState.region, REGIONS.hollow_march)
	region = (load(path) as PackedScene).instantiate()
	add_child(region)

	player = (load("res://scenes/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	camera_rig = CameraRig.new()
	add_child(camera_rig)
	player.camera_rig = camera_rig

	if GameState.has_saved_position:
		player.global_position = GameState.saved_position + Vector3.UP * 0.3
		player.rotation.y = GameState.saved_yaw
	else:
		var spawn := region.get_node_or_null("PlayerSpawn") as Node3D
		if spawn:
			player.global_position = spawn.global_position + Vector3.UP * 0.3
			player.rotation.y = spawn.rotation.y
	camera_rig.set_target(player)

	hud = HUD.new()
	add_child(hud)
	hud.setup(player, self)
	menu = PauseMenu.new()
	menu.player = player
	menu.game = self
	add_child(menu)
	hud.menu_requested.connect(open_menu)

	Settings.changed.connect(_on_settings_changed)
	AudioManager.play_music("exploration")
	AudioManager.play_ambient("wind")
	if not GameState.has_saved_position:
		EventBus.notify.emit("The Emoria Watch Outpost, %s." % region.get("region_name"))
	GameState.has_saved_position = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not menu.is_open() and not hud.is_blocking_ui():
		open_menu("inventory")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("open_inventory") and not menu.is_open() and not hud.is_blocking_ui():
		open_menu("inventory")
	elif event.is_action_pressed("open_map") and not menu.is_open() and not hud.is_blocking_ui():
		open_menu("map")
	elif event is InputEventMouseButton and event.pressed and not Settings.touch_controls_enabled():
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not menu.is_open() and not hud.is_blocking_ui():
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _process(_delta: float) -> void:
	var want_free := menu.is_open() or hud.is_blocking_ui()
	if want_free and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func open_menu(tab: String) -> void:
	hud.touch.release_all()
	menu.open(tab)


func respawn_player() -> void:
	var shrine := find_shrine(GameState.respawn_point)
	var pos := shrine.spawn_position() if shrine else (region.get_node("PlayerSpawn") as Node3D).global_position
	if player.rings.companion:
		player.rings.dismiss(true)
	GameState.restore_all_creatures()
	player.respawn_at(pos, shrine.rotation.y if shrine else 0.0)


func find_shrine(id: String) -> SaveShrine:
	for s in get_tree().get_nodes_in_group("shrines"):
		if (s as SaveShrine).shrine_id == id:
			return s
	return null


func _on_settings_changed(section: String, key: String) -> void:
	if section == "graphics" and key == "render_scale":
		get_viewport().scaling_3d_scale = float(Settings.get_value("graphics", "render_scale"))
