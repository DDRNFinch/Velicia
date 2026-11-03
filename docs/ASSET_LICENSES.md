# Asset sources and licences

Record **every** asset that enters the project here, with its source and
licence, before it is committed. Do not add ripped or copyrighted game assets
(no sprites, music, names or logos from existing games).

| Asset | Path | Source | Licence | Notes |
|---|---|---|---|---|
| Godot Engine | - | godotengine.org | MIT | Engine and export templates |
| Pixel art (tiles, characters, battle sprites, objects, UI, font) | `art/` | Original, drawn from code by `tools/gbc_art.py` (uses `tools/make_art.py`) | Project licence | GBC-style 4-colour rules; regenerate any time |
| Maps | `data/maps/*.json` | Original, `tools/make_maps.py` | Project licence | |
| Music (6 tracks) | `audio/music/*.wav` | Original chiptune composed in `tools/make_music.py` | Project licence | No borrowed melodies |
| Sound effects | `audio/sfx/*.wav` | Original, synthesised (earlier `generate_audio.py`) | Project licence | Placeholders |
| Peoples reference sheet | `docs/reference/peoples_of_velicia.jpg` | Supplied by the project author | Author's own | Design reference only |
| Icon | `icon.svg` | Original | Project licence | |

No third-party art, music or sound packs are used.
