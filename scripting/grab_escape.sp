// Grab Escape: when a special infected pins a survivor, a bar appears; mashing the shown key fills it and a full bar
// makes the special infected let go (L4D2's own stagger, with a kill as fallback if the stagger doesn't break the pin).
// The bar is a screen overlay from addons/grab_escape.vpk (tools/make_bar.py): one texture per key and fill level.
// r_screenoverlay is a client cheat command; on a listen server the host's client shares this cvar registry, so the
// plugin drops FCVAR_CHEAT from it while loaded (remote clients on a dedicated server would still refuse it).
#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define TEAM_SURVIVOR 2
#define BAR_LEVELS 20  // overlay textures bar_<key>_00 .. bar_<key>_20

public Plugin myinfo =
{
	name = "Grab Escape",
	author = "mariokinsmanjr (built with Claude)",
	description = "Mash a key to fill a bar and break free from special infected grabs",
	version = "1.1.0",
	url = ""
};

// Every way a special infected holds a survivor (victim-side netprops)
static const char g_PinProps[][] = { "m_tongueOwner", "m_pounceAttacker", "m_jockeyAttacker", "m_pummelAttacker", "m_carryAttacker" };

ConVar g_cvEnable, g_cvKey, g_cvPresses, g_cvDecay, g_cvBots, g_cvKillFallback;

int g_KeyButton = IN_USE;
char g_KeyId[16] = "use";

int g_Attacker[MAXPLAYERS + 1];
float g_Fill[MAXPLAYERS + 1];
int g_LastButtons[MAXPLAYERS + 1];
float g_ReleasedAt[MAXPLAYERS + 1];
int g_ShownLevel[MAXPLAYERS + 1] = { -1, ... };
float g_KeepUntil[MAXPLAYERS + 1];
int g_OverlayFlags = INVALID_FCVAR_FLAGS;
int g_HelperScript = INVALID_ENT_REFERENCE;
char g_LogPath[PLATFORM_MAX_PATH];

public void OnPluginStart()
{
	g_cvEnable = CreateConVar("grab_escape_enable", "1", "1 = survivors can mash out of special infected grabs", _, true, 0.0, true, 1.0);
	g_cvKey = CreateConVar("grab_escape_key", "use", "Key to mash: use (E), jump (SPACE), attack (LEFT CLICK), attack2 (RIGHT CLICK), reload (R), duck (CTRL)");
	g_cvPresses = CreateConVar("grab_escape_presses", "12", "Presses needed to fill the bar", _, true, 1.0, true, 200.0);
	g_cvDecay = CreateConVar("grab_escape_decay", "1.0", "Presses drained from the bar per second when you stop mashing", _, true, 0.0);
	g_cvBots = CreateConVar("grab_escape_bots", "0", "1 = survivor bots also break free on their own (mash 5 times a second)", _, true, 0.0, true, 1.0);
	g_cvKillFallback = CreateConVar("grab_escape_kill_fallback", "1", "1 = if the stagger doesn't free you, kill the special infected instead", _, true, 0.0, true, 1.0);
	AutoExecConfig(true, "grab_escape");

	g_cvKey.AddChangeHook(OnKeyChanged);
	ApplyKey();

	RegAdminCmd("sm_ge_fill", Cmd_Fill, ADMFLAG_CHEATS, "sm_ge_fill <#userid|name> - fill a pinned survivor's bar (test)");
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	BuildPath(Path_SM, g_LogPath, sizeof(g_LogPath), "logs/grab_escape.log");

	g_OverlayFlags = GetCommandFlags("r_screenoverlay");
	if (g_OverlayFlags != INVALID_FCVAR_FLAGS)
		SetCommandFlags("r_screenoverlay", g_OverlayFlags & ~FCVAR_CHEAT);
	else
		LogToFileEx(g_LogPath, "r_screenoverlay not found: the bar can't be shown (dedicated server?)");
}

public void OnPluginEnd()
{
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && !IsFakeClient(i) && g_ShownLevel[i] != -1)
			ClientCommand(i, "r_screenoverlay 0");
	if (g_OverlayFlags != INVALID_FCVAR_FLAGS)
		SetCommandFlags("r_screenoverlay", g_OverlayFlags);
}

public void OnMapStart()
{
	g_HelperScript = INVALID_ENT_REFERENCE;
	for (int i = 1; i <= MaxClients; i++)
		ResetClient(i);
}

public void OnClientDisconnect(int client)
{
	ResetClient(client);
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_HelperScript = INVALID_ENT_REFERENCE;
	for (int i = 1; i <= MaxClients; i++)
	{
		ClearBar(i);
		ResetClient(i);
	}
}

void ResetClient(int client)
{
	g_Attacker[client] = 0;
	g_Fill[client] = 0.0;
	g_LastButtons[client] = 0;
	g_ReleasedAt[client] = 0.0;
	g_ShownLevel[client] = -1;
	g_KeepUntil[client] = 0.0;
}

void OnKeyChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	ApplyKey();
}

void ApplyKey()
{
	char key[16];
	g_cvKey.GetString(key, sizeof(key));
	if (StrEqual(key, "jump", false))
		SetKey(IN_JUMP, "jump");
	else if (StrEqual(key, "attack", false))
		SetKey(IN_ATTACK, "attack");
	else if (StrEqual(key, "attack2", false))
		SetKey(IN_ATTACK2, "attack2");
	else if (StrEqual(key, "reload", false))
		SetKey(IN_RELOAD, "reload");
	else if (StrEqual(key, "duck", false))
		SetKey(IN_DUCK, "duck");
	else
		SetKey(IN_USE, "use");
	for (int i = 1; i <= MaxClients; i++)
		if (g_ShownLevel[i] != -1)
			g_ShownLevel[i] = -2;  // redraw with the new key's textures
}

void SetKey(int button, const char[] id)
{
	g_KeyButton = button;
	strcopy(g_KeyId, sizeof(g_KeyId), id);
}

int GetPinner(int client)
{
	for (int i = 0; i < sizeof(g_PinProps); i++)
	{
		int attacker = GetEntPropEnt(client, Prop_Send, g_PinProps[i]);
		if (attacker > 0 && attacker <= MaxClients && IsClientInGame(attacker) && IsPlayerAlive(attacker))
			return attacker;
	}
	return 0;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	if (!g_cvEnable.BoolValue || !IsClientInGame(client) || GetClientTeam(client) != TEAM_SURVIVOR || !IsPlayerAlive(client))
	{
		ClearBar(client);
		return Plugin_Continue;
	}

	bool bot = IsFakeClient(client);
	if (bot && !g_cvBots.BoolValue)
		return Plugin_Continue;

	float now = GetGameTime();
	int pinner = GetPinner(client);
	if (pinner != g_Attacker[client])
	{
		g_Attacker[client] = pinner;
		g_Fill[client] = 0.0;
	}
	if (pinner == 0)
	{
		if (now >= g_KeepUntil[client])
			ClearBar(client);
		g_LastButtons[client] = buttons;
		return Plugin_Continue;
	}

	float needed = g_cvPresses.FloatValue;
	if (now - g_ReleasedAt[client] > 0.5)
	{
		bool pressed;
		if (bot)
			pressed = GetURandomFloat() < 5.0 * GetTickInterval();
		else
			pressed = (buttons & g_KeyButton) && !(g_LastButtons[client] & g_KeyButton);

		if (pressed)
			g_Fill[client] += 1.0;
		else
			g_Fill[client] -= g_cvDecay.FloatValue * GetTickInterval();
		if (g_Fill[client] < 0.0)
			g_Fill[client] = 0.0;

		if (g_Fill[client] >= needed)
		{
			Release(client, pinner);
			g_Fill[client] = 0.0;
			g_ReleasedAt[client] = now;
			if (!bot)
			{
				DrawBar(client, 1.0);  // hold the full bar for a moment
				g_KeepUntil[client] = now + 0.6;
			}
		}
	}
	g_LastButtons[client] = buttons;

	if (!bot && now >= g_KeepUntil[client])
		DrawBar(client, g_Fill[client] / needed);
	return Plugin_Continue;
}

void DrawBar(int client, float frac)
{
	if (frac > 1.0)
		frac = 1.0;
	int level = RoundToFloor(frac * BAR_LEVELS);
	if (level == g_ShownLevel[client])
		return;
	g_ShownLevel[client] = level;
	ClientCommand(client, "r_screenoverlay grab_escape/bar_%s_%02d", g_KeyId, level);
}

void ClearBar(int client)
{
	if (g_ShownLevel[client] == -1)
		return;
	g_ShownLevel[client] = -1;
	if (IsClientInGame(client) && !IsFakeClient(client))
		ClientCommand(client, "r_screenoverlay 0");
}

void Release(int victim, int attacker)
{
	float from[3];
	GetClientAbsOrigin(victim, from);
	char code[192];
	Format(code, sizeof(code), "GetPlayerFromUserID(%d).Stagger(Vector(%.1f, %.1f, %.1f))", GetClientUserId(attacker), from[0], from[1], from[2]);
	RunVScript(code);
	LogToFileEx(g_LogPath, "%N broke free from %N (stagger)", victim, attacker);

	DataPack pack;
	CreateDataTimer(0.25, Timer_CheckFreed, pack, TIMER_FLAG_NO_MAPCHANGE);
	pack.WriteCell(GetClientUserId(victim));
	pack.WriteCell(GetClientUserId(attacker));
}

Action Timer_CheckFreed(Handle timer, DataPack pack)
{
	pack.Reset();
	int victim = GetClientOfUserId(pack.ReadCell());
	int attacker = GetClientOfUserId(pack.ReadCell());
	if (victim == 0 || attacker == 0 || !IsPlayerAlive(victim) || !IsPlayerAlive(attacker))
		return Plugin_Stop;
	if (GetPinner(victim) != attacker)
	{
		LogToFileEx(g_LogPath, "  stagger freed %N", victim);
		return Plugin_Stop;
	}
	if (g_cvKillFallback.BoolValue)
	{
		LogToFileEx(g_LogPath, "  stagger did not free %N; killing %N", victim, attacker);
		ForcePlayerSuicide(attacker);
	}
	else
		LogToFileEx(g_LogPath, "  stagger did not free %N (kill fallback off)", victim);
	return Plugin_Stop;
}

void RunVScript(const char[] code)
{
	int ent = EntRefToEntIndex(g_HelperScript);
	if (ent == INVALID_ENT_REFERENCE)
	{
		ent = CreateEntityByName("logic_script");
		if (ent == -1)
			return;
		DispatchSpawn(ent);
		g_HelperScript = EntIndexToEntRef(ent);
	}
	SetVariantString(code);
	AcceptEntityInput(ent, "RunScriptCode");
}

Action Cmd_Fill(int client, int args)
{
	if (args < 1)
	{
		ReplyToCommand(client, "Usage: sm_ge_fill <#userid|name> [fraction 0-1]");
		return Plugin_Handled;
	}
	char arg[64];
	GetCmdArg(1, arg, sizeof(arg));
	int target = FindTarget(client, arg, false, false);
	if (target == -1)
		return Plugin_Handled;
	int pinner = GetPinner(target);
	if (pinner == 0)
	{
		ReplyToCommand(client, "%N is not pinned", target);
		return Plugin_Handled;
	}
	// with a fraction: set the bar to that much (test the overlay); without: break free now
	if (args >= 2)
	{
		g_Fill[target] = GetCmdArgFloat(2) * g_cvPresses.FloatValue;
		ReplyToCommand(client, "%N's bar set to %.2f", target, GetCmdArgFloat(2));
		return Plugin_Handled;
	}
	Release(target, pinner);
	ReplyToCommand(client, "Released %N from %N", target, pinner);
	return Plugin_Handled;
}
