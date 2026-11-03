# Velicia roadmap: Game Boy Color-style creature RPG

Legend: ✅ done · 🟡 partial / placeholder · ⬜ not started · 🔒 needs the author's input

## Milestone A: Foundations ✅
- ✅ Godot 4.3, GBC-style 240x160 canvas (scales cleanly on phones), pixel font, 4-colour art rules
- ✅ Original art generated from code (tiles, 16x16 walkers, battle sprites, UI frames)
- ✅ Original chiptune music generated from code (title, town, route, battle, camp, victory)
- ✅ Headless tests + script checker in CI; Android export preset

## Milestone B: Overworld ✅
- ✅ Tile-by-tile movement, turning on the spot, 3-frame walk cycles, ledges, doors and map edges
- ✅ Emoria Watch (town), lodging, Guild Hall, quartermaster's shop, Hollow Road, Ashfen Camp
- ✅ NPCs of all six peoples, signs, items, lore stones, Ring Stones (heal + respawn)
- ✅ Gyria trainers who spot you and walk over to fight; tall-grass wild encounters
- ⬜ More towns and routes, caves/dungeons with simple puzzles, surfing/cutting-style travel skills

## Milestone C: Battles where the warrior fights ✅ (tuning ongoing)
- ✅ Creature command (moves / SWAP) + warrior command (STRIKE / GUARD / RING / BAG / RUN) every turn
- ✅ Enemies target your creature or your warrior; GUARD shields the creature; warrior KO = blackout
- ✅ Wild battles, Gyria warbands (fighter + creature at once), Warchief boss
- ✅ Binding with rings (HP-based chance, wobbles), XP and levels for creatures *and* the warrior
- 🟡 Balance pass; status effects; warrior skills and gear upgrades
- ⬜ Move animations per element; battle backgrounds per area

## Milestone D: Creatures 🔒
- ✅ System: species data, learnsets, element chart (draft), party of 3 + vault, bond
- 🔒 Official creature roster, names, art direction and lore (author to provide)
- ⬜ Evolution / ring forging; a creature log (seen/bound)

## Milestone E: Story & content 🔒
- ✅ First chapter slice: the Warden, the starter choice, the scout, Ashfen, Kesh's choice, Vorga
- 🔒 Story approval (docs/STORY_DRAFT.md), names, region list
- ⬜ Chapters 2+, more Gyria clans, the Pale Withering mystery, more side quests

## Milestone F: Release ⬜
- ⬜ Test on real phones (performance, touch comfort), options menu (text speed, volume)
- ⬜ Release signing, .aab build, store listing, privacy policy (offline, no data collection)
