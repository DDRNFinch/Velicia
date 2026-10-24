# Technical plan and architecture

## Engine and targets
- **Godot 4.3+**, **GDScript only** (no C#), Compatibility renderer (OpenGL ES 3)
  for broad Android support. Opens in newer 4.x versions too.
- Landscape (sensor-landscape), 1280×720 base canvas, stretch `canvas_items` /
  `expand`, so the UI scales across phone aspect ratios.
- Offline, single-player. No servers or accounts.

## Project layout
```
project.godot            engine config, autoloads, input map
export_presets.cfg       Android export preset
scenes/
  main/main_menu.tscn    title, new game (character creator), settings
  game/game.tscn         gameplay root (loads region, player, HUD, menu)
  player/player.tscn     Emoria warrior
  regions/hollow_march.tscn   first region: locations, NPCs, enemies, spawners, chests
scripts/
  autoload/   EventBus, Database, Settings, AudioManager, GameState,
              QuestManager, SaveManager, CombatDirector, Fx
  data/       Resource classes: Item/Attack/Enemy/BossPhase/Creature/
              CreatureAbility/Ability/Quest/QuestStage/QuestObjective definitions
  core/       HitData, CombatStats, CombatUtil, PlaceholderBody, CreatureBody
  player/     Player, CameraRig, PlayerAppearance
  enemies/    Enemy (data-driven AI incl. boss phases)
  creatures/  CreatureActor (wild + companion), RingController, CreatureInstance
  world/      RegionBuilder, VeliciaTerrain, LocationTrigger, NPC, Interactable,
              TreasureChest, SaveShrine, LoreStone, LootPickup, CreatureSpawner, BossArena
  dialogue/   DialogueRunner
  ui/         HUD, TouchControls, PauseMenu, SettingsPanel, MapView, UiTheme, main_menu
data/         .tres definitions + dialogue/lore JSON (all content lives here)
audio/        sfx, ambience, music (procedural placeholders)
tests/        headless integration test suite
tools/        input map, data and audio generators, script checker, screenshots
docs/         design and technical documentation
```

## Key design decisions
| Decision | Why |
|---|---|
| **Data-driven content** (`Resource` .tres for items, attacks, enemies, creatures, abilities, quests; JSON for dialogue/lore) | New content needs no code; writers can edit dialogue as text |
| **EventBus** for gameplay events | Quests, UI, progression and audio react without coupling |
| **One input path**: touch controls press the same InputMap actions as keyboard/gamepad | Gameplay code never branches on device; everything is testable |
| **Attack = windup / active / recovery** timings in data | Readable telegraphs, weight and punishable recovery; the same model drives player, enemies and bosses |
| **Attack tokens** (CombatDirector) | Only 2 enemies (3 with a boss) attack at once; others circle — readable group fights and fewer active AIs |
| **Distance sleep** for enemies (> 75 m) | CPU budget on phones |
| **Pooled** hit sparks, damage numbers, ring bursts and audio players | No per-hit allocations |
| **MultiMesh + visibility ranges** for trees and rocks, chunked | Few draw calls; distance culling |
| **Procedural placeholder art** behind small interfaces | Gameplay is finished first; models can be swapped later (see ASSET_REQUIREMENTS.md) |
| **Versioned JSON saves**, atomic write + verified temp file + backup | Corruption-safe, migratable |
| Region terrain from a **deterministic height function** with flatten zones from LocationTriggers | Designers move a location and the ground follows; tiny files |

## Combat model
- Player: light combo (3), heavy (guard break, hyper-armour on impact),
  whirling-cut skill, block (stamina), **parry** = block within 0.2 s before
  impact (0.32 s with Combat Assist), **dodge** with i-frames 0.03–0.30 s.
- Hits apply damage, poise damage (stagger when broken), knockback, hitstop,
  camera shake, sparks and numbers. Parried/dazed targets take critical damage.
- Enemies: patrol → alert → chase/position (circle) → telegraphed attack →
  recovery; may raise guard (break it with heavies); leash and return home.
- Bosses: phase list by health; each phase changes attack set, speed and
  recovery and triggers a roar shockwave.

## Scaling the world
- A region = one scene with a `RegionBuilder` root. Add a region by creating a
  new scene and registering it in `scripts/game/game.gd` (`REGIONS`).
- Save data already stores `region`, so travel between regions only needs a
  travel point that sets `GameState.region` and reloads `game.tscn`.

## Testing
- `tools/check_scripts.tscn` compiles every script and loads every resource.
- `tests/test_runner.tscn` runs ~120 integration checks headlessly (data,
  dialogue, quests, save/load incl. corruption recovery, movement, combat,
  parry/dodge, AI, capture, companion, touch input, dialogue, shrine, death,
  menus).
- `tools/screenshots.tscn` renders review screenshots (needs a display).
- GitHub Actions runs the checks on every push and builds a debug APK on `main`.
