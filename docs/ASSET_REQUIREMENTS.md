# Asset requirements and replacement guide

Every visual and audio asset in the current build is a **placeholder**.
Nothing here is final art. This document lists exactly what is needed and how
to swap assets in without breaking gameplay.

## Current placeholders

| Area | Placeholder | Where it is made |
|---|---|---|
| Humanoids (player, NPCs, Gyria) | Primitive meshes with procedural animation | `scripts/core/placeholder_body.gd` |
| Creatures | Primitive quadruped / hovering body | `scripts/core/creature_body.gd` |
| Terrain, trees, rocks, water | Procedural mesh + MultiMesh | `scripts/world/region_builder.gd` |
| Buildings, ruins, camp, fort | Primitive "structure kits" | `region_builder.gd` (`_kit_*`) |
| Chests, shrines, lore stones | Primitive meshes | `scripts/world/*.gd` |
| UI | Godot theme built in code | `scripts/ui/ui_theme.gd` |
| Sound and music | Procedurally synthesised originals | `tools/generate_audio.py` → `audio/` |

## Characters (glTF 2.0 `.glb`)
- One shared humanoid skeleton (≤ 60 bones), with per-people proportions.
  Extra chains: Amir tail (5 bones), optional cloak/mantle (4–6 bones).
- Faces: a shared facial rig or blendshape set (blink, jaw, brows, 4–6 visemes).
  **All peoples have human-structured faces** — see CHARACTER_DESIGN.md.
- Required animation clips (names used by the planned AnimationTree):
  `idle, walk, run, sprint, jump_start, jump_air, land, dodge, block_idle,
  block_hit, parry, stagger_light, stagger_heavy, death, interact, talk_idle,
  capture_cast, summon_cast` plus per-weapon attacks
  `light_1, light_2, light_3, heavy, skill_whirl` (each split into
  windup/active/recovery timings that match `data/attacks/*.tres`).
- Enemies: Gyria soldier set (sword/hookblade + spear), Gyria Warchief set
  (`cleave, slam, sweep, charge, frenzy, roar`).

### Mobile budgets (mid-range Android)
| Asset | LOD0 tris | Bones | Materials | Texture |
|---|---|---|---|---|
| Player / Amir / Vapouriun / Gouran / Gyria soldier | 8k–15k | ≤ 60 | 1–2 | 1024² atlas |
| Burrok | 12k–18k | ≤ 65 | 1–2 | 1024²–2048² |
| Gyria boss, hero NPCs | 15k–25k | ≤ 75 | ≤ 3 | 2048² |
| Creatures | 4k–12k | ≤ 40 | 1–2 | 1024² |
| Crowd/background NPCs | 3k–6k | ≤ 40 | 1 | 512² |

Provide LODs at ≈50% and ≈20%. Use stylised shading (simple PBR or toon ramp).
Fur and hair: alpha cards or stylised geometry, not strand hair.

## Creatures
Final creature designs will come from the game's author. For each creature,
provide a model, `idle/walk/run/attack/hit/daze/faint/summon_appear` clips,
and fill a `CreatureDefinition` resource (see [CREATURE_SYSTEM.md](CREATURE_SYSTEM.md)).

## Environment kit
Modular pieces on a 2 m grid: palisade, gate, tents (guild/settler/Gyria),
watchtower, stone walls/towers (intact + broken), arches, pillars, Spire
segments + crown crystal, rocks (3 sizes), trees (pine/broadleaf, 3 variants
each with LODs and impostors), grass clumps, props (crates, barrels, racks,
banners, campfire), water shader (cheap, no refraction).

## How to replace a placeholder
1. **Characters:** add a `model_scene` export to the actor scripts that
   instantiates your `.glb` instead of `PlaceholderBody`; keep the same public
   calls (`animate`, `pose_attack`, `flash`, `set_telegraph`) by implementing
   them in a small adapter script that drives an `AnimationTree`.
   Gameplay never reads mesh data, so nothing else changes.
2. **Structures:** replace a `_kit_*` function with code that instances your
   modular scene at the same location (or place scenes directly in
   `scenes/regions/hollow_march.tscn`).
3. **Audio:** overwrite the files in `audio/` (same names) or change the
   paths in `scripts/autoload/audio_manager.gd`.
4. **UI:** change colours, fonts and styleboxes in `scripts/ui/ui_theme.gd`.

Record every imported asset in [ASSET_LICENSES.md](ASSET_LICENSES.md).
