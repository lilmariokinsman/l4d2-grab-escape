// Dev-only test helpers for grab_escape. Not part of the release.
#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

static const char g_PinProps[][] = { "m_tongueOwner", "m_pounceAttacker", "m_jockeyAttacker", "m_pummelAttacker", "m_carryAttacker" };

public Plugin myinfo =
{
	name = "Grab Escape lab",
	author = "l4d2-grab-escape",
	description = "Test helpers: pin status, bring a special infected to a survivor",
	version = "0.1.0",
	url = ""
};

public void OnPluginStart()
{
	RegServerCmd("ge_status", Cmd_Status, "List survivors and who pins them");
	RegServerCmd("ge_cexec", Cmd_Cexec, "ge_cexec <userid> <command> - ClientCommand on that client");
	RegServerCmd("ge_bring", Cmd_Bring, "ge_bring <si userid> <survivor userid> - put the SI 120 u in front of the survivor, facing it");
	RegServerCmd("ge_turn", Cmd_Turn, "ge_turn <userid> <degrees> - turn a player's view");
	RegServerCmd("ge_mash", Cmd_Mash, "ge_mash <0|1|2> - press E 10x/s for the carried survivor: 1 from carry start, 2 from carry end");
	RegServerCmd("ge_autofree", Cmd_AutoFree, "ge_autofree <0|1> - log charger carries; with 1, run sm_ge_fill the moment a carry starts");
}

// Carry watcher: logs carry start/end (with duration and what follows) for every survivor
bool g_AutoFree;
bool g_Watch;
int g_Carrier[MAXPLAYERS + 1];
int g_Pummeler[MAXPLAYERS + 1];
float g_CarryStart[MAXPLAYERS + 1];

Action Cmd_AutoFree(int args)
{
	g_Watch = true;
	g_AutoFree = GetCmdArgInt(1) != 0;
	PrintToServer("carry watch on, autofree %d", g_AutoFree);
	return Plugin_Handled;
}

int g_LastBtn[MAXPLAYERS + 1];
int g_MashMode;
float g_MashFrom[MAXPLAYERS + 1];
float g_MashUntil[MAXPLAYERS + 1];

Action Cmd_Mash(int args)
{
	g_MashMode = GetCmdArgInt(1);
	PrintToServer("mash mode %d", g_MashMode);
	return Plugin_Handled;
}

public Action OnPlayerRunCmd(int client, int &buttons)
{
	float now = GetGameTime();
	if (now >= g_MashFrom[client] && now < g_MashUntil[client])
	{
		// 10 presses/s: E down for 0.05 s of every 0.1 s
		if (FloatFraction((now - g_MashFrom[client]) * 10.0) < 0.5)
			buttons |= IN_USE;
		else
			buttons &= ~IN_USE;
	}
	if (g_Watch && (buttons & IN_USE) && !(g_LastBtn[client] & IN_USE))
		LogMessage("press E %N at %.2f s after carry start; stagger %d", client, GetGameTime() - g_CarryStart[client],
			GetEntProp(GetEntPropEnt(client, Prop_Send, "m_pummelAttacker") > 0 ? GetEntPropEnt(client, Prop_Send, "m_pummelAttacker") : client, Prop_Send, "m_zombieClass"));
	g_LastBtn[client] = buttons;
	return Plugin_Continue;
}

public void OnGameFrame()
{
	if (!g_Watch)
		return;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || GetClientTeam(i) != 2)
			continue;
		float now = GetGameTime();
		int pm = GetEntPropEnt(i, Prop_Send, "m_pummelAttacker");
		if (pm != g_Pummeler[i])
		{
			LogMessage("pummel %s %N (%.2f s after carry start)", pm > 0 ? "START" : "END", i, now - g_CarryStart[i]);
			g_Pummeler[i] = pm;
		}
		int c = GetEntPropEnt(i, Prop_Send, "m_carryAttacker");
		if (c == g_Carrier[i])
			continue;
		if (c > 0)
		{
			g_CarryStart[i] = now;
			LogMessage("carry START %N by %N (game time %.2f)", i, c, now);
			if (g_MashMode == 1)
			{
				g_MashFrom[i] = now;
				g_MashUntil[i] = now + 4.0;
			}
			if (g_AutoFree)
				ServerCommand("sm_ge_fill #%d", GetClientUserId(i));
		}
		else if (g_MashMode == 2)
		{
			g_MashFrom[i] = now;
			g_MashUntil[i] = now + 4.0;
		}
		if (c <= 0)
			LogMessage("carry END %N after %.2f s; pummel %d", i, now - g_CarryStart[i], GetEntPropEnt(i, Prop_Send, "m_pummelAttacker"));
		g_Carrier[i] = c;
	}
}

Action Cmd_Status(int args)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
			continue;
		if (GetClientTeam(i) == 3)
		{
			PrintToServer("SI %N userid %d class %d", i, GetClientUserId(i), GetEntProp(i, Prop_Send, "m_zombieClass"));
			continue;
		}
		if (GetClientTeam(i) != 2)
			continue;
		char who[96] = "free";
		for (int p = 0; p < sizeof(g_PinProps); p++)
		{
			int a = GetEntPropEnt(i, Prop_Send, g_PinProps[p]);
			if (a > 0)
				Format(who, sizeof(who), "%s by %N", g_PinProps[p], a);
		}
		PrintToServer("survivor %N userid %d: %s", i, GetClientUserId(i), who);
	}
	return Plugin_Handled;
}

Action Cmd_Bring(int args)
{
	int si = GetClientOfUserId(GetCmdArgInt(1));
	int victim = GetClientOfUserId(GetCmdArgInt(2));
	if (si == 0 || victim == 0)
	{
		PrintToServer("bad userids");
		return Plugin_Handled;
	}
	float pos[3], ang[3], fwd[3];
	GetClientAbsOrigin(victim, pos);
	GetClientEyeAngles(victim, ang);
	ang[0] = 0.0;
	GetAngleVectors(ang, fwd, NULL_VECTOR, NULL_VECTOR);
	float dist = args >= 3 ? GetCmdArgFloat(3) : 120.0;
	pos[0] += fwd[0] * dist;
	pos[1] += fwd[1] * dist;
	pos[2] += 10.0;
	ang[1] += 180.0;
	TeleportEntity(si, pos, ang, view_as<float>({0.0, 0.0, 0.0}));
	bool burning = (GetEntityFlags(si) & FL_ONFIRE) != 0;
	ExtinguishEntity(si);
	SetEntityHealth(si, 600);
	PrintToServer("brought %N to %N (was burning %d, health %d)", si, victim, burning, GetClientHealth(si));
	return Plugin_Handled;
}

Action Cmd_Cexec(int args)
{
	int client = GetClientOfUserId(GetCmdArgInt(1));
	char cmd[256];
	GetCmdArg(2, cmd, sizeof(cmd));
	if (client == 0)
		return Plugin_Handled;
	ClientCommand(client, "%s", cmd);
	PrintToServer("cexec %N: %s (flags %x)", client, cmd, GetCommandFlags("r_screenoverlay"));
	return Plugin_Handled;
}

Action Cmd_Turn(int args)
{
	int client = GetClientOfUserId(GetCmdArgInt(1));
	if (client == 0)
		return Plugin_Handled;
	float ang[3];
	GetClientEyeAngles(client, ang);
	ang[0] = 0.0;
	ang[1] += GetCmdArgFloat(2);
	TeleportEntity(client, NULL_VECTOR, ang, NULL_VECTOR);
	PrintToServer("turned %N to yaw %.0f", client, ang[1]);
	return Plugin_Handled;
}
