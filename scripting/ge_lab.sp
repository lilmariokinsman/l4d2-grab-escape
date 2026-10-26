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
	pos[0] += fwd[0] * 120.0;
	pos[1] += fwd[1] * 120.0;
	pos[2] += 10.0;
	ang[1] += 180.0;
	TeleportEntity(si, pos, ang, view_as<float>({0.0, 0.0, 0.0}));
	PrintToServer("brought %N to %N", si, victim);
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
