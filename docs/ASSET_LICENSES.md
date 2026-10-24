# Asset sources and licences

Record **every** asset that enters the project here, with its source and
licence, before it is committed. Do not add ripped or copyrighted game assets.

| Asset | Path | Source | Licence | Notes |
|---|---|---|---|---|
| Godot Engine | — | godotengine.org | MIT | Engine and export templates |
| All 3D placeholder geometry | generated at runtime | Original (procedural code in this repo) | Project licence | `placeholder_body.gd`, `creature_body.gd`, `region_builder.gd` |
| Sound effects (17) | `audio/sfx/*.wav` | Original, synthesised by `tools/generate_audio.py` | Project licence | Placeholder quality |
| Ambience (wind loop) | `audio/sfx/ambience_wind.wav` | Original, synthesised | Project licence | |
| Music: exploration, combat | `audio/music/*.wav` | Original, synthesised | Project licence | Placeholder music |
| Icon | `icon.svg` | Original | Project licence | |
| Fonts | — | Godot's built-in default font (ships with the engine) | Engine-bundled (open licence) | Replace with a chosen, licensed font later |

No third-party art, sound or music packs are used in this build.
