#!/usr/bin/env python3
"""Map data for Velicia's first area, written as data/maps/<id>.json.

Maps are ASCII tile grids plus lists of buildings, warps, people, trainers,
signs, items, Ring Stones and lore stones. Edit the layouts here and run:
    python3 tools/make_maps.py

Tile legend (16x16 tiles, see scripts/world/overworld.gd):
  .  grass       ,  grass (variant)   *  flowers        "  tall grass (wild creatures)
  =  path        :  path (variant)    s  sand           ~  water (solid)
  T  tree (solid)    L  ledge (hop down, south only)    F  fence (solid)
  #  rock (solid)    ^  rock with grass top (solid)     o  stone floor
  w  wood floor  W  wall (solid)  N  wall with window (solid)  M  door mat
  C  counter (solid)  K  shelf (solid)  B  bed (solid)  P  plant (solid)
  t  table (solid)  A  ring altar (solid)  r  rug  S  stairs  c  cave floor  X  void (solid)
Buildings are drawn as objects; their footprint is solid except the door.
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "data", "maps")


def check(name, rows):
    """All rows must match the first row's width; short rows are padded with
    grass before their last (border) tile to make authoring easier."""
    w = len(rows[0])
    out = []
    for i, r in enumerate(rows):
        assert len(r) <= w, "%s row %d is too wide (%d > %d): %r" % (name, i, len(r), w, r)
        out.append(r[:-1] + "." * (w - len(r)) + r[-1] if len(r) < w else r)
    return out


MAPS = {}

# ------------------------------------------------------------------ Emoria Watch (town)
MAPS["emoria"] = {
    "name": "Emoria Watch", "music": "town",
    "rows": check("emoria", [
        "TTTTTTTTT==TTTTTTTTT",
        "T,,.....:==:.....,,T",
        "T.......:==:.......T",
        "T........==........T",
        "T........==........T",
        "T........==........T",
        "T*.......==......*.T",
        "T..==============..T",
        "T..=.............=.T",
        "T..=......*......=.T",
        "T..=.............=.T",
        "T..=.............=.T",
        "T..=.......~~~~..=.T",
        "T..=...,..~~~~~~.=.T",
        "T..====...~~~~~~.=.T",
        "T*....=....~~~~..=.T",
        "T,....============.T",
        "TTTTTTTTTTTTTTTTTTTT",
    ]),
    "objects": [
        {"sprite": "house_red", "x": 2, "y": 3, "w": 4, "h": 4, "door": [1, 3]},
        {"sprite": "guild_hall", "x": 12, "y": 2, "w": 6, "h": 5, "door": [3, 4]},
        {"sprite": "shop", "x": 4, "y": 8, "w": 4, "h": 4, "door": [2, 3]},
        {"sprite": "campfire", "x": 13, "y": 9, "anim": 2},
        {"sprite": "banner", "x": 11, "y": 6}, {"sprite": "banner", "x": 18, "y": 6},
    ],
    "warps": [
        {"x": 3, "y": 6, "to": "home", "tx": 3, "ty": 6, "facing": "up"},
        {"x": 15, "y": 6, "to": "guild", "tx": 4, "ty": 8, "facing": "up"},
        {"x": 6, "y": 11, "to": "shop", "tx": 3, "ty": 6, "facing": "up"},
        {"x": 9, "y": 0, "to": "route1", "tx": 9, "ty": 38, "facing": "up"},
        {"x": 10, "y": 0, "to": "route1", "tx": 10, "ty": 38, "facing": "up"},
    ],
    "npcs": [
        {"id": "sefa", "name": "Sefa", "sprite": "amir", "x": 8, "y": 9, "facing": "down", "dialogue": "sefa", "wander": 2},
        {"id": "mira", "name": "Mira", "sprite": "villager", "x": 15, "y": 14, "facing": "left", "dialogue": "mira", "wander": 2},
        {"id": "tobin", "name": "Tobin", "sprite": "villager2", "x": 3, "y": 15, "facing": "right", "dialogue": "tobin", "wander": 2},
        {"id": "ilith", "name": "Ilith", "sprite": "vapouriun", "x": 10, "y": 13, "facing": "right", "dialogue": "ilith"},
    ],
    "signs": [
        {"x": 7, "y": 6, "text": "EMORIA WATCH\\nOutpost of the Emoria Guild."},
        {"x": 11, "y": 2, "text": "North: the Hollow Road."},
    ],
    "stones": [{"id": "watch_stone", "x": 16, "y": 9}],
    "items": [{"id": "town_tonic", "x": 1, "y": 15, "item": "tonic", "count": 1}],
}

# ------------------------------------------------------------------ interiors
MAPS["home"] = {
    "name": "Guild Lodging", "music": "home",
    "rows": check("home", [
        "WWNWWWNW",
        "KKwwwwBw",
        "wwwwwwBw",
        "wwwrrwww",
        "Pwwrrwwt",
        "wwwwwwwt",
        "wwwwwwww",
        "XXXMMXXX",
    ]),
    "warps": [{"x": 3, "y": 7, "to": "emoria", "tx": 3, "ty": 7, "facing": "down"},
              {"x": 4, "y": 7, "to": "emoria", "tx": 3, "ty": 7, "facing": "down"}],
    "signs": [{"x": 0, "y": 1, "text": "Shelves of Guild ledgers. One is titled 'Rings and How Not to Lose Them'."},
              {"x": 7, "y": 4, "text": "A note: 'Report to Warden Aldren in the Guild Hall. - A.'"}],
    "npcs": [],
}

MAPS["guild"] = {
    "name": "Guild Hall", "music": "guild",
    "rows": check("guild", [
        "WWNWWWWNWW",
        "KKwwwwwwKK",
        "wwwwAAwwww",
        "wwwwwwwwww",
        "Pwwwrrwwwt",
        "wwwwrrwwwt",
        "wwwwrrwwww",
        "wwwwrrwwww",
        "wwwwwwwwww",
        "XXXXMMXXXX",
    ]),
    "warps": [{"x": 4, "y": 9, "to": "emoria", "tx": 15, "ty": 7, "facing": "down"},
              {"x": 5, "y": 9, "to": "emoria", "tx": 15, "ty": 7, "facing": "down"}],
    "npcs": [
        {"id": "warden", "name": "Warden Aldren", "sprite": "warden", "x": 2, "y": 3, "facing": "down", "dialogue": "warden"},
        {"id": "oddrin", "name": "Master Oddrin", "sprite": "gouran", "x": 5, "y": 1, "facing": "down", "dialogue": "oddrin"},
    ],
    "signs": [{"x": 4, "y": 2, "text": "Three rings rest on the altar, each humming softly."},
              {"x": 5, "y": 2, "text": "Three rings rest on the altar, each humming softly."}],
}

MAPS["shop"] = {
    "name": "Quartermaster", "music": "guild",
    "rows": check("shop", [
        "WWNWWNWW",
        "KKKwwKKK",
        "wwwwwwww",
        "CCCCwwww",
        "wwwwwwwP",
        "wwwwwwww",
        "wwwwwwww",
        "XXXMMXXX",
    ]),
    "warps": [{"x": 3, "y": 7, "to": "emoria", "tx": 6, "ty": 12, "facing": "down"},
              {"x": 4, "y": 7, "to": "emoria", "tx": 6, "ty": 12, "facing": "down"}],
    "npcs": [{"id": "brannoch", "name": "Brannoch", "sprite": "burrok", "x": 1, "y": 2, "facing": "down", "dialogue": "brannoch", "talk_over": True}],
}

# ------------------------------------------------------------------ Hollow Road (route 1)
MAPS["route1"] = {
    "name": "Hollow Road", "music": "route",
    "rows": check("route1", [
        "TTTTTTTT====TTTTTTTT",
        "TTTT....====....TTTT",
        "TT.......==.......TT",
        "T.....o.ooo.o......T",
        "T.....oooooo.......T",
        "T......o==o........T",
        "T.......==.....\"\"\"\"T",
        "T\"\"\"....==....\"\"\"\"\"T",
        "T\"\"\"\"...==.....\"\"\"\"T",
        "T\"\"\"\"...==..........",
        "T.......==..........",
        "TLLLLL..==..LLLLLL==",
        "T.......==........==",
        "T..TT...===========T",
        "T..TT...==.........T",
        "T.......==..\"\"\"\"\"..T",
        "Tss.....==..\"\"\"\"\"..T",
        "T~~s....==..\"\"\"\"\"..T",
        "T~~~s...==.........T",
        "T~~~s...==..TT.....T",
        "T~~s.*..==..TT..*..T",
        "Tss.....==.........T",
        "T.......==.........T",
        "TLLLLLL.==.LLLLLLLLT",
        "T.......==.........T",
        "T\"\"\"\"\"..==...\"\"\"\"\"T",
        "T\"\"\"\"\"..==....\"\"\"\"T",
        "T\"\"\"\"...==....\"\"\"\"\"T",
        "T.......==.........T",
        "T...*...==....TT...T",
        "T.......==....TT...T",
        "TTT.....==.........T",
        "TTT.....==.....*...T",
        "T.......==.........T",
        "T..\"\"\"..==..\"\"\"....T",
        "T..\"\"\"..==..\"\"\"....T",
        "T.......==.........T",
        "TT......==.......TTT",
        "TTTTTTTTT==TTTTTTTTT",
    ]),
    "warps": [
        {"x": 9, "y": 38, "to": "emoria", "tx": 9, "ty": 1, "facing": "down"},
        {"x": 10, "y": 38, "to": "emoria", "tx": 10, "ty": 1, "facing": "down"},
        {"x": 19, "y": 9, "to": "ashfen", "tx": 1, "ty": 9, "facing": "right"},
        {"x": 19, "y": 10, "to": "ashfen", "tx": 1, "ty": 10, "facing": "right"},
    ],
    "encounters": {"rate": 0.12, "table": [["gamma", 2, 4, 3], ["delta", 2, 4, 3], ["epsilon", 3, 5, 1], ["beta", 3, 5, 1], ["alpha", 4, 5, 1]]},
    "npcs": [
        {"id": "scout", "name": "Scout Vel", "sprite": "villager2", "x": 11, "y": 33, "facing": "left", "dialogue": "scout"},
        {"id": "brannoch_cousin", "name": "Hrolf", "sprite": "burrok", "x": 6, "y": 18, "facing": "right", "dialogue": "hrolf"},
    ],
    "trainers": [
        {"id": "scout_a", "name": "Gyria Scout", "sprite": "gyria", "x": 4, "y": 24, "facing": "right", "sight": 4,
         "intro": "A human with a ring? Hah! Let's see if it bites.", "lose": "Tch. Your ring-beast hits hard.",
         "team": [{"fighter": "gyria", "name": "Scout Ruk", "level": 3}, {"species": "delta", "level": 3}], "reward": 60},
        {"id": "scout_b", "name": "Gyria Archer", "sprite": "gyria_archer", "x": 15, "y": 14, "facing": "left", "sight": 5,
         "intro": "Stop there! Vorga said no one passes.", "lose": "...Vorga won't like this.",
         "team": [{"fighter": "gyria_archer", "name": "Archer Tess", "level": 4}], "reward": 80},
        {"id": "scout_c", "name": "Gyria Scout", "sprite": "gyria", "x": 3, "y": 8, "facing": "right", "sight": 3,
         "intro": "Grass is ours today, warden.", "lose": "Fine. Go on, then.",
         "team": [{"fighter": "gyria", "name": "Scout Mag", "level": 5}, {"species": "epsilon", "level": 4}], "reward": 90},
    ],
    "signs": [
        {"x": 7, "y": 36, "text": "HOLLOW ROAD\\nTall grass: wild creatures! Keep a ring creature ready."},
        {"x": 18, "y": 10, "text": "East: ASHFEN. Gyria camp. Turn back."},
        {"x": 7, "y": 2, "text": "SENTINEL SHRINE ahead. A Ring Stone restores weary travellers."},
    ],
    "stones": [{"id": "shrine_stone", "x": 9, "y": 3}],
    "lore": [{"id": "lore_shrine", "x": 11, "y": 3, "title": "The First Ring",
              "text": "'A ring is a promise. Bind nothing you will not protect.'"},
             {"id": "lore_glassmere", "x": 1, "y": 21, "title": "The Glassmere Stone",
              "text": "In Vapouriun script: 'The water remembers every face it has shown.'"}],
    "items": [{"id": "route_ring", "x": 1, "y": 7, "item": "binding_ring", "count": 3},
              {"id": "route_tonic", "x": 18, "y": 29, "item": "tonic", "count": 2},
              {"id": "route_elixir", "x": 3, "y": 13, "item": "elixir", "count": 1}],
}

# ------------------------------------------------------------------ Ashfen Camp
MAPS["ashfen"] = {
    "name": "Ashfen Camp", "music": "camp",
    "rows": check("ashfen", [
        "TTTTTTTTTTTTTTTTTTTTTT",
        "TTTTTTTT######TTTTTTTT",
        "TTT.....#oooo#.....TTT",
        "TT......#oooo#......TT",
        "TT.....,..oo..,.....TT",
        "TT.......=..=.......TT",
        "T........=..=........T",
        "T...============.....T",
        "T...=..........=.....T",
        "=====..........=.....T",
        "=......,.......=.....T",
        "T...=..........=.....T",
        "T...============.....T",
        "T........\"\"\"\"......TT",
        "TT......\"\"\"\"\"\"....TTT",
        "TTT......\"\"\"\".....TTT",
        "TTTT...............TTT",
        "TTTTTTTTTTTTTTTTTTTTTT",
    ]),
    "objects": [
        {"sprite": "tent", "x": 5, "y": 8, "w": 2, "h": 2, "solid": True},
        {"sprite": "tent_red", "x": 12, "y": 8, "w": 2, "h": 2, "solid": True},
        {"sprite": "tent", "x": 17, "y": 9, "w": 2, "h": 2, "solid": True},
        {"sprite": "campfire", "x": 9, "y": 10, "anim": 2, "solid": True},
        {"sprite": "banner", "x": 8, "y": 4}, {"sprite": "banner", "x": 13, "y": 4},
        {"sprite": "crate", "x": 18, "y": 6, "solid": True},
    ],
    "warps": [{"x": 0, "y": 9, "to": "route1", "tx": 18, "ty": 9, "facing": "left"},
              {"x": 0, "y": 10, "to": "route1", "tx": 18, "ty": 10, "facing": "left"}],
    "encounters": {"rate": 0.1, "table": [["alpha", 5, 7, 2], ["epsilon", 5, 7, 2], ["delta", 5, 6, 1]]},
    "npcs": [{"id": "kesh", "name": "Kesh", "sprite": "kesh", "x": 19, "y": 12, "facing": "left", "dialogue": "kesh"}],
    "trainers": [
        {"id": "camp_a", "name": "Gyria Blade", "sprite": "gyria", "x": 7, "y": 6, "facing": "down", "sight": 4,
         "intro": "Intruder! Blades out!", "lose": "Gah! Go, then. Vorga will finish you.",
         "team": [{"fighter": "gyria", "name": "Blade Korr", "level": 6}, {"species": "alpha", "level": 5}], "reward": 120},
        {"id": "camp_b", "name": "Gyria Archer", "sprite": "gyria_archer", "x": 14, "y": 6, "facing": "down", "sight": 4,
         "intro": "One more step and you're a pincushion.", "lose": "My string snapped. That's my story.",
         "team": [{"fighter": "gyria_archer", "name": "Archer Vey", "level": 6}, {"species": "delta", "level": 6}], "reward": 120},
        {"id": "warchief", "name": "Warchief Vorga", "sprite": "gyria_boss", "x": 11, "y": 3, "facing": "down", "sight": 2,
         "boss": True, "requires_flag": "",
         "intro": "So the Guild sends a whelp with a ring. I am Vorga. My clan does not run twice!",
         "lose": "...Strong. The Withering is stronger. Remember that, warden.",
         "team": [{"fighter": "gyria_boss", "name": "Warchief Vorga", "level": 9}, {"species": "epsilon", "level": 7}], "reward": 300,
         "flag": "warchief_defeated"},
    ],
    "signs": [{"x": 3, "y": 9, "text": "A scratched marker: 'ASHFEN. Turn back.'"}],
    "items": [{"id": "camp_chest", "x": 20, "y": 15, "item": "heart_vessel", "count": 1}],
    "stones": [],
}


def main():
    os.makedirs(OUT, exist_ok=True)
    for mid, m in MAPS.items():
        m = dict(m)
        m["rows"] = [r.replace("\\n", "\n") for r in m["rows"]]
        for s in m.get("signs", []):
            s["text"] = s["text"].replace("\\n", "\n")
        m["width"] = len(m["rows"][0])
        m["height"] = len(m["rows"])
        with open(os.path.join(OUT, mid + ".json"), "w") as f:
            json.dump(m, f, indent=1)
    print("wrote", ", ".join(MAPS))


if __name__ == "__main__":
    main()
