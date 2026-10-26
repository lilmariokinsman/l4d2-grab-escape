# MODLOG: Grab Escape (L4D2) - separate from the Dying Light mod

Idea: when a special infected pins you, a bar shows; each press of the shown key fills it; full bar = SI lets go.
Started 2026-10-26.

## Route
SourceMod plugin, reusing the SourceMod 1.12.0.7253 already installed in L4D2 for dl-parkour-l4d2 (Smart App Control:
use spcomp64.exe). No other dependency (no left4dhooks). Build: `sh build.sh` (compiles + copies to addons/sourcemod/plugins).

## How it works (scripting/grab_escape.sp, v1.1.0)
- Pin detection: victim netprops m_tongueOwner, m_pounceAttacker, m_jockeyAttacker, m_pummelAttacker, m_carryAttacker.
- OnPlayerRunCmd: edge-detected presses of the key add 1; bar drains grab_escape_decay presses/s.
- Bar (user asked: big red bar, big bold lettering, not the game's font): screen overlay textures from
  addons/grab_escape.vpk, built by tools/make_bar.py (Pillow in .venv, Impact font, 1024x256 DXT5, 6 keys x 21 levels,
  33 MB). The VMT's $basetexturetransform puts the texture in the lower middle (REGION); the VTF is clamped with a
  transparent border. The plugin sends `r_screenoverlay grab_escape/bar_<key>_<NN>` with ClientCommand only when the
  level changes, `r_screenoverlay 0` to clear; full bar held 0.6 s after breaking free.
- r_screenoverlay = client ConCommand, flags 0x10004008 (cheat | server_can_execute | clientdll). On a listen server the
  host's client shares the cvar registry, so the plugin drops FCVAR_CHEAT (verified: flags read back 0x10000008 and
  ClientCommand shows the overlay with sv_cheats 0... note sv_cheats was 1 during tests; recheck with 0). Remote clients
  on a dedicated server would refuse it.
- Release: VScript `GetPlayerFromUserID(attacker).Stagger(victim origin)`; 0.25 s later, if still pinned and
  grab_escape_kill_fallback 1, ForcePlayerSuicide(attacker). Log: addons/sourcemod/logs/grab_escape.log.
- Cvars (cfg/sourcemod/grab_escape.cfg): grab_escape_enable, _key (use/jump/attack/attack2/reload/duck),
  _presses 12, _decay 1.0, _bots 0, _kill_fallback 1. Test cmd: sm_ge_fill <target> [fraction].
- Dev-only scripting/ge_lab.sp (not for release): ge_status, ge_bring <si uid> <surv uid>, ge_cexec <uid> <cmd>.
  Driven through dl-parkour's lab bridge (dlp_lab.smx, data/dlp_cmd.txt). Console `script` splits on ';', so use ge_lab.

## Verified in game 2026-10-26 (L4D2 2.2.4.3, c1m1_hotel, sv_cheats 1, god 1)
- Stagger ALONE frees all four: hunter (pounce), jockey, smoker (tongue), charger (pummel); the SI survives. Kill
  fallback never fired. Charger carry (mid-charge) not tested.
- Real E presses from the user freed their survivor 8 times (log 02:37-02:39) = mashing works with real input.
- Overlay renders as designed (screenshots). The game's "Pummeled! A teammate must help..." text sat on the key cap at
  y 0.60-0.86 -> REGION moved to y 0.71-0.95; rebuilt build/grab_escape.vpk but NOT installed (game locks the vpk).
- User rule: test with ONLY the user's survivor (survivor_limit 1, kick bots, check status again after ~10 s: bots
  join late after map load).

## Next
1. Game closed -> `.venv/Scripts/python.exe tools/make_bar.py --vpk --install`, relaunch, check bar position.
2. Check overlay with sv_cheats 0. 3. User feel-test of presses/decay. 4. Remove ge_lab.smx from plugins for release.

## 2026-10-26 later
- New vpk (REGION y 0.71-0.95) installed + game relaunched. VERIFIED with sv_cheats 0: hunter pin shows the overlay
  bar, clear of the game's "Pinned! A teammate must help..." line (screenshot). Next 1 and 2 above are done.
- Still open: user feel-test of presses/decay; charger carry; remove ge_lab.smx from plugins before release.

## Release packaging (2026-10-26 12:40)
- README.md (install, cvars, listen-server-only bar, AI disclosure) + package.sh -> release/grab_escape-1.1.0.zip (2 MB;
  vpk compresses 31 -> ~2 MB). Layout: left4dead2/addons/{grab_escape.vpk, sourcemod/plugins/grab_escape.smx,
  sourcemod/scripting/grab_escape.sp}. ge_lab never packaged.
- `um publish check`: 2 FAILs are false positives (the release files equal the installed copies of this same mod);
  vpk listing = addoninfo.txt + materials/grab_escape/bar_* only. Project put under git (build/, release/, .venv ignored).
- Still open: user feel-test (presses/decay), charger CARRY test, then delete ge_lab.smx from the game's plugins folder.

## v1.2.0 charger carry + difficulty (2026-10-26 12:4x-13:02)
- Measured (ge_lab carry watcher): carry lasts 0.09-0.56 s, then a slam with NO pin netprop set, pummel starts
  0.77-0.89 s after carry start. server.dll only has m_carryAttacker/Victim, m_pummelAttacker/Victim (no queued prop).
- Old bug: fill reset + bar flicker in that gap; and the 0.25 s "freed" check was fooled by the gap.
- Fix: grace CARRY_GRACE 1.5 s keeps the same charger as pinner after a carry. VERIFIED test A (12 presses at 10/s from
  carry start): released 1.20 s after carry start, pummel started 1.03 s -> no presses lost.
- Measured: a Stagger during the slam does NOT stop the pummel (release at 342.93, pummel began anyway 0.56 s later).
  So a charger bar that fills before the pummel is held full (no drain) and fires at pummel start. VERIFIED: carry start
  193.20, pummel start ~194.09, release 194.10, pummel ended 0.04 s later, "stagger freed".
- Difficulty (user request): grab_escape_presses_/decay_<easy|normal|hard|expert>, defaults 8/12/20/30 and
  1.0/2.0/3.5/5.0, read from z_difficulty every tick. Old grab_escape_presses/decay removed; cfg regenerated (old cfg
  backed up in the session scratchpad). VERIFIED cvars live in game.
- Lab: ge_lab got ge_autofree/ge_mash/ge_turn, ge_bring <si> <surv> [dist] (extinguish + 600 hp). z_spawn chargers went
  passive with dlp_parkour loaded and attacked once it was unloaded (1 sample each) -> noted in dl-parkour MODLOG.
- User came back mid-test and found the bar full after 3 clicks = my test setting presses 2. Restored.
- Open: user feel-test of the difficulty numbers; delete ge_lab.smx from plugins before release; rebuild zip (package.sh).
- Feel-test (user, 13:1x): 8/12/20/30 "too easy"; 15/25/35/50 with drain 3/5/7/9 "better, but pretty difficult for low
  difficulty" -> CHOSEN easy 10 (drain 2.0), normal 18 (3.5), hard 35 (7.0), expert 50 (9.0). Set in plugin defaults,
  the game's cfg/sourcemod/grab_escape.cfg and live. Awaiting the user's next feel-test.
- User: harder ones a little easier too -> hard 30 (drain 6.0), expert 42 (8.0). CHOSEN, live + cfg + defaults.
- User: "sweet that's better" -> difficulty numbers final (10/18/30/42, drain 2/3.5/6/8).

## Release 1.2.0 (2026-10-26 13:05)
- ge_lab.smx unloaded and deleted from the game's plugins folder (copy stays in build/; source in scripting/).
- release/grab_escape-1.2.0.zip built by package.sh. `um publish check`: same 2 false-positive FAILs as 1.1.0 (the files
  equal the installed copies of this mod); vpk = addoninfo + materials/grab_escape/bar_* only.
- Not done: uploading anywhere (ask the user where: Nexus / GitHub / Steam Workshop needs a different packaging).
