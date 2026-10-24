# Story content — DRAFT, awaiting approval

Everything on this page beyond the established canon (the six peoples, the
Emoria Guild, the magical creature rings, the conflict with the Gyria) is
**draft** content written to make the first region playable. It is kept in
data files so it can be revised without touching code:

- Dialogue: `data/dialogue/*.json`
- Lore entries: `data/lore/lore.json`
- Quests: `data/quests/*.tres` (all marked `is_draft`)
- Names placed in the world: `scenes/regions/hollow_march.tscn`

## Draft names (please approve, rename or replace)
| Draft name | What it is |
|---|---|
| The Hollow March | The first region |
| Emoria Watch Outpost | The Guild outpost where the game starts |
| The Sentinel Spire | The landmark tower north of the outpost |
| Ashfen Camp | The Gyria camp to the east |
| The Broken Fort | The boss arena north of the Spire |
| Mossglade, Whisperpine Wood, Glassmere, the Hidden Hollow, the Old Battlefield | Other places |
| Warden Aldren (human) | Outpost commander, quest giver |
| Master Oddrin (Gouran) | Ring-sage; teaches capture; trains creatures |
| Quartermaster Brannoch (Burrok) | Supplies; side quest |
| Sefa (Amir) | Scout; combat tips |
| Ilith (Vapouriun) | Messenger; lore and a reward |
| Kesh (Gyria) | Wounded scout; moral choice |
| Warchief Vorga (Gyria) | First boss |
| The Pale Withering | Mystery blight driving the Gyria south |

## Draft story outline (first region)
1. **The Emoria Watch** — the player reports to Warden Aldren.
2. **Smoke over the Spire** — Gyria scouts at the Sentinel Spire. A sealed
   letter reveals they are fleeing a blight (the Pale Withering) and that
   Warchief Vorga is gathering ring-stones. The player chooses how to frame
   this to the Warden (reputation).
3. **The Ashfen Camp** — at the Gyria camp, a wounded scout, Kesh, is left
   behind. **Choice:** spare her (+Gyria reputation, she warns you about the
   Warchief's tactics and explains the Withering) or detain her (+Guild
   reputation, she becomes a prisoner at the outpost). The Warden's closing
   dialogue changes with the choice.
4. **Warchief Vorga** at the Broken Fort — two-phase boss. Defeat recovers the
   stolen ring-stone.
5. Side quests: **The Ring Trial** (capture and summon a creature),
   **Lost on the Road** (find three supply bundles).

The Gyria are written as a people under pressure, with internal disagreement
("Maybe she's right. Maybe she's mad.") — not as inherently evil.

## Open questions for the author
- The protagonist's background and whether they stay customisable.
- The Pale Withering: keep, change or replace as the central mystery?
- How the Guild Council and other kingdoms fit into the main story.
- The real creature roster (see CREATURE_SYSTEM.md).
