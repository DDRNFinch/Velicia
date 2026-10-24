# Running and building Velicia on Android

There are two ways to play the current build on your phone.

## Option A — run it inside the Godot editor app on your phone (quickest)
1. Install **Godot Engine 4** from the Google Play Store (the official app is
   published by *Godot Engine*). Version 4.3 or newer.
2. Get the project onto the phone:
   - On GitHub (in a browser), open the Velicia repository, choose the branch,
     then **Code → Download ZIP**.
   - Unzip it with your phone's Files app (for example into
     `Documents/Velicia`). The folder must contain `project.godot`.
3. Open Godot on the phone → **Import** → browse to the folder → select
   `project.godot` → **Import & Edit**. Allow file access if asked.
4. The first import takes a minute (it converts sounds and scenes).
5. Press the **▶ Run Project** button (top right). The game starts on the title
   screen in landscape. Touch controls switch on automatically on a touch screen.
6. To stop, use the back gesture or the stop button in the editor.

Tips: if the editor UI is cramped, rotate to landscape. If text is tiny,
change *Editor Settings → Interface → Editor → Display Scale*.

## Option B — install an APK (plays like a normal app)
The repository has a GitHub Actions workflow (**Android APK**) that builds a
signed **debug** APK:
1. On GitHub, open **Actions → Android APK → Run workflow** (or merge to
   `main`, which runs it automatically).
2. When it finishes, open the run and download the **velicia-debug-apk**
   artifact (a zip containing `velicia-debug.apk`).
3. Unzip on the phone and tap the APK. Android will ask you to allow installs
   from your browser/files app — allow it for this install.

Debug APKs are for testing only. For the Play Store you will need a release
keystore and an `.aab` build (see the release checklist in ROADMAP.md).

## Building on a computer (optional)
1. Install Godot 4.3+ and its **export templates** (Editor → Manage Export Templates).
2. Install Android SDK command-line tools + build tools and JDK 17, then set
   their paths in *Editor Settings → Export → Android*, and create a debug keystore.
3. *Project → Export → Android → Export Project* (preset already configured).

## Controls
| Action | Touch | Keyboard / mouse | Gamepad |
|---|---|---|---|
| Move | Left thumb anywhere on the left side (floating stick) | WASD | Left stick |
| Sprint | Push the stick to the edge | Shift | L3 |
| Look | Drag on the right side | Mouse (click to capture, F1 to release) | Right stick |
| Light attack (combo) | ATTACK | J / left click | X |
| Heavy attack (breaks guard) | HEAVY | K / right click | Y |
| Block / parry (tap just before a hit) | BLOCK (hold) | Q or L | LB |
| Dodge (brief invulnerability) | DODGE | C or Ctrl | B |
| Jump | JUMP | Space | A |
| Skill | SKILL | R | RB |
| Lock on | LOCK | Tab / middle click | R3 |
| Summon / dismiss creature | RING | G | D-pad down |
| Command companion | CMD | H | Back |
| Capture | CAPTURE button (appears when possible) | F | D-pad left |
| Select ring | Tap a ring slot (top right) | V / Z | D-pad right |
| Interact / talk | Tap the prompt | E | D-pad up |
| Heal | HEAL | 1 or X | — |
| Menu | ☰ | Esc, I (inventory), M (map) | Start |

Settings include button size and opacity, camera sensitivity, invert Y,
hold-or-toggle block, auto-targeting, combat assist, screen shake, hitstop,
warning colour and interface scale.

## Troubleshooting
- **Black screen / crash on old phones:** the game uses the Compatibility
  renderer (OpenGL ES 3.0). Very old devices without ES 3.0 are not supported.
- **Low frame rate:** Settings → Graphics → Quality *Low*, Shadows off, View
  distance lower (quality applies when the region loads).
- **Save location:** saves live in the app's private storage
  (`user://saves`). Uninstalling the APK deletes them.
