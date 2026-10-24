# Creature rings — system guide

Creatures are entirely data-driven. **The official roster has not been
designed yet**: the three creatures in `data/creatures/` are clearly labelled
temporary test creatures (α, β, γ) that exist only to exercise the system.
Replace or delete them when the real designs are approved.

## The loop in play
1. **Encounter** creatures in the wild (spawners keep populations alive).
2. **Weaken** one in combat. When its health drops to its capture threshold it
   becomes **dazed** for a few seconds and shows a glowing ring and "✦ Capturable".
3. **Capture**: press CAPTURE (button appears with the success chance) while
   wearing a ring with an empty slot of a high enough tier. You channel for
   1.5 s; being hit interrupts you. Success binds it to the ring; failure lets
   it break free (it recovers a little health and fights back).
4. **Store/manage**: up to 3 worn rings, one creature each; extra creatures
   rest in the Guild vault (swap at a Ring Stone shrine).
5. **Summon / dismiss** the creature in the active ring (RING button, or tap a
   ring slot twice). Switching rings is instant when nothing is summoned.
6. **Fight together**: the companion follows you and fights according to its
   temperament (aggressive / defensive / support).
7. **Command**: CMD makes it attack your current target; pressing CMD with no
   target toggles "hold back".
8. **Rest**: creatures in rings recover health over time; a creature knocked
   out in battle is **exhausted** for 45 s (Ring Stones restore it at once).
9. **Train**: Master Oddrin (the outpost ring-sage) trains creatures with
   Training Rations (+40 XP, +3 bond).
10. **Bond**: fighting and summoning deepen bond (levels 0–4). Abilities can
    require a creature level and/or bond level to unlock.

Capture chance = base chance × rarity factor × ring power × weakness bonus
(up to +60%) × 1.25 if dazed, clamped to 5–95%.

## Adding a creature (no code needed)
In the Godot editor: **FileSystem → data/creatures → right-click → New
Resource → CreatureDefinition**, save as `<id>.tres`, then fill in:

| Field | Meaning |
|---|---|
| `id` | Unique id, e.g. `emberback` |
| `display_name`, `description` | Shown in the ring menu |
| `is_placeholder` | Untick for approved creatures |
| `rarity` | Common → Legendary (affects capture chance) |
| `temperament` | Aggressive (engages enemies), Defensive (helps when you fight), Support (stays close, heals) |
| Stats | Base health/attack/defence and per-level growth, move speed, max level |
| `abilities` | List of `CreatureAbility` (melee, ranged, area, heal ally, guard) with power, cooldown, range, windup, **required level** and **required bond** |
| Capture | Health threshold, base chance, minimum ring tier, extra condition (`dazed`), hint text |
| Appearance | Placeholder body shape/colours/size until a model exists |
| Wild behaviour | Wander radius, flee when weak, hostile on sight |

Then place a **CreatureSpawner** node in a region scene and set its `creature`
field to the new resource. The creature automatically appears in the journal,
ring menu, training panel and save files.

## Ideas template for the author
When you're ready to supply creatures, this is the information that maps
straight into the system:

```
Name:
Look (silhouette, size, colours, special features):
Personality / temperament (aggressive, defensive, support):
Habitat (where in Velicia it lives):
Rarity:
How it fights (2–4 abilities, and which unlock with bond):
How it must be captured (threshold, special condition, ring tier):
Lore notes:
```
