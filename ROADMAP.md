# Velicia roadmap — prototype to Android release

Legend: ✅ done · 🟡 partial / placeholder · ⬜ not started · 🔒 needs the author's input

## Milestone 0 — Foundation ✅
- ✅ Godot 4.3 project, Compatibility renderer, landscape, autoload architecture
- ✅ Input map (keyboard, mouse, gamepad) + Android export preset
- ✅ Data-driven resources for items, attacks, enemies, creatures, abilities, quests
- ✅ Automated script check, integration tests, CI, screenshot tool

## Milestone 1 — Playable warrior in a 3D world ✅
- ✅ Third-person character: analogue walk/run, sprint, jump, coyote time
- ✅ Follow camera with collision, touch/mouse/stick look, lock-on framing
- ✅ Terrain with collision, forests, rocks, water, sky, fog, sun shadows
- ✅ Landmark: the Sentinel Spire, visible from the starting outpost
- 🟡 Character art and animation are procedural placeholders

## Milestone 2 — Combat ✅ (tuning ongoing)
- ✅ Light combo, heavy (guard break), skill, block, timed parry + riposte, dodge i-frames
- ✅ Stamina, poise/stagger, knockback, hitstop, camera shake, sparks, numbers
- ✅ Soft targeting, lock-on, attack buffering and recovery cancels
- ✅ Gyria skirmisher and spear-warden with telegraphs, guarding, attack tokens
- ✅ Boss: Warchief with phases, ground telegraphs, charge and roar
- ⬜ Balance pass on real devices
- ⬜ More archetypes: archers (projectiles), shield-bearers, Gyria shamans
- ⬜ Ambushes, group tactics (flanking), enemy morale/retreat
- ⬜ Final hit VFX, animation-driven hit windows

## Milestone 3 — Touch controls ✅
- ✅ Floating joystick, look-drag zone, two-thumb button arc, multi-touch
- ✅ Contextual buttons (capture, interact), ring slots, adjustable size/opacity
- ⬜ Haptics, customisable layout editor, controller glyphs

## Milestone 4 — Creature rings ✅ (system) / 🔒 (content)
- ✅ Capture rules (threshold, daze, ring tier, chance), capture channel and failure
- ✅ Rings (3 worn) and vault, summon/dismiss, exhaustion and recovery
- ✅ Companion AI: follow, temperaments, commands, abilities, XP and levels
- ✅ Bond levels unlocking abilities; training at the ring-sage
- 🔒 Official creature roster and lore (author to provide)
- ⬜ Creature evolution/affinities, ring forging (Ring Shards), creature combos with player skills
- ⬜ Final ring VFX and creature models/animations

## Milestone 5 — Region, NPCs, quests, saving ✅
- ✅ The Hollow March: 9 locations, 3 Ring Stones, 7 NPCs (all six peoples), 9 Gyria + boss, 6 creature spawners, 5 chests, 7 lore pieces, collectibles
- ✅ Branching JSON dialogue with conditions/effects
- ✅ Quests: 3-part main chain, 2 side quests; moral choice with consequences and reputation
- ✅ Discovery, journal, lore, map with quest markers
- ✅ Versioned saves, backup recovery, migrations; shrine rest/respawn
- 🔒 Story, names and lore approval (see docs/STORY_DRAFT.md)
- ⬜ NPC daily schedules (time of day), barks, more side content

## Milestone 6 — Menus, inventory, progression ✅
- ✅ Main menu, character creator, settings, pause menu with 7 tabs
- ✅ Inventory, equipment, consumables, loot, levels, attributes, Guild abilities
- ⬜ Shops and currency, crafting, more weapons per people (spear/axe/dagger movesets)
- ⬜ Skill tree with combat stances

## Milestone 7 — Art production ⬜
- ⬜ Style guide and colour script per region
- ⬜ Rigged models: player (modular armour), the six peoples, Gyria soldiers and bosses (see CHARACTER_DESIGN.md)
- ⬜ AnimationTree adapter replacing procedural animation
- ⬜ Modular environment kit, foliage with LODs/impostors, water shader
- ⬜ VFX: hits, parry, rings, magic; UI artwork and icons; fonts
- ⬜ Original music score and recorded SFX; ambience per area; voice (optional)

## Milestone 8 — World expansion ⬜
- ⬜ Region streaming / travel between regions
- ⬜ Region 2+ (settlements of each people, Gyria homelands, dungeons)
- ⬜ Day/night and weather
- ⬜ Main story acts 1–3, companion characters, faction quests, endings

## Milestone 9 — Performance and device support ⬜
- 🟡 Pooling, multimesh, distance sleeping, attack tokens (done)
- ⬜ Profiling on low/mid/high Android devices; target 30 fps low, 60 fps mid+
- ⬜ Texture compression (ETC2/ASTC) per asset, LODs, occlusion, baked lighting where useful
- ⬜ Memory and thermal budgets, battery saver mode

## Milestone 10 — Release ⬜
- ⬜ Release keystore, `.aab` build, Play Console listing, privacy policy (offline, no data collection)
- ⬜ Accessibility review (text size, colour-blind modes, remapping)
- ⬜ Localisation pipeline
- ⬜ Closed testing → open testing → production
