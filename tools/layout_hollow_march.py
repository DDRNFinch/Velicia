# Regenerates scenes/regions/hollow_march.tscn from the layout tables below.
# Usage: python3 tools/layout_hollow_march.py scenes/regions/hollow_march.tscn
# (Optional: you can also edit the .tscn directly in the Godot editor; if you
#  do, stop using this script or copy your changes back into the tables.)
# Emits scenes/regions/hollow_march.tscn from a readable layout table.
import sys
out = []
ext = {}
def ext_res(kind, path):
    if path not in ext:
        ext[path] = (kind, "%d_r" % (len(ext) + 1))
    return 'ExtResource("%s")' % ext[path][1]

S = {k: ext_res("Script", "res://scripts/%s.gd" % v) for k, v in {
    "builder": "world/region_builder", "loc": "world/location_trigger", "shrine": "world/save_shrine",
    "npc": "world/npc", "enemy": "enemies/enemy", "spawner": "world/creature_spawner", "chest": "world/chest",
    "lore": "world/lore_stone", "pickup": "world/loot_pickup", "arena": "world/boss_arena"}.items()}
def enemy(id): return ext_res("Resource", "res://data/enemies/%s.tres" % id)
def creature(id): return ext_res("Resource", "res://data/creatures/%s.tres" % id)

def tf(x, z, y=0.0, rot=0.0):
    import math
    c, s = math.cos(rot), math.sin(rot)
    return "Transform3D(%g, 0, %g, 0, 1, 0, %g, 0, %g, %g, %g, %g)" % (c, -s, s, c, x, y, z)

nodes = []
def node(name, typ, parent, props):
    nodes.append((name, typ, parent, props))

def gd(v):
    if isinstance(v, bool): return "true" if v else "false"
    if isinstance(v, str) and (v.startswith("ExtResource") or v.startswith("Transform3D") or v.startswith("PackedVector3Array") or v.startswith("NodePath") or v.startswith("&") or v.startswith("{") or v.startswith("Color") or v.startswith("Array[")): return v
    if isinstance(v, str): return '"%s"' % v
    return str(v)

node("HollowMarch", "Node3D", None, {"script": S["builder"], "region_id": "hollow_march", "region_name": "The Hollow March", "terrain_seed": 1337,
    "paths": 'Array[PackedStringArray]([PackedStringArray("emoria_outpost", "sentinel_spire"), PackedStringArray("emoria_outpost", "ashfen_camp"), PackedStringArray("sentinel_spire", "broken_fort"), PackedStringArray("emoria_outpost", "mossglade"), PackedStringArray("emoria_outpost", "old_battlefield"), PackedStringArray("mossglade", "glassmere_shallows")])',
    "lakes": "Array[Vector4]([Vector4(-40, 95, 20, -4)])",
    "forests": "Array[Vector4]([Vector4(-95, -30, 70, 0.55), Vector4(-30, -95, 40, 0.3), Vector4(125, -60, 40, 0.3)])"})
node("PlayerSpawn", "Marker3D", ".", {"transform": tf(0, 9)})

node("Locations", "Node3D", ".", {})
locs = [
 # id, name, x, z, radius, flat_r, flat_h, structure, icon
 ("emoria_outpost", "Emoria Watch Outpost", 0, 0, 24, 22, 4, "outpost", "settlement"),
 ("sentinel_spire", "The Sentinel Spire", 35, -75, 22, 16, 6, "spire", "ruin"),
 ("ashfen_camp", "Ashfen Camp", 95, 5, 20, 16, 3, "gyria_camp", "camp"),
 ("broken_fort", "The Broken Fort", 25, -135, 24, 22, 8, "fort", "fort"),
 ("mossglade", "Mossglade", -75, 40, 18, 12, 2, "glade", "wild"),
 ("glassmere_shallows", "Glassmere Stones", -58, 80, 14, 8, 0, "lake_ruin", "lake"),
 ("hidden_hollow", "The Hidden Hollow", -120, -110, 8, 9, 9, "grotto", "cave"),
 ("old_battlefield", "The Old Battlefield", 75, 85, 22, 0, 0, "battlefield", "ruin"),
 ("whisperpine_wood", "Whisperpine Wood", -95, -30, 32, 0, 0, "", "wild"),
]
for (lid, name, x, z, r, fr, fh, st, icon) in locs:
    p = {"transform": tf(x, z), "script": S["loc"], "location_id": lid, "display_name": name, "radius": float(r), "map_icon": icon}
    if fr: p.update({"flatten_radius": float(fr), "flatten_height": float(fh)})
    if lid == "hidden_hollow": p["flatten_falloff"] = 10.0
    if st: p["structure"] = st
    node(name.replace(" ", "").replace("The", ""), "Area3D", "Locations", p)

node("Shrines", "Node3D", ".", {})
for sid, name, x, z, rot in [("outpost_shrine", "Outpost Ring Stone", -7, -5, 0.6), ("spire_shrine", "Spire Ring Stone", 24, -63, 0.3), ("fort_shrine", "Fort Road Ring Stone", 12, -108, 0.0)]:
    node(sid, "Node3D", "Shrines", {"transform": tf(x, z, rot=rot), "script": S["shrine"], "shrine_id": sid, "display_name": name})

node("NPCs", "Node3D", ".", {})
npcs = [
 ("Warden", "warden", "Warden Aldren", "human", 0, "warden", 3, -3, "PackedVector3Array(0, 0, 0, 2, 0, 2)", {"cloth_color": "Color(0.22, 0.28, 0.45, 1)"}),
 ("RingSage", "ring_sage", "Master Oddrin", "gouran", 1, "ring_sage", -5, 4, "PackedVector3Array(0, 0, 0, -2, 0, 1, 1, 0, 2)", {}),
 ("Quartermaster", "quartermaster", "Quartermaster Brannoch", "burrok", 0, "quartermaster", 6, -8, "PackedVector3Array(0, 0, 0, -3, 0, 1)", {}),
 ("AmirScout", "amir_scout", "Sefa", "amir", 1, "amir_scout", -2, -17, "PackedVector3Array(0, 0, 0, 4, 0, 0)", {"routine_pause": 5.0, "walk_speed": 1.6}),
 ("Messenger", "vapouriun_messenger", "Ilith", "vapouriun", 0, "vapouriun_messenger", 10, 3, "PackedVector3Array(0, 0, 0, 0, 0, 4)", {}),
 ("Kesh", "gyria_scout", "Kesh (wounded)", "gyria", 2, "gyria_scout", 101, 10, "", {"hidden_by_flag": "detained_kesh"}),
 ("KeshPrisoner", "kesh_prisoner", "Kesh (prisoner)", "gyria", 2, "kesh_prisoner", 1, -6, "", {"requires_flag": "detained_kesh"}),
]
for (nm, nid, dname, people, var, dlg, x, z, route, extra) in npcs:
    p = {"transform": tf(x, z, rot=3.14159 if nm in ("Warden",) else 0.0), "script": S["npc"], "npc_id": nid, "display_name": dname, "people": "&\"%s\"" % people, "variant": var, "dialogue_id": dlg}
    if route: p["routine_points"] = route
    p.update(extra)
    node(nm, "CharacterBody3D", "NPCs", p)

node("Enemies", "Node3D", ".", {})
enemies = [
 ("SpireScout1", "gyria_skirmisher", 30, -70, 0, {}),
 ("SpireScout2", "gyria_skirmisher", 41, -80, 1, {}),
 ("SpireScout3", "gyria_spearman", 36, -66, 2, {}),
 ("CampGuard1", "gyria_skirmisher", 90, 0, 3, {}),
 ("CampGuard2", "gyria_spearman", 98, -3, 1, {}),
 ("CampGuard3", "gyria_skirmisher", 92, 10, 2, {}),
 ("FieldPatrol1", "gyria_skirmisher", 70, 80, 0, {"patrol_radius": 10.0}),
 ("FieldPatrol2", "gyria_spearman", 80, 90, 3, {"patrol_radius": 10.0}),
 ("Warchief", "gyria_warchief", 25, -138, 0, {"wait_for_engage": True, "unique_id": "warchief_vorga", "patrol_radius": 3.0}),
]
for (nm, eid, x, z, var, extra) in enemies:
    p = {"transform": tf(x, z), "script": S["enemy"], "definition": enemy(eid), "variant": var}
    p.update(extra)
    node(nm, "CharacterBody3D", "Enemies", p)

node("Creatures", "Node3D", ".", {})
spawners = [
 ("MeadowAlpha", "test_creature_alpha", 28, 22, 2, 1, 2, 7.0),
 ("GladeAlpha", "test_creature_alpha", -72, 36, 2, 2, 3, 7.0),
 ("GladeBeta", "test_creature_beta", -80, 46, 2, 1, 3, 6.0),
 ("LakeBeta", "test_creature_beta", -48, 70, 1, 2, 3, 5.0),
 ("ForestAlpha", "test_creature_alpha", -95, -35, 2, 3, 4, 8.0),
 ("HollowGamma", "test_creature_gamma", -100, -92, 1, 5, 6, 4.0),
]
for (nm, cid, x, z, count, lo, hi, spread) in spawners:
    node(nm, "Node3D", "Creatures", {"transform": tf(x, z), "script": S["spawner"], "creature": creature(cid), "count": count, "min_level": lo, "max_level": hi, "spread": spread})

node("Interactables", "Node3D", ".", {})
chests = [
 ("OutpostChest", "outpost_chest", -14, -1, '{"stamina_tonic": 1, "training_ration": 2}', False),
 ("SpireChest", "spire_chest", 40, -84, '{"healing_draught": 2, "sentinel_charm": 1}', False),
 ("AshfenChest", "ashfen_chest", 100, -6, '{"gyria_hookblade": 1, "gyria_scale_vest": 1, "training_ration": 1}', False),
 ("HollowCache", "hollow_cache", -121, -112, '{"emoria_spear": 1, "greater_draught": 1, "ring_shard": 3}', True),
 ("BattlefieldChest", "battlefield_chest", 72, 93, '{"stamina_tonic": 2, "training_ration": 2}', False),
]
for (nm, cid, x, z, loot, hidden) in chests:
    p = {"transform": tf(x, z, rot=0.5), "script": S["chest"], "chest_id": cid, "loot": loot}
    if hidden: p["hidden_cache"] = True
    node(nm, "Node3D", "Interactables", p)
lores = [
 ("OutpostStone", "emoria_guild", -2, -9, "stone"), ("SpireStone", "sentinel_spire", 31, -62, "stone"),
 ("AshfenBanner", "gyria_clans", 88, 8, "banner"), ("FortRelic", "broken_fort", 25, -124, "relic"),
 ("HollowStone", "hidden_hollow", -118, -107, "stone"), ("LakeStone", "glassmere_ruins", -55, 77, "stone"),
 ("FieldBanner", "old_battlefield", 78, 78, "banner"),
]
for (nm, lid, x, z, style) in lores:
    node(nm, "Node3D", "Interactables", {"transform": tf(x, z), "script": S["lore"], "lore_id": lid, "style": style, "prompt": "Read banner" if style == "banner" else ("Examine relic" if style == "relic" else "Read inscription")})
pickups = [
 ("SealedLetter", "sealed_letter", 1, "spire_letter", 38, -72),
 ("SupplyNorth", "supply_bundle", 1, "supply_north", 18, -36),
 ("SupplyWest", "supply_bundle", 1, "supply_west", -40, 21),
 ("SupplyEast", "supply_bundle", 1, "supply_east", 50, 4),
]
for (nm, iid, n, cid, x, z) in pickups:
    node(nm, "Area3D", "Interactables", {"transform": tf(x, z), "script": S["pickup"], "item_id": iid, "count": n, "collect_id": cid})

node("BossArena", "Area3D", ".", {"transform": tf(25, -135), "script": S["arena"], "boss_path": 'NodePath("../Enemies/Warchief")', "radius": 15.0})

lines = ['[gd_scene load_steps=%d format=3]' % (len(ext) + 1), '']
for path, (kind, rid) in ext.items():
    lines.append('[ext_resource type="%s" path="%s" id="%s"]' % (kind, path, rid))
lines.append('')
for (name, typ, parent, props) in nodes:
    head = '[node name="%s" type="%s"' % (name, typ)
    if parent is not None: head += ' parent="%s"' % parent
    lines.append(head + ']')
    order = ["transform", "script"] + [k for k in props if k not in ("transform", "script")]
    for k in order:
        if k in props: lines.append("%s = %s" % (k, gd(props[k])))
    lines.append('')
open(sys.argv[1], 'w').write("\n".join(lines))
print("nodes", len(nodes), "ext", len(ext))
