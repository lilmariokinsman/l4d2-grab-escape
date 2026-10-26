# Grab Escape (Left 4 Dead 2)

When a special infected pins you (hunter pounce, smoker tongue, jockey ride, charger pummel or carry), a big red bar
appears at the bottom of the screen. Mash the key shown on it to fill the bar; when it's full the special infected
is staggered and lets go. The harder the difficulty, the more presses it takes and the faster the bar drains. If the stagger doesn't free you, the special infected is killed instead (can be turned off).

## Requirements
- Left 4 Dead 2 (Steam, current version 2.2.4.x)
- [MetaMod:Source](https://www.sourcemm.net/downloads.php?branch=stable) and
  [SourceMod](https://www.sourcemod.net/downloads.php?branch=stable) 1.12 installed in L4D2
- Built for **single-player / a listen server you host**. The bar is drawn with the host's `r_screenoverlay`, so on a
  dedicated server or for other players joining you, mashing still frees them but they won't see the bar.
- Only play modded on your own games or servers. Add `-insecure` to the Steam launch options so VAC stays off while
  SourceMod is loaded.

## Install
Copy the `left4dead2` folder from this zip into
`Steam\steamapps\common\Left 4 Dead 2\`, merging folders. That adds:

| File | What it is |
|---|---|
| `addons/sourcemod/plugins/grab_escape.smx` | the plugin |
| `addons/sourcemod/scripting/grab_escape.sp` | its source |
| `addons/grab_escape.vpk` | the bar textures |

Restart the game (the vpk is only read at startup).

## Settings
Written to `left4dead2/cfg/sourcemod/grab_escape.cfg` on first run. Change them there or in the console. The
plugin follows the game's difficulty (`z_difficulty`) live.

| Cvar | Default | Meaning |
|---|---|---|
| `grab_escape_enable` | 1 | turn the mod on/off |
| `grab_escape_key` | use | key to mash: `use` (E), `jump` (SPACE), `attack` (LMB), `attack2` (RMB), `reload` (R), `duck` (CTRL) |
| `grab_escape_presses_easy` / `_normal` / `_hard` / `_expert` | 10 / 18 / 30 / 42 | presses needed to fill the bar on each difficulty |
| `grab_escape_decay_easy` / `_normal` / `_hard` / `_expert` | 2.0 / 3.5 / 6.0 / 8.0 | presses the bar loses per second when you stop mashing |
| `grab_escape_bots` | 0 | 1 = survivor bots break free on their own too |
| `grab_escape_kill_fallback` | 1 | 1 = kill the special infected if the stagger doesn't free you |

Charger: the carry and the slam count as part of the same grab. If the bar fills before the pummel starts, it stays
full and frees you the moment the pummel begins (a stagger during the carry or slam doesn't stop the pummel).

The bar shows the key letter from the default binds; if you've rebound, set `grab_escape_key` to the action, not the
letter.

Admin test command: `sm_ge_fill <player> [0-1]` fills a pinned player's bar (or frees them with no fraction).
Log: `addons/sourcemod/logs/grab_escape.log`.

## Credits
- Made by mariokinsmanjr with Claude (Anthropic) writing the code and textures: built with AI.
- Uses SourceMod / MetaMod:Source and L4D2's own VScript `Stagger`. Bar lettering uses the Impact font rendered to
  textures. No game files are included.

## License
GPL-3.0 (see `LICENSE`), copyright 2026 mariokinsmanjr. SourceMod plugins are linked against SourceMod, which is GPL-3.0.
