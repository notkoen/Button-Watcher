#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <csgocolors_fix>
#include <clientprefs>
#include <EntWatch>
#include <adminmenu>

#define MAX_EDICTS 2048

Handle g_hCookie_BBans = null;
Handle g_hCookie_BBansLength = null;
Handle g_hCookie_BBansIssued = null;
Handle g_hCookie_BBansBy = null;
Handle g_hCookie_Buttons = null;
Handle g_hCookie_BConsole = null;

bool g_bBBans[MAXPLAYERS + 1] = {false, ...};
char g_sBBansBy[MAXPLAYERS + 1][64];
int g_iBBansLength[MAXPLAYERS + 1], g_iBBansIssued[MAXPLAYERS + 1];
bool g_bButtons[MAXPLAYERS + 1] = {false, ...};
bool g_bConsole[MAXPLAYERS + 1] = {false, ...};

Handle g_hAdminMenu;

int g_iAdminMenuTarget[MAXPLAYERS + 1];

ConVar g_hCvar_ButtonsEnabled;
ConVar g_hCvar_ButtonsTimer;

bool isMapRunning;

int g_aButtons[MAX_EDICTS];
int g_iMaxButtons = 0;

bool g_aTimerButtons[MAX_EDICTS] = {false,...};
float g_fTimerTime = 0.0;

public Plugin myinfo =
{
	name = "Button Watcher",
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
	g_hCookie_BBans = RegClientCookie("buttonwatcher_BBans", "", CookieAccess_Private);
	g_hCookie_BBansLength = RegClientCookie("buttonwatcher_BBanslength", "", CookieAccess_Private);
	g_hCookie_BBansIssued = RegClientCookie("buttonwatcher_BBansissued", "", CookieAccess_Private);
	g_hCookie_BBansBy = RegClientCookie("buttonwatcher_BBansby", "", CookieAccess_Private);
	g_hCookie_Buttons = RegClientCookie("buttonwatcher_Buttons", "", CookieAccess_Private);
	g_hCookie_BConsole = RegClientCookie("buttonwatcher_Console", "", CookieAccess_Private);
	
	// Set cookie menu option
	SetCookieMenuItem(CookieHandler, INVALID_HANDLE, "Buttonwatcher Settings");
	
	// Commands
	RegAdminCmd("sm_bban", Command_BBan, ADMFLAG_BAN);
	RegAdminCmd("sm_bunban", Command_UnBBan, ADMFLAG_BAN);
	RegAdminCmd("sm_bbanlist", Command_BBanlist, ADMFLAG_BAN);
	
	RegConsoleCmd("sm_bstatus", Command_BStat);
	RegConsoleCmd("sm_buttons", Command_Buttons);
	RegConsoleCmd("sm_bw", Command_Buttons);
	
	// Timer for unbban
	CreateTimer(30.0, TimerClientUnBBanCheck, _, TIMER_REPEAT);
	
	// Menu
	Handle hTopMenu;

	if (LibraryExists("adminmenu") && ((hTopMenu = GetAdminTopMenu()) != INVALID_HANDLE))
	{
		OnAdminMenuReady(hTopMenu);
	}
}

public void Cvar_ButtonsTimer(ConVar convar, const char[] oldValue, const char[] newValue)
{
	g_fTimerTime = GetConVarFloat(convar);
}

public void OnLibraryRemoved(const char[] sName)
{
	if (strcmp(sName, "adminmenu") == 0) g_hAdminMenu = INVALID_HANDLE;
}

public void OnAdminMenuReady(Handle hAdminMenu)
{
	if (hAdminMenu == g_hAdminMenu) return;

	g_hAdminMenu = hAdminMenu;

	TopMenuObject hMenuObj = AddToTopMenu(g_hAdminMenu, "Buttons_commands", TopMenuObject_Category, AdminMenu_Commands_Handler, INVALID_TOPMENUOBJECT);

	switch (hMenuObj)
	{
		case INVALID_TOPMENUOBJECT: return;
	}

	AddToTopMenu(g_hAdminMenu, "Buttons_banlist", TopMenuObject_Item, Handler_BBanList, hMenuObj, "sm_bbanlist", ADMFLAG_BAN);
	AddToTopMenu(g_hAdminMenu, "Buttons_ban", TopMenuObject_Item, Handler_BBan, hMenuObj, "sm_bban", ADMFLAG_BAN);
	AddToTopMenu(g_hAdminMenu, "Buttons_unban", TopMenuObject_Item, Handler_UnBBan, hMenuObj, "sm_unbban", ADMFLAG_BAN);
}

public void AdminMenu_Commands_Handler(Handle hMenu, TopMenuAction hAction, TopMenuObject hObjID, int client, char[] sBuffer, int iMaxlen)
{
	switch (hAction)
	{
		case TopMenuAction_DisplayOption: Format(sBuffer, iMaxlen, "%s", "Button Watcher Commands", client);
		case TopMenuAction_DisplayTitle: Format(sBuffer, iMaxlen, "%s", "[BW] Admin Commands:", client);
	}
}

public void Handler_BBanList(Handle hMenu, TopMenuAction hAction, TopMenuObject hObjID, int client, char[] sBuffer, int iMaxlen)
{
	switch (hAction)
	{
		case TopMenuAction_DisplayOption: Format(sBuffer, iMaxlen, "%s", "List Button Banned Players", client);
		case TopMenuAction_SelectOption: Menu_BBan_List(client);
	}
}

public void Handler_BBan(Handle hMenu, TopMenuAction hAction, TopMenuObject hObjID, int client, char[] sBuffer, int iMaxlen)
{
	switch (hAction)
	{
		case TopMenuAction_DisplayOption: Format(sBuffer, iMaxlen, "%s", "Button Ban a Player", client);
		case TopMenuAction_SelectOption: Menu_BBan(client);
	}
}

public void Handler_UnBBan(Handle hMenu, TopMenuAction hAction, TopMenuObject hObjID, int client, char[] sBuffer, int iMaxlen)
{
	switch (hAction)
	{
		case TopMenuAction_DisplayOption: Format(sBuffer, iMaxlen, "%s", "Button Unban a Player", client);
		case TopMenuAction_SelectOption: Menu_UnBBan(client);
	}
}

void Menu_BBan_List(int iClient)
{
	int iBannedClients;

	Menu hListMenu = CreateMenu(MenuHandler_Menu_BBan_List);
	hListMenu.SetTitle("[BW] Button Banned Players:");
	hListMenu.ExitBackButton = true;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i)) continue;
		if (g_bBBans[i])
		{
			int iUserID = GetClientUserId(i);
			char sUserID[12], sBuff[64];
			
			Format(sUserID, sizeof(sUserID), "%d", iUserID);
			Format(sBuff, sizeof(sBuff), "%N (#%i)", i, GetClientUserId(i));
			hListMenu.AddItem(sUserID, sBuff);
			iBannedClients++;
		}
	}

	if (!iBannedClients) hListMenu.AddItem("", "No Button Banned Players", ITEMDRAW_DISABLED);

	hListMenu.Display(iClient, MENU_TIME_FOREVER);
}

public int MenuHandler_Menu_BBan_List(Menu hMenu, MenuAction hAction, int client, int selection)
{
	switch (hAction)
	{
		case MenuAction_End: delete hMenu;
		case MenuAction_Cancel:
		{
			if (selection == MenuCancel_ExitBack && g_hAdminMenu != INVALID_HANDLE)
			{
				DisplayTopMenu(g_hAdminMenu, client, TopMenuPosition_LastCategory);
			}
		}
		case MenuAction_Select:
		{
			char sOption[32];
			hMenu.GetItem(selection, sOption, sizeof(sOption));
			int iTarget = GetClientOfUserId(StringToInt(sOption));

			if (iTarget != 0) Menu_BBan_ListTarget(client, iTarget);
			else
			{
				CPrintToChat(client, "%t %t", "Chat Prefix", "BBan No Available");
				if (g_hAdminMenu != INVALID_HANDLE) DisplayTopMenu(g_hAdminMenu, client, TopMenuPosition_LastCategory);
				else delete hMenu;
			}
		}
	}
	return 0;
}

void Menu_BBan_ListTarget(int iClient, int iTarget)
{
	Menu hListTargetMenu = CreateMenu(MenuHandler_Menu_BBan_ListTarget);
	hListTargetMenu.SetTitle("[BW] Buttons Banned Client: %N", iTarget);
	hListTargetMenu.ExitBackButton = true;

	char sBanExpiryDate[64], sBanIssuedDate[64], sBanDuration[64], sBannedBy[64], sUserID[15];
	int iBanExpiryDate = g_iBBansLength[iTarget] * 60 + g_iBBansIssued[iTarget];
	int iBanIssuedDate = g_iBBansIssued[iTarget];
	int iBanDuration = g_iBBansLength[iTarget];
	int iUserID = GetClientUserId(iTarget);

	Format(sUserID, sizeof(sUserID), "%d", iUserID);

	if (g_bBBans[iTarget])
	{
		if (iBanDuration == -1)
		{
			Format(sBanDuration, sizeof(sBanDuration), "Duration: Temporary");
			Format(sBanExpiryDate, sizeof(sBanExpiryDate), "Expires: On Map Change");
		}
		
		if (iBanDuration == 0)
		{
			Format(sBanDuration, sizeof(sBanDuration), "Duration: Permanent");
			Format(sBanExpiryDate, sizeof(sBanExpiryDate), "Expires: Never");
		}
		
		if (iBanDuration > 0)
		{
			Format(sBanDuration, sizeof(sBanDuration), "Duration: %i Minute%s", iBanDuration, iBanDuration > 1 ? "s" : "");
			char sBufTime[32];
			FormatTime(sBufTime, sizeof(sBufTime), "%m/%d/%Y | %H:%M",iBanExpiryDate);
			Format(sBanExpiryDate, sizeof(sBanExpiryDate), "Expires: %s", sBufTime);
		}
	}
	
	char sBufTimeIss[32];
	if (!(iBanIssuedDate == 0)) FormatTime(sBufTimeIss, sizeof(sBufTimeIss), "%m/%d/%Y | %H:%M",iBanIssuedDate);
	else Format(sBufTimeIss, sizeof(sBufTimeIss), "Unknown");
	
	Format(sBanIssuedDate, sizeof(sBanIssuedDate), "Issued on: %s", sBufTimeIss);
	Format(sBannedBy, sizeof(sBannedBy), "Admin: %s", g_sBBansBy[iTarget][0] ? g_sBBansBy[iTarget]:"Unknown");

	hListTargetMenu.AddItem("", sBannedBy, ITEMDRAW_DISABLED);
	hListTargetMenu.AddItem("", sBanIssuedDate, ITEMDRAW_DISABLED);
	hListTargetMenu.AddItem("", sBanExpiryDate, ITEMDRAW_DISABLED);
	hListTargetMenu.AddItem("", sBanDuration, ITEMDRAW_DISABLED);
	hListTargetMenu.AddItem("", "", ITEMDRAW_SPACER);
	hListTargetMenu.AddItem(sUserID, "Unban");

	hListTargetMenu.Display(iClient, MENU_TIME_FOREVER);
}

public int MenuHandler_Menu_BBan_ListTarget(Menu hMenu, MenuAction hAction, int client, int selection)
{
	switch (hAction)
	{
		case MenuAction_End: delete hMenu;
		case MenuAction_Cancel: if (selection == MenuCancel_ExitBack) Menu_BBan_List(client);
		case MenuAction_Select:
		{
			char sOption[32];
			hMenu.GetItem(selection, sOption, sizeof(sOption));
			int iTarget = GetClientOfUserId(StringToInt(sOption));

			if (iTarget != 0) UnBBanClient(iTarget, client);
			else
			{
				CPrintToChat(client, "%t %t", "Chat Prefix", "BBan No Available");
				Menu_BBan_List(client);
			}
		}
	}
	return 0;
}

void Menu_BBan(int iClient)
{
	Menu hBBanMenu = CreateMenu(MenuHandler_Menu_BBan);
	hBBanMenu.SetTitle("[BW] Button Ban a Player:");
	hBBanMenu.ExitBackButton = true;
	AddTargetsToMenu2(hBBanMenu, iClient, COMMAND_FILTER_NO_BOTS|COMMAND_FILTER_CONNECTED);

	hBBanMenu.Display(iClient, MENU_TIME_FOREVER);
}

public int MenuHandler_Menu_BBan(Menu hMenu, MenuAction hAction, int client, int selection)
{
	switch (hAction)
	{
		case MenuAction_End: delete hMenu;
		case MenuAction_Cancel:
		{
			if (selection == MenuCancel_ExitBack && g_hAdminMenu != INVALID_HANDLE)
			{
				DisplayTopMenu(g_hAdminMenu, client, TopMenuPosition_LastCategory);
			}
		}
		case MenuAction_Select:
		{
			char sOption[32];
			hMenu.GetItem(selection, sOption, sizeof(sOption));
			int iTarget = GetClientOfUserId(StringToInt(sOption));

			if (iTarget != 0) Menu_BBanTime(client, iTarget);
			else
			{
				CPrintToChat(client, "%t %t", "Chat Prefix", "BBan No Available");
				if (g_hAdminMenu != INVALID_HANDLE) DisplayTopMenu(g_hAdminMenu, client, TopMenuPosition_LastCategory);
				else delete hMenu;
			}
		}
	}
	return 0;
}

void Menu_BBanTime(int iClient, int iTarget)
{
	Menu hBBanMenuTime = CreateMenu(MenuHandler_Menu_BBanTime);
	hBBanMenuTime.SetTitle("[BW] Set Ban Duration for %N:", iTarget);
	hBBanMenuTime.ExitBackButton = true;

	g_iAdminMenuTarget[iClient] = iTarget;
	hBBanMenuTime.AddItem("-1", "Temporary");
	hBBanMenuTime.AddItem("10", "10 Minutes");
	hBBanMenuTime.AddItem("30", "30 Minutes");
	hBBanMenuTime.AddItem("60", "1 Hour");
	hBBanMenuTime.AddItem("360", "6 Hours");
	hBBanMenuTime.AddItem("720", "12 Hours");
	hBBanMenuTime.AddItem("1440", "1 Day");
	hBBanMenuTime.AddItem("4320", "3 Days");
	hBBanMenuTime.AddItem("10080", "1 Week");
	hBBanMenuTime.AddItem("20160", "2 Week");
	hBBanMenuTime.AddItem("40320", "1 Month");
	hBBanMenuTime.AddItem("0", "Permanent");

	hBBanMenuTime.Display(iClient, MENU_TIME_FOREVER);
}

public int MenuHandler_Menu_BBanTime(Menu hMenu, MenuAction hAction, int client, int selection)
{
	switch (hAction)
	{
		case MenuAction_End: delete hMenu;
		case MenuAction_Cancel: if (selection == MenuCancel_ExitBack) Menu_BBan(client);
		case MenuAction_Select:
		{
			char sOption[64];
			hMenu.GetItem(selection, sOption, sizeof(sOption));
			int iTarget = g_iAdminMenuTarget[client];

			if (iTarget != 0)
			{
				if (strcmp(sOption, "-1") == 0) BBanClient(iTarget, "-1", client);
				else if (strcmp(sOption, "0") == 0) BBanClient(iTarget, "0", client);
				else BBanClient(iTarget, sOption, client);
			}
			else
			{
				CPrintToChat(client, "%t %t", "Chat Prefix", "BBan No Available");
				Menu_BBan(client);
			}
		}
	}
	return 0;
}

void Menu_UnBBan(int iClient)
{
	int iBannedClients;

	Menu hUnBBanMenu = CreateMenu(MenuHandler_Menu_UnBBan);
	hUnBBanMenu.SetTitle("[BW] Button Unban a Client:");
	hUnBBanMenu.ExitBackButton = true;

	for (int i = 1; i < MaxClients + 1; i++)
	{
		if (!IsClientInGame(i)) continue;
		
		if (g_bBBans[i])
		{
			if (g_iBBansLength[i] == -1)
			{
				int iUserID = GetClientUserId(i);
				char sUserID[12], sBuff[64];
				Format(sBuff, sizeof(sBuff), "%N (#%i) [T]", i, iUserID);
				Format(sUserID, sizeof(sUserID), "%d", iUserID);
				
				hUnBBanMenu.AddItem(sUserID, sBuff);
				iBannedClients++;
			}
			if (g_iBBansLength[i] == 0)
			{
				int iUserID = GetClientUserId(i);
				char sUserID[12], sBuff[64];
				Format(sBuff, sizeof(sBuff), "%N (#%i) [P]", i, iUserID);
				Format(sUserID, sizeof(sUserID), "%d", iUserID);
				
				hUnBBanMenu.AddItem(sUserID, sBuff);
				iBannedClients++;
			}
			if (g_iBBansLength[i] > 0)
			{
				int iTLeft = (g_iBBansLength[i] * 60 + g_iBBansIssued[i] - GetTime()) / 60;
				if (iTLeft < 0) iTLeft = 0;
				
				int iUserID = GetClientUserId(i);
				char sUserID[12], sBuff[64];
				Format(sBuff, sizeof(sBuff), "%N (#%i)[L:%i]", i, iUserID, iTLeft);
				Format(sUserID, sizeof(sUserID), "%d", iUserID);
				
				hUnBBanMenu.AddItem(sUserID, sBuff);
				iBannedClients++;
			}
		}
	}

	if (!iBannedClients) hUnBBanMenu.AddItem("", "No Banned Clients.", ITEMDRAW_DISABLED);
	hUnBBanMenu.Display(iClient, MENU_TIME_FOREVER);
}

public int MenuHandler_Menu_UnBBan(Menu hMenu, MenuAction hAction, int client, int selection)
{
	switch (hAction)
	{
		case MenuAction_End: delete hMenu;
		case MenuAction_Cancel:
		{
			if (selection == MenuCancel_ExitBack && g_hAdminMenu != INVALID_HANDLE)
			{
				DisplayTopMenu(g_hAdminMenu, client, TopMenuPosition_LastCategory);
			}
		}
		case MenuAction_Select:
		{
			char sOption[32];
			hMenu.GetItem(selection, sOption, sizeof(sOption));
			int iTarget = GetClientOfUserId(StringToInt(sOption));

			if (iTarget != 0) UnBBanClient(iTarget, client);
			else
			{
				CPrintToChat(client, "%t %t", "Chat Prefix", "BBan No Available");
				if (g_hAdminMenu != INVALID_HANDLE) DisplayTopMenu(g_hAdminMenu, client, TopMenuPosition_LastCategory);
				else delete hMenu;
			}
		}
	}
	return 0;
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
	if (g_bBBans[iActivator]) return Plugin_Handled;
	
	return Plugin_Continue;
}

public Action OnButtonDamage(int iButton, int &iActivator)
{
	if (!IsValidEdict(iButton) || !IsValidClient(iActivator))
	{
		return Plugin_Continue;
	}
	
	if (EntWatch_IsSpecialItem(iButton)) return Plugin_Continue;
	if (g_bBBans[iActivator]) return Plugin_Handled;
	
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
	
	// Banned
	GetClientCookie(iClient, g_hCookie_BBans, sBuffer_cookie, sizeof(sBuffer_cookie));
	g_bBBans[iClient] = view_as<bool>(StringToInt(sBuffer_cookie));

	// Length ban
	GetClientCookie(iClient, g_hCookie_BBansLength, sBuffer_cookie, sizeof(sBuffer_cookie));
	g_iBBansLength[iClient] = StringToInt(sBuffer_cookie);

	// Time ban
	GetClientCookie(iClient, g_hCookie_BBansIssued, sBuffer_cookie, sizeof(sBuffer_cookie));
	g_iBBansIssued[iClient] = StringToInt(sBuffer_cookie);

	// Who banned
	GetClientCookie(iClient, g_hCookie_BBansBy, sBuffer_cookie, sizeof(sBuffer_cookie));
	Format(g_sBBansBy[iClient], sizeof(g_sBBansBy[]), "%s", sBuffer_cookie);
	
	// Unban if time is expired
	if (g_bBBans[iClient])
	{
		if (g_iBBansLength[iClient] > 0)
		{
			if ((g_iBBansIssued[iClient] + (g_iBBansLength[iClient] * 60)) < GetTime())
			{
				g_bBBans[iClient] = false;
				g_iBBansLength[iClient] = -1;
				g_iBBansIssued[iClient] = 0;
				g_sBBansBy[iClient][0] = '\0';
				
				SetClientCookie(iClient, g_hCookie_BBans, "0");
				SetClientCookie(iClient, g_hCookie_BBansLength, "-1");
				SetClientCookie(iClient, g_hCookie_BBansIssued, "0");
				SetClientCookie(iClient, g_hCookie_BBansBy, "");
				
				LogMessage("[BW] Unbanned button presses for \"%L\" (Expired)", iClient);
			}
		}
	}
}

public void OnClientDisconnect(int iClient)
{
	g_bButtons[iClient] = false;
	g_bConsole[iClient] = false;
	g_bBBans[iClient] = false;
	g_iBBansLength[iClient] = -1;
	g_iBBansIssued[iClient] = 0;
	g_sBBansBy[iClient][0] = '\0';
}

public void BBanClient(int iClient, const char[] sLength, int iAdmin)
{
	int iBanLen = StringToInt(sLength);
	
	if (iAdmin != 0)
	{
		char sAdminSID[64];
		GetClientAuthId(iAdmin, AuthId_Steam2, sAdminSID, sizeof(sAdminSID));
		Format(g_sBBansBy[iClient], sizeof(g_sBBansBy[]), "%N [%s]", iAdmin, sAdminSID);
		SetClientCookie(iClient, g_hCookie_BBansBy, sAdminSID);
	}
	else
	{
		Format(g_sBBansBy[iClient], sizeof(g_sBBansBy[]), "Console");
		SetClientCookie(iClient, g_hCookie_BBansBy, "Console");
	}
	
	// Length ban
	if (iBanLen == -1) // Temporarily
	{
		SetClientCookie(iClient, g_hCookie_BBans, "0");
		SetClientCookie(iClient, g_hCookie_BBansLength, "-1");
		
		g_bBBans[iClient] = true;
		g_iBBansLength[iClient] = -1;
		
		LogAction(iAdmin, iClient, "\"%L\" banned button presses \"%L\"", iAdmin, iClient);
		CPrintToChatAll("%t %t", "Chat Prefix", "BBan Temp", iAdmin, iClient);
	}
	else if (iBanLen == 0) // Permanently
	{
		SetClientCookie(iClient, g_hCookie_BBans, "1");
		SetClientCookie(iClient, g_hCookie_BBansLength, "0");
		
		g_bBBans[iClient] = true;
		g_iBBansLength[iClient] = 0;
		
		LogAction(iAdmin, iClient, "[BW] \"%L\" banned button presses \"%L\" permanently", iAdmin, iClient);
		CPrintToChatAll("%t %t", "Chat Prefix", "BBan Perm", iAdmin, iClient);
	}
	else
	{
		SetClientCookie(iClient, g_hCookie_BBans, "1");
		SetClientCookie(iClient, g_hCookie_BBansLength, sLength);
		
		g_bBBans[iClient] = true;
		g_iBBansLength[iClient] = iBanLen;
		LogAction(iAdmin, iClient, "[BW] \"%L\" banned button presses for \"%L\" for %d minute%s", iAdmin, iClient, iBanLen, iBanLen > 1 ? "s" : "");
		CPrintToChatAll("%t %t", "Chat Prefix", "BBan Time", iAdmin, iClient, iBanLen, iBanLen > 1 ? "s" : "");
	}
	
	// Time ban
	char sIssueTime[64];
	Format(sIssueTime, sizeof(sIssueTime), "%d", GetTime());
	SetClientCookie(iClient, g_hCookie_BBansIssued, sIssueTime);
	g_iBBansIssued[iClient] = GetTime();
}

public void UnBBanClient(int iClient, int iAdmin)
{
	g_bBBans[iClient] = false;
	g_iBBansLength[iClient] = -1;
	g_iBBansIssued[iClient] = 0;
	g_sBBansBy[iClient][0] = '\0';
	
	SetClientCookie(iClient, g_hCookie_BBans, "0");
	SetClientCookie(iClient, g_hCookie_BBansLength, "-1");
	SetClientCookie(iClient, g_hCookie_BBansIssued, "0");
	SetClientCookie(iClient, g_hCookie_BBansBy, "");

	CPrintToChatAll("%t %t", "Chat Prefix","BBan Unban", iAdmin, iClient);
	LogAction(iAdmin, iClient, "\"%L\" Unbanned button presses \"%L\"", iAdmin, iClient);
}

public Action TimerClientUnBBanCheck(Handle hTimer)
{
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IsClientInGame(iClient)) continue;
		if (!g_bBBans[iClient]) continue;
		if (g_iBBansLength[iClient] < 0) continue;
		
		if ((g_iBBansIssued[iClient] + (g_iBBansLength[iClient] * 60)) < GetTime())
		{
			g_bBBans[iClient] = false;
			g_iBBansLength[iClient] = -1;
			g_iBBansIssued[iClient] = 0;
			g_sBBansBy[iClient][0] = '\0';
			
			SetClientCookie(iClient, g_hCookie_BBans, "0");
			SetClientCookie(iClient, g_hCookie_BBansLength, "-1");
			SetClientCookie(iClient, g_hCookie_BBansIssued, "0");
			SetClientCookie(iClient, g_hCookie_BBansBy, "");
			
			CPrintToChat(iClient, "%t %t", "Chat Prefix", "BBan Unban TimeLeft");
			LogMessage("[BW] Unbanned button presses for \"%L\" (Timeleft)", iClient);
		}
	}
	return Plugin_Continue;
}

public Action Command_BBan(int iClient, int iArgs)
{
	if (GetCmdArgs() < 1)
	{
		CReplyToCommand(iClient, "{orange}[BW] {default}Usage: sm_bban <target> [time in minutes]");
		return Plugin_Handled;
	}

	char sTarget_argument[64];
	GetCmdArg(1, sTarget_argument, sizeof(sTarget_argument));

	int iTarget = -1;
	if ((iTarget = FindTarget(iClient, sTarget_argument, true)) == -1)
	{
		return Plugin_Handled;
	}

	if (GetCmdArgs() > 1)
	{
		char sLen[64];
		GetCmdArg(2, sLen, sizeof(sLen));

		if (StringToInt(sLen) <= -1) BBanClient(iTarget, "-1", iClient);
		else if (StringToInt(sLen) == 0) BBanClient(iTarget, "0", iClient);
		else BBanClient(iTarget, sLen, iClient);
		return Plugin_Handled;
	}

	BBanClient(iTarget, "0", iClient);
	return Plugin_Handled;
}

public Action Command_UnBBan(int iClient, int iArgs)
{
	if (iArgs != 1)
	{
		CReplyToCommand(iClient, "{orange}[BW] {default}Usage: sm_unbban <target>");
		return Plugin_Handled;
	}

	char sTarget_argument[64];
	GetCmdArg(1, sTarget_argument, sizeof(sTarget_argument));

	int iTarget = -1;
	if ((iTarget = FindTarget(iClient, sTarget_argument, true)) == -1)
	{
		return Plugin_Handled;
	}

	UnBBanClient(iTarget, iClient);
	return Plugin_Handled;
}

public Action Command_BStat(int iClient, int iArgs)
{
	if (!g_bBBans[iClient])
	{
		CPrintToChat(iClient, "%t %t", "Chat Prefix", "BBan You Unbanned");
		return Plugin_Handled;
	}
	
	if (g_iBBansLength[iClient] == -1)
	{
		CPrintToChat(iClient, "%t %t", "Chat Prefix", "BBan Status Temp", g_sBBansBy[iClient]);
		return Plugin_Handled;
	}
	
	if (g_iBBansLength[iClient] == 0)
	{
		CPrintToChat(iClient, "%t %t", "Chat Prefix", "BBan Status Perm", g_sBBansBy[iClient]);
		return Plugin_Handled;
	}
	
	if (g_iBBansLength[iClient] > 0)
	{
		CPrintToChat(iClient, "%t %t", "Chat Prefix", "BBan Status", g_iBBansLength[iClient], g_iBBansLength[iClient] > 0 ? "s" : "", g_sBBansBy[iClient]);
		return Plugin_Handled;
	}
	return Plugin_Handled;
}

public Action Command_BBanlist(int iClient, int iArgs)
{
	char sBuff[1024];
	bool bFirst = true;
	Format(sBuff, sizeof(sBuff), "No players found.");

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i)) continue;
		
		if (g_bBBans[i])
		{
			if (bFirst)
			{
				bFirst = false;
				CReplyToCommand(iClient, "{orange}[BW] {default}Currently BBanned:");
			}
			
			char sPlayerSID[64];
			GetClientAuthId(i, AuthId_Steam2, sPlayerSID, sizeof(sPlayerSID));
			
			if (g_iBBansLength[i] == -1)
			{
				Format(sBuff, sizeof(sBuff), "%N (%s) [Temp] | Admin: %s", i, sPlayerSID, g_sBBansBy[i]);
				CReplyToCommand(iClient, "> %s",sBuff);
			}
			if (g_iBBansLength[i] == 0)
			{
				Format(sBuff, sizeof(sBuff), "%N (%s) [Perm] | Admin: %s", i, sPlayerSID, g_sBBansBy[i]);
				CReplyToCommand(iClient, "> %s", sBuff);
			}
			if (g_iBBansLength[i] > 0)
			{
				int iTLeft = (g_iBBansLength[i] * 60 + g_iBBansIssued[i] - GetTime()) / 60;
				if (iTLeft < 0) iTLeft = 0;
				
				Format(sBuff, sizeof(sBuff), "%N (%s) [%i Min%s] | Admin: %s", i, sPlayerSID, iTLeft, iTLeft > 1 ? "s" : "", g_sBBansBy[i]);
				CReplyToCommand(iClient, "> %s",sBuff);
			}
		}
	}
	
	if (bFirst) CReplyToCommand(iClient, "{orange}[BW] {default}Currently BBanned: No players found.");
	
	Format(sBuff, sizeof(sBuff), "");
	return Plugin_Handled;
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