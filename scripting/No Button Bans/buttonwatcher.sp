#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <csgocolors_fix>
#include <EntWatch>
#include <clientprefs>

#define MAX_EDICTS 2048

Handle g_hCookie_Buttons = null;
Handle g_hCookie_BConsole = null;

bool g_bButtons[MAXPLAYERS + 1] = {false, ...};
bool g_bConsole[MAXPLAYERS + 1] = {false, ...};

ConVar g_hCvar_ButtonsEnabled;
ConVar g_hCvar_ButtonsTimer;

bool isMapRunning;

int g_aButtons[MAX_EDICTS];
int g_iMaxButtons = 0;

bool g_aTimerButtons[MAX_EDICTS] = {false,...};
float g_fTimerTime = 0.0;

public Plugin myinfo =
{
	name = "Button Watcher [No ButtonBan Version]",
	author = "DarkerZ[RUS], koen",
	description = "Track button interactions with ban functionality",
	version = "2.3",
	url = "https://github.com/darkerz7 & https://github.com/notkoen"
};

public void OnPluginStart()
{
	// Load translations
	LoadTranslations("button_watcher.phrases");
	LoadTranslations("common.phrases");
	
	// Entity hooks
	HookEntityOutput("func_button", "OnPressed", Button_OnPressed);
	HookEntityOutput("momentary_rot_button", "OnPressed", Button_OnPressed);
	HookEntityOutput("func_rot_button", "OnPressed", Button_OnPressed);
	
	// Event hooks
	HookEventEx("round_end", Event_RoundEnd, EventHookMode_Pre);
	
	// CVARs
	g_hCvar_ButtonsEnabled = CreateConVar("sm_buttons_view", "1", "Enable/Disable Global the display Buttons.", _, true, 0.0, true, 1.0);
	g_hCvar_ButtonsTimer = CreateConVar("sm_buttons_timer", "0.0", "Timer before showing the pressed button again(0.0 - Disabled)", _, true, 0.0, true, 10.0);
	HookConVarChange(g_hCvar_ButtonsTimer, Cvar_ButtonsTimer);
	
	// Reg Cookies
	g_hCookie_Buttons = RegClientCookie("buttonwatcher_Buttons", "", CookieAccess_Private);
	g_hCookie_BConsole = RegClientCookie("buttonwatcher_Console", "", CookieAccess_Private);
	
	// Set cookie menu option
	SetCookieMenuItem(CookieHandler, INVALID_HANDLE, "Buttonwatcher Settings");
	
	// Commands
	RegConsoleCmd("sm_buttons", Command_Buttons);
	RegConsoleCmd("sm_bw", Command_Buttons);
}

public void Cvar_ButtonsTimer(ConVar convar, const char[] oldValue, const char[] newValue)
{
	g_fTimerTime = GetConVarFloat(convar);
}


public void CookieHandler(int client, CookieMenuAction action, any info, char[] buffer, int maxlen)
{
	switch (action)
	{
		case CookieMenuAction_SelectOption: ClientSettingsMenu(client);
	}
}

public void ClientSettingsMenu(int client)
{
	Menu menu = CreateMenu(SettingsMenuHandler);
	menu.SetTitle("Button Watcher Settings");
	menu.AddItem("nothing", "", ITEMDRAW_SPACER);
	
	char buffer[64];
	Format(buffer, sizeof(buffer), "Show in Chat: %s", g_bButtons[client] ? "Enabled" : "Disabled");
	menu.AddItem("chat", buffer);
	Format(buffer, sizeof(buffer), "Show in Console: %s", g_bConsole[client] ? "Enabled" : "Disabled");
	menu.AddItem("console", buffer);
	
	SetMenuExitBackButton(menu, false);
	SetMenuExitButton(menu, true);
	menu.Display(client, MENU_TIME_FOREVER);
}

public int SettingsMenuHandler(Handle menu, MenuAction action, int client, int selection)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			char choice[32];
			GetMenuItem(menu, selection, choice, sizeof(choice));
			if (StrEqual(choice, "chat"))
			{
				g_bButtons[client] = !g_bButtons[client];
				CPrintToChat(client, "{orange}[BW] {default}Button watch messages have been %s {default}in chat.", g_bButtons[client] ? "{green}enabled" : "{red}disabled");
			}
			else if (StrEqual(choice, "console"))
			{
				g_bConsole[client] = !g_bConsole[client];
				CPrintToChat(client, "{orange}[BW] {default}Button watch messages have been %s {default}in console.", g_bConsole[client] ? "{green}enabled" : "{red}disabled");
			}
			SaveSettings(client);
			ClientSettingsMenu(client);
		}
		case MenuAction_Cancel: if (selection == MenuCancel_ExitBack) ShowCookieMenu(client);
		case MenuAction_End: CloseHandle(menu);
	}
	return 0;
}

public void OnEntityCreated(int iEntity, const char[] sClassname)
{
	if (StrContains(sClassname, "func_button", false) != -1 && IsValidEntity(iEntity) && isMapRunning)
	{
		SDKHookEx(iEntity, SDKHook_Use, OnButtonUse);
		SDKHookEx(iEntity, SDKHook_OnTakeDamage, OnButtonDamage);
		g_aButtons[g_iMaxButtons] = iEntity;
		g_iMaxButtons++;
	}
	
	if (StrContains(sClassname, "momentary_rot_button", false) != -1 && IsValidEntity(iEntity) && isMapRunning)
	{
		SDKHookEx(iEntity, SDKHook_Use, OnButtonUse);
		SDKHookEx(iEntity, SDKHook_OnTakeDamage, OnButtonDamage);
		g_aButtons[g_iMaxButtons] = iEntity;
		g_iMaxButtons++;
	}
	
	if (StrContains(sClassname, "func_rot_button", false) != -1 && IsValidEntity(iEntity) && isMapRunning)
	{
		SDKHookEx(iEntity, SDKHook_Use, OnButtonUse);
		SDKHookEx(iEntity, SDKHook_OnTakeDamage, OnButtonDamage);
		g_aButtons[g_iMaxButtons] = iEntity;
		g_iMaxButtons++;
	}
}

public void OnMapStart()
{
	g_iMaxButtons = 0;
	isMapRunning = true;
}

public void OnMapEnd()
{
	isMapRunning = false;
}

public void Event_RoundEnd(Event hEvent, const char[] sName, bool bDontBroadcast)
{
	for (int index = 0; index < g_iMaxButtons; index++)
	{
		SDKUnhook(g_aButtons[index], SDKHook_Use, OnButtonUse);
		SDKUnhook(g_aButtons[index], SDKHook_OnTakeDamage, OnButtonDamage);
	}
	g_iMaxButtons = 0;
}

public Action OnButtonUse(int iButton, int iActivator)
{
	if (!IsValidEdict(iButton) || !IsValidClient(iActivator))
	{
		return Plugin_Continue;
	}
	
	if (EntWatch_IsSpecialItem(iButton)) return Plugin_Continue;
	
	return Plugin_Continue;
}

public Action OnButtonDamage(int iButton, int &iActivator)
{
	if (!IsValidEdict(iButton) || !IsValidClient(iActivator))
	{
		return Plugin_Continue;
	}
	
	if (EntWatch_IsSpecialItem(iButton)) return Plugin_Continue;
	
	return Plugin_Continue;
}

public void OnClientCookiesCached(int iClient)
{
	char sBuffer_cookie[32];
	
	// Chat notification
	GetClientCookie(iClient, g_hCookie_Buttons, sBuffer_cookie, sizeof(sBuffer_cookie));
	g_bButtons[iClient] = view_as<bool>(StringToInt(sBuffer_cookie));
	
	// Console notification
	GetClientCookie(iClient, g_hCookie_BConsole, sBuffer_cookie, sizeof(sBuffer_cookie));
	g_bConsole[iClient] = view_as<bool>(StringToInt(sBuffer_cookie));
}

public void OnClientDisconnect(int iClient)
{
	g_bButtons[iClient] = false;
	g_bConsole[iClient] = false;
}

public Action Command_Buttons(int iClient, int iArgs)
{
	if (!IsValidClient(iClient)) return Plugin_Handled;
	ClientSettingsMenu(iClient);
	return Plugin_Handled;
}

public Action Button_OnPressed(const char[] output, int caller, int activator, float delay)
{
	if (!IsValidClient(activator)) return Plugin_Continue;
	if (!g_hCvar_ButtonsEnabled.BoolValue) return Plugin_Continue;
	
	if (g_fTimerTime > 0.0)
	{
		if (g_aTimerButtons[caller] == true) return Plugin_Continue;
	}

	char entity[512];
	GetEntPropString(caller, Prop_Data, "m_iName", entity, sizeof(entity));
	
	float origin[3];
	GetEntPropVector(caller, Prop_Send, "m_vecOrigin", origin);
	
	char clientID_char[64];
	GetClientAuthId(activator, AuthId_Steam2, clientID_char, sizeof(clientID_char));
	
	int clientID = GetClientUserId(activator);

	if (EntWatch_IsSpecialItem(caller)) return Plugin_Continue;
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i)) return Plugin_Continue;
		
		if (g_bButtons[i]) CPrintToChat(i, "%t %t", "Chat Prefix", "Button Press", activator, clientID, caller, entity);
		if (g_bConsole[i])
		{
			PrintToConsole(i, "--------------------< Button Watcher >--------------------");
			PrintToConsole(i, "%t", "Button Press Console 1", activator, clientID_char, clientID, caller, entity);
			PrintToConsole(i, "%t", "Button Press Console 2", origin[0], origin[1], origin[2]);
			PrintToConsole(i, "----------------------------------------------------------");
		}
	}
	
	LogMessage("[BW] %N [%s] pressed button %s [#%i]", activator, clientID_char, entity, caller);
	
	if (g_fTimerTime > 0.0)
	{
		g_aTimerButtons[caller] = true;
		CreateTimer(g_fTimerTime, Timer_End, caller);
	}
	
	return Plugin_Continue;
}

public Action Timer_End(Handle timer, int entity)
{
	g_aTimerButtons[entity] = false;
	return Plugin_Stop;
}

stock bool IsValidClient(int client)
{
	if (!(1 <= client <= MaxClients) || !IsClientInGame(client))
		return false;
	return true;
}

void SaveSettings(int client)
{
	char buffer[8];
	Format(buffer, sizeof(buffer), "%b", g_bButtons[client]);
	SetClientCookie(client, g_hCookie_Buttons, buffer);
	
	Format(buffer, sizeof(buffer), "%b", g_bConsole[client]);
	SetClientCookie(client, g_hCookie_BConsole, buffer);
}