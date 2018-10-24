#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#include <kento_csgocolors>

#pragma newdecls required

#define MAXMODELS 1024

// Models
char Model_Name[MAXMODELS][1024];
char Model_Path[MAXMODELS][1024];
float Model_Scale[MAXMODELS];
float Model_Pos[MAXMODELS][3];
float Model_Angle[MAXMODELS][3];
int Model_Count;

// Cookie
Handle Cookie_Model, Cookie_Type;

// Client
char Client_Model[MAXPLAYERS + 1][1024];
int Client_ModelID[MAXPLAYERS + 1];
int Client_ModelEnt[MAXPLAYERS + 1];
int Client_Type[MAXPLAYERS + 1];
int Client_Ref[MAXPLAYERS + 1];
int Client_MRef[MAXPLAYERS + 1];
int Client_Chicken[MAXPLAYERS + 1];

// Cvars
ConVar Cvar_Kill;
int iKill;

public Plugin myinfo =
{
	name = "[CS:GO] Chicken Pets",
	author = "Kento",
	version = "1.0.1",
	description = "Create a chicken as pet.",
	url = "http://steamcommunity.com/id/kentomatoryoshika/"
};

public void OnPluginStart() 
{
	RegConsoleCmd("sm_chicken", CMD_Chicken, "Chicken menu");
	RegAdminCmd("sm_ec", CMD_EditChicken, ADMFLAG_GENERIC, "Chicken editor menu");
	
	Cookie_Model = RegClientCookie("chicken_model", "Player's chicken model", CookieAccess_Private);
	Cookie_Type = RegClientCookie("chicken_type", "Player's chicken type", CookieAccess_Private);
	
	HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);
	HookEvent("player_death", Event_PlayerDeath);

	LoadTranslations("core.phrases");
	LoadTranslations("kento.chicken.phrases");
	
	Cvar_Kill = CreateConVar("sm_chicken_kill", "0", "Will chicken disappear after his breeder killed?\n0 = no, 1= yes");
	Cvar_Kill.AddChangeHook(OnConVarChanged);
	
	AutoExecConfig(true, "kento_chicken_pet");
	
	for(int i = 1; i <= MaxClients; i++)
	{ 
		if(IsValidClient(i) && !IsFakeClient(i) && !AreClientCookiesCached(i))	OnClientCookiesCached(i);
	}
}

public void OnConfigsExecuted()
{
	iKill = Cvar_Kill.IntValue;
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(convar == Cvar_Kill)	iKill = Cvar_Kill.IntValue;
}

public void OnMapStart() 
{
	LoadConfig();
	DownloadFiles();
	
	PrecacheModel("models/chicken/chicken.mdl", true);
	PrecacheModel("models/chicken/chicken_zombie.mdl", true);
	
	PrecacheParticleEffect("chicken_gone_feathers");
	PrecacheParticleEffect("chicken_gone_feathers_zombie");
}

void LoadConfig()
{
	char Configfile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, Configfile, sizeof(Configfile), "configs/kento_chicken/models.cfg");
	
	if (!FileExists(Configfile))
	{
		SetFailState("Fatal error: Unable to open configuration file \"%s\"!", Configfile);
	}
	
	KeyValues kv = CreateKeyValues("models");
	kv.ImportFromFile(Configfile);
	
	if(!kv.GotoFirstSubKey())
	{
		SetFailState("Fatal error: Unable to read configuration file \"%s\"!", Configfile);
	}
	
	char pos[PLATFORM_MAX_PATH], posdata[3][PLATFORM_MAX_PATH], name[PLATFORM_MAX_PATH], model[PLATFORM_MAX_PATH], 
	ang[PLATFORM_MAX_PATH], angdata[3][PLATFORM_MAX_PATH];
	
	Model_Count = 1;
	do
	{
		kv.GetSectionName(name, sizeof(name));
		kv.GetString("model", model, sizeof(model), "unknown");
		kv.GetString("position", pos, sizeof(pos), "unknown");
		
		if(!StrEqual(pos, "unknown") && !StrEqual(model, "unknown"))
		{
			strcopy(Model_Name[Model_Count], sizeof(Model_Name[]), name);
			strcopy(Model_Path[Model_Count], sizeof(Model_Path[]), model);
			PrecacheModel(Model_Path[Model_Count], true);
			
			ExplodeString(pos, ";", posdata, 3, 32);
			Model_Pos[Model_Count][0] = StringToFloat(posdata[0]);
			Model_Pos[Model_Count][1] = StringToFloat(posdata[1]);
			Model_Pos[Model_Count][2] = StringToFloat(posdata[2]);
			
			kv.GetString("angles", ang, sizeof(ang), "0.0;0.0;0.0");
			ExplodeString(ang, ";", angdata, 3, 32);
			Model_Angle[Model_Count][0] = StringToFloat(angdata[0]);
			Model_Angle[Model_Count][1] = StringToFloat(angdata[1]);
			Model_Angle[Model_Count][2] = StringToFloat(angdata[2]);
			
			Model_Scale[Model_Count] = kv.GetFloat("scale", 1.0);
			
			Model_Count++;
		}
		else
		{
			LogError("Unable to read settings of %s, ignoring...", name);
		}
	} while (kv.GotoNextKey());
	
	kv.Rewind();
	delete kv;
	
	Model_Count--;
}

void DownloadFiles()
{
	PrecacheEffect("ParticleEffect");
	
	char Configfile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, Configfile, sizeof(Configfile), "configs/kento_chicken/downloads.cfg");
	
	if (!FileExists(Configfile))
	{
		LogError("Unable to open download file \"%s\"!", Configfile);
		return;
	}
	
	char line[PLATFORM_MAX_PATH];
	Handle fileHandle = OpenFile(Configfile,"r");

	while(!IsEndOfFile(fileHandle) && ReadFileLine(fileHandle, line, sizeof(line)))
	{
		// Remove whitespaces and empty lines
		TrimString(line);
		ReplaceString(line, sizeof(line), " ", "", false);
	
		// Skip comments
		if (line[0] != '/' && FileExists(line, true))
		{
			AddFileToDownloadsTable(line);
		}
	}
	CloseHandle(fileHandle);
}

// https://forums.alliedmods.net/showpost.php?p=2471747&postcount=4
stock void PrecacheEffect(const char[] sEffectName)
{
    static int table = INVALID_STRING_TABLE;
    
    if (table == INVALID_STRING_TABLE)
    {
        table = FindStringTable("EffectDispatch");
    }
    bool save = LockStringTables(false);
    AddToStringTable(table, sEffectName);
    LockStringTables(save);
}

stock void PrecacheParticleEffect(const char[] sEffectName)
{
    static int table = INVALID_STRING_TABLE;
    
    if (table == INVALID_STRING_TABLE)
    {
        table = FindStringTable("ParticleEffectNames");
    }
    bool save = LockStringTables(false);
    AddToStringTable(table, sEffectName);
    LockStringTables(save);
}

public void OnClientPutInServer(int client)
{
	if (IsValidClient(client) && !IsFakeClient(client))	OnClientCookiesCached(client);
}

public void OnClientCookiesCached(int client)
{
	if(!IsValidClient(client) && IsFakeClient(client))	return;
	
	// Model cookie
	char scookie[1024];
	GetClientCookie(client, Cookie_Model, scookie, sizeof(scookie));
	if(!StrEqual(scookie, ""))
	{
		Client_ModelID[client] = FindModelIDByName(scookie);
		if(Client_ModelID[client] > 0)	strcopy(Client_Model[client], sizeof(Client_Model[]), scookie);
		else 
		{
			Client_Model[client] = "";
			SetClientCookie(client, Cookie_Model, "");
		}
	}
	else 
	{
		Client_Model[client] = "";	
		Client_ModelID[client] = 0;
	}
	
	// Model cookie
	GetClientCookie(client, Cookie_Type, scookie, sizeof(scookie));
	if(!StrEqual(scookie, ""))
	{
		Client_Type[client] = StringToInt(scookie);
		if(Client_Type[client] > 2)	SetClientCookie(client, Cookie_Type, "0");
	}
	else Client_Type[client] = 0;	
}

public Action Event_PlayerSpawn(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if(IsValidClient(client))	CreateTimer(0.1, SpawnDelay, client);
}

public Action SpawnDelay(Handle timer, int client)
{
	SpawnChicken(client);
}

public Action Event_PlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if(IsValidClient(client))
	{
		if(iKill == 1)
		{
			int entity = EntRefToEntIndex(Client_Ref[client]);
			if(entity != INVALID_ENT_REFERENCE && IsValidEdict(entity) && entity != 0)
			{
				if(Client_Type[client] == 3)	CreateParticle(entity, 3);
				else	CreateParticle(entity, 1);
				
				AcceptEntityInput(entity, "Kill");
				Client_Ref[client] = INVALID_ENT_REFERENCE;
			}
		}
	}
}

public Action CMD_Chicken(int client, int args)
{
	if(IsValidClient(client) && !IsFakeClient(client))
	{
		ShowMenu(client, "main", 0);
	}
	
	return Plugin_Handled;
}

public Action CMD_EditChicken(int client, int args)
{
	if(IsValidClient(client) && !IsFakeClient(client))
	{
		if(!IsPlayerAlive(client))
		{
			CPrintToChat(client, "%T", "Must Alive", client);
			return Plugin_Handled;
		}
		
		if(Client_Type[client] == 0)	Client_Type[client] = 1;
		
		SpawnChicken(client);
		ShowMenu(client, "model2", 0);
	}
	
	return Plugin_Handled;
}

public int EditMenuHandler(Menu menu, MenuAction action, int client, int param)
{
	if(action == MenuAction_Select)
	{
		char select[1024];
		GetMenuItem(menu, param, select, sizeof(select));
		
		// https://github.com/Franc1sco/Franug-hats/blob/master/scripting/franug_hats.sp#L683
		int num;
		float pos;
		
		if (StrContains(select, "Position", false) != -1)
		{
			ReplaceString(select, 32, "Position", "", false);
			
			if (StrContains(select, "X", false) != -1)
			{
				num = 0;
				ReplaceString(select, 32, "X", "", false);
			}
			else if (StrContains(select, "Y", false) != -1)
			{
				num = 1;
				ReplaceString(select, 32, "Y", "", false);
			}
			else if (StrContains(select, "Z", false) != -1)
			{
				num = 2;
				ReplaceString(select, 32, "Z", "", false);
			}
			
			pos = StringToFloat(select);
			
			Model_Pos[Client_ModelID[client]][num] += pos;
			
			RefreshModel(client);
		}
		else if (StrContains(select, "Angle", false) != -1)
		{
			ReplaceString(select, 32, "Angle", "", false);

			if (StrContains(select, "X", false) != -1)
			{
				num = 0;
				ReplaceString(select, 32, "X", "", false);
			}
			else if (StrContains(select, "Y", false) != -1)
			{
				num = 1;
				ReplaceString(select, 32, "Y", "", false);
			}
			else if (StrContains(select, "Z", false) != -1)
			{
				num = 2;
				ReplaceString(select, 32, "Z", "", false);
			}
			
			pos = StringToFloat(select);
			
			Model_Angle[Client_ModelID[client]][num] += pos;
			
			RefreshModel(client);
		}
		else if (StrContains(select, "Save", false) != -1)
		{
			SaveConfig(Client_ModelID[client], client);
		}
		
		ShowMenu(client, "edit", GetMenuSelectionPosition());
	}
	else if(action == MenuAction_Cancel)
	{
		ShowMenu(client, "model2", 0);
	}
}

public int ChickenMenuHandler(Menu menu, MenuAction action, int client, int param)
{
	if(action == MenuAction_Select)
	{
		char select[1024];
		GetMenuItem(menu, param, select, sizeof(select));
		
		if(StrEqual(select, "model"))
		{
			ShowMenu(client, "model", 0);
		}
		else if(StrEqual(select, "type"))
		{
			ShowMenu(client, "type", 0);
		}
	}
}

public int ModelMenuHandler(Menu menu, MenuAction action, int client, int param)
{
	if(action == MenuAction_Select)
	{
		char name[1024];
		GetMenuItem(menu, param, name, sizeof(name));
		
		strcopy(Client_Model[client], sizeof(Client_Model[]), name);
		SetClientCookie(client, Cookie_Model, name);
		
		if(StrEqual(name, ""))
		{
			CPrintToChat(client, "%T", "No Selected Hat", client);
			Client_ModelID[client] = 0;
			ShowMenu(client, "model", GetMenuSelectionPosition());
				
			int entity = EntRefToEntIndex(Client_MRef[client]);
			if(entity != INVALID_ENT_REFERENCE && IsValidEdict(entity) && entity != 0)
			{
				AcceptEntityInput(entity, "Kill");
				Client_MRef[client] = INVALID_ENT_REFERENCE;
			}
		}
		else
		{
			CPrintToChat(client, "%T", "Selected Hat", client, name);
			ShowMenu(client, "model", GetMenuSelectionPosition());
			Client_ModelID[client] = FindModelIDByName(name);
			RefreshModel(client);
		}
	}
	else if(action == MenuAction_Cancel)
	{
		ShowMenu(client, "main", 0);
	}
}

public int ModelMenuHandler2(Menu menu, MenuAction action, int client, int param)
{
	if(action == MenuAction_Select)
	{
		char name[1024];
		GetMenuItem(menu, param, name, sizeof(name));

		strcopy(Client_Model[client], sizeof(Client_Model[]), name);
		Client_ModelID[client] = FindModelIDByName(name);
		SetClientCookie(client, Cookie_Model, name);
		
		CPrintToChat(client, "%T", "Selected Hat", client, name);
		
		if(IsPlayerAlive(client))	RefreshModel(client);
				
		ShowMenu(client, "edit", 0);
	}
}

public int TypeMenuHandler(Menu menu, MenuAction action, int client, int param)
{
	if(action == MenuAction_Select)
	{
		char name[1024];
		GetMenuItem(menu, param, name, sizeof(name));
		
		Client_Type[client] = StringToInt(name);
		
		if(Client_Type[client] == 0)		CPrintToChat(client, "%T", "No Selected Type", client);
		else if(Client_Type[client] == 1)	CPrintToChat(client, "%T", "Selected Noraml Type", client);
		else if(Client_Type[client] == 2)	CPrintToChat(client, "%T", "Selected Brown Type", client);
		else if(Client_Type[client] == 3)	CPrintToChat(client, "%T", "Selected Zombie Type", client);
		else if(Client_Type[client] == 4)	CPrintToChat(client, "%T", "Selected Birthday Type", client);
		else if(Client_Type[client] == 5)	CPrintToChat(client, "%T", "Selected Ghost Type", client);
		else if(Client_Type[client] == 6)	CPrintToChat(client, "%T", "Selected Xmas Type", client);
		else if(Client_Type[client] == 7)	CPrintToChat(client, "%T", "Selected Bunny Type", client);
		else if(Client_Type[client] == 8)	CPrintToChat(client, "%T", "Selected Pumpkin Type", client);
		
		SpawnChicken(client);
		
		SetClientCookie(client, Cookie_Type, name);
		
		ShowMenu(client, "type", GetMenuSelectionPosition());
	}
	else if(action == MenuAction_Cancel)
	{
		ShowMenu(client, "main", 0);
	}
}

int FindModelIDByName(char [] name)
{
	int id = 0;
	
	for(int i = 1; i <= Model_Count; i++)
	{
		if(StrEqual(Model_Name[i], name))	id = i;
	}
	
	return id;
}

void SpawnChicken(int client)
{
	// Kill exist chicken
	int entity = EntRefToEntIndex(Client_Ref[client]);
	if(entity != INVALID_ENT_REFERENCE && IsValidEdict(entity) && entity != 0)
	{
		AcceptEntityInput(entity, "Kill");
		Client_Ref[client] = INVALID_ENT_REFERENCE;
	}
	entity = EntRefToEntIndex(Client_MRef[client]);
	if(entity != INVALID_ENT_REFERENCE && IsValidEdict(entity) && entity != 0)
	{
		AcceptEntityInput(entity, "Kill");
		Client_MRef[client] = INVALID_ENT_REFERENCE;
	}
	
	// No Chicken, and player dead, return
	if(Client_Type[client] == 0 || !IsPlayerAlive(client))	return;

	// Spawn Chicken
	int ent = CreateEntityByName("chicken");
	
	// ent = chicken, model = hat
	if(IsValidEntity(ent))
	{
		Client_Chicken[client] = ent;
		float pos[3];
		GetClientAbsOrigin(client, pos);
		
		DispatchSpawn(ent);
		TeleportEntity(ent, pos, NULL_VECTOR, NULL_VECTOR);
		
		SetEntPropEnt(ent, Prop_Send, "m_leader", client);
		
		CreateParticle(ent, Client_Type[client]);
		
		// set not killable
		SetEntProp(ent, Prop_Data, "m_takedamage", 0);
		
		// brown chicken
		if(Client_Type[client] == 2)	DispatchKeyValue(ent, "skin", "1");
		
		// Change model if is zombie chicken
		else if(Client_Type[client] == 3)	SetEntityModel(ent, "models/chicken/chicken_zombie.mdl");
		
		// Holiday chickens
		// https://forums.alliedmods.net/showpost.php?p=2512427&postcount=4
		else if(Client_Type[client] == 4)	SetEntProp(ent, Prop_Data, "m_nBody", 1);  
		else if(Client_Type[client] == 5)	SetEntProp(ent, Prop_Data, "m_nBody", 2);  
		else if(Client_Type[client] == 6)	SetEntProp(ent, Prop_Data, "m_nBody", 3);  
		else if(Client_Type[client] == 7)	SetEntProp(ent, Prop_Data, "m_nBody", 4);  
		else if(Client_Type[client] == 8)	SetEntProp(ent, Prop_Data, "m_nBody", 5);  
		
		
		HookSingleEntityOutput(ent, "OnBreak", OnBreak);
		
		Client_Ref[client] = EntIndexToEntRef(ent);
		
		// Has model
		if(!StrEqual(Client_Model[client], ""))	RefreshModel(client);
	}
	else LogError("Failed to spawn chicken");
}

void RefreshModel(int client)
{
	// check chicken
	int entity = EntRefToEntIndex(Client_Ref[client]);
	if(entity != INVALID_ENT_REFERENCE && IsValidEdict(entity) && entity != 0)
	{
		float pos[3], angle[3];
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
		GetEntPropVector(entity, Prop_Send, "m_angRotation", angle);  

		// check model
		int entity2 = EntRefToEntIndex(Client_MRef[client]);
		if(entity2 != INVALID_ENT_REFERENCE && IsValidEdict(entity2) && entity2 != 0)
		{
			AcceptEntityInput(entity2, "Kill");
			Client_MRef[client] = INVALID_ENT_REFERENCE;
		}
		
		int model = CreateEntityByName("prop_dynamic_override");
		Client_ModelEnt[client] = model;
		
		DispatchKeyValue(model, "model", Model_Path[ Client_ModelID[client] ]);
		DispatchKeyValue(model, "spawnflags", "256");
		DispatchKeyValue(model, "solid", "0");
		SetEntPropEnt(model, Prop_Send, "m_hOwnerEntity", entity);
		SetEntPropFloat(model, Prop_Send, "m_flModelScale", Model_Scale[ Client_ModelID[client] ]);
		
		SetEntProp(model, Prop_Data, "m_CollisionGroup", 0);  
	
		DispatchSpawn(model);	
		AcceptEntityInput(model, "TurnOn", model, model, 0);
		
		float m_fForward[3], m_fRight[3], m_fUp[3];
		
		GetAngleVectors(angle, m_fForward, m_fRight, m_fUp);
		
		pos[0] += m_fRight[0]*Model_Pos[Client_ModelID[client]][0]+m_fForward[0]*Model_Pos[Client_ModelID[client]][1]+m_fUp[0]*Model_Pos[Client_ModelID[client]][2];
		pos[1] += m_fRight[1]*Model_Pos[Client_ModelID[client]][0]+m_fForward[1]*Model_Pos[Client_ModelID[client]][1]+m_fUp[1]*Model_Pos[Client_ModelID[client]][2];
		pos[2] += m_fRight[2]*Model_Pos[Client_ModelID[client]][0]+m_fForward[2]*Model_Pos[Client_ModelID[client]][1]+m_fUp[2]*Model_Pos[Client_ModelID[client]][2];
		
		angle[0] += Model_Angle[Client_ModelID[client]][0];
		angle[1] += Model_Angle[Client_ModelID[client]][1];
		angle[2] += Model_Angle[Client_ModelID[client]][2];
		
		TeleportEntity(model, pos, angle, NULL_VECTOR); 
	
		SetVariantString("!activator");
		AcceptEntityInput(model, "SetParent", entity, model, 0);
		AcceptEntityInput(model, "SetParentAttachmentMaintainOffset", model, model, 0);	
		
		Client_MRef[client] = EntIndexToEntRef(model);
	}
}

// https://forums.alliedmods.net/showthread.php?p=2283192
void CreateParticle(int entity, int type)
{	
	int particle = CreateEntityByName("info_particle_system");
	if(IsValidEntity(particle))
	{
		float pos[3];
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", pos);
		TeleportEntity(particle, pos, NULL_VECTOR, NULL_VECTOR);
		
		if(type == 3)	DispatchKeyValue(particle, "effect_name", "chicken_gone_feathers_zombie");
		else	DispatchKeyValue(particle, "effect_name", "chicken_gone_feathers");
		
		DispatchKeyValue(particle, "angles", "-90 0 0");
		DispatchSpawn(particle);
		ActivateEntity(particle);
		AcceptEntityInput(particle, "Start");
		
		CreateTimer(5.0, Timer_KillEntity, EntIndexToEntRef(particle));
	}
}

public void OnBreak(const char[] output, int caller, int activator, float delay)
{
	int client = FindOwnerByEnt(caller);
	if(Client_Type[client] == 3)	CreateParticle(caller, 3);
	UnhookSingleEntityOutput(caller, "OnBreak", OnBreak);
}

int FindOwnerByEnt(int ent)
{
	int r;
	for (int i = 1; i <= MAXPLAYERS ; i++)
	{
		if(ent == Client_Chicken[i])	r = i;
	}
	return r;
}

public Action Timer_KillEntity(Handle timer, any reference)
{
	int entity = EntRefToEntIndex(reference);
	if(entity != INVALID_ENT_REFERENCE)
	{
		AcceptEntityInput(entity, "Kill");
	}
}

void ShowMenu(int client, char [] menu, int item)
{
	char tmp[1024];
	
	if(StrEqual(menu, "edit"))
	{
		Menu menu_editor = new Menu(EditMenuHandler);
		
		Format(tmp, sizeof(tmp), "%T", "Edit Menu Title", client, Client_Model[client]);
		menu_editor.SetTitle(tmp);
		menu_editor.SetTitle("Chicken Hats Editor");
		menu_editor.AddItem("Position X+0.5", "Position X + 0.5");
		menu_editor.AddItem("Position X-0.5", "Position X - 0.5");
		menu_editor.AddItem("Position Y+0.5", "Position Y + 0.5");
		menu_editor.AddItem("Position Y-0.5", "Position Y - 0.5");
		menu_editor.AddItem("Position Z+0.5", "Position Z + 0.5");
		menu_editor.AddItem("Position Z-0.5", "Position Z - 0.5");
		menu_editor.AddItem("Angle X+0.5", "Angle X + 0.5");
		menu_editor.AddItem("Angle X-0.5", "Angle X - 0.5");
		menu_editor.AddItem("Angle Y+0.5", "Angle Y + 0.5");
		menu_editor.AddItem("Angle Y-0.5", "Angle Y - 0.5");
		menu_editor.AddItem("Angle Z+0.5", "Angle Z + 0.5");
		menu_editor.AddItem("Angle Z-0.5", "Angle Z - 0.5");
		menu_editor.AddItem("save", "Save");
	
		DisplayMenuAtItem(menu_editor, client, item, 0);
	}
	else if(StrEqual(menu, "model"))
	{
		Menu menu_model = new Menu(ModelMenuHandler);
		
		Format(tmp, sizeof(tmp), "%T", "Model Menu Title", client);
		menu_model.SetTitle(tmp);
		
		Format(tmp, sizeof(tmp), "%T", "NO Model", client);
		menu_model.AddItem("", tmp);
		
		for(int i = 1; i <= Model_Count; i++)
		{
			menu_model.AddItem(Model_Name[i], Model_Name[i]);
		}

		DisplayMenuAtItem(menu_model, client, item, 0);
	}
	else if(StrEqual(menu, "model2"))
	{
		Menu menu_model2 = new Menu(ModelMenuHandler2);
		
		Format(tmp, sizeof(tmp), "%T", "Model Menu Title", client);
		menu_model2.SetTitle(tmp);
		
		for(int i = 1; i <= Model_Count; i++)
		{
			menu_model2.AddItem(Model_Name[i], Model_Name[i]);
		}

		DisplayMenuAtItem(menu_model2, client, item, 0);
	}
	else if(StrEqual(menu, "type"))
	{
		Menu menu_type = new Menu(TypeMenuHandler);
		
		Format(tmp, sizeof(tmp), "%T", "Type Menu Title", client);
		menu_type.SetTitle(tmp);
		
		Format(tmp, sizeof(tmp), "%T", "NO Chicken", client);
		menu_type.AddItem("0", tmp);
		
		Format(tmp, sizeof(tmp), "%T", "Normal Chicken", client);
		menu_type.AddItem("1", tmp);
		
		Format(tmp, sizeof(tmp), "%T", "Brown Chicken", client);
		menu_type.AddItem("2", tmp);
		
		Format(tmp, sizeof(tmp), "%T", "Zombie Chicken", client);
		menu_type.AddItem("3", tmp);
		
		Format(tmp, sizeof(tmp), "%T", "Birthday Chicken", client);
		menu_type.AddItem("4", tmp);
		
		Format(tmp, sizeof(tmp), "%T", "Ghost Chicken", client);
		menu_type.AddItem("5", tmp);
		
		Format(tmp, sizeof(tmp), "%T", "Xmas Chicken", client);
		menu_type.AddItem("6", tmp);
		
		Format(tmp, sizeof(tmp), "%T", "Bunny Chicken", client);
		menu_type.AddItem("7", tmp);
		
		Format(tmp, sizeof(tmp), "%T", "Pumpkin Chicken", client);
		menu_type.AddItem("8", tmp);

		DisplayMenuAtItem(menu_type, client, item, 0);
	}
	else if(StrEqual(menu, "main"))
	{
		Menu menu_main = new Menu(ChickenMenuHandler);
		
		Format(tmp, sizeof(tmp), "%T", "Chicken Menu Title", client);
		menu_main.SetTitle(tmp);
		
		Format(tmp, sizeof(tmp), "%T", "Model Menu Title", client);
		menu_main.AddItem("model", tmp);
		
		Format(tmp, sizeof(tmp), "%T", "Type Menu Title", client);
		menu_main.AddItem("type", tmp);
		
		DisplayMenuAtItem(menu_main, client, item, 0);
	}
}

void SaveConfig(int id, int client)
{
	char Configfile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, Configfile, sizeof(Configfile), "configs/kento_chicken/models.cfg");
	
	if (!FileExists(Configfile))
	{
		SetFailState("Fatal error: Unable to open configuration file \"%s\"!", Configfile);
	}
	
	KeyValues kv = CreateKeyValues("models");
	kv.ImportFromFile(Configfile);
	kv.JumpToKey(Model_Name[id], true);
	
	char spos[512], sangle[512];
	
	Format(spos, sizeof(spos), "%f;%f;%f", Model_Pos[id][0], Model_Pos[id][1], Model_Pos[id][2]);
	Format(sangle, sizeof(sangle), "%f;%f;%f", Model_Angle[id][0], Model_Angle[id][1], Model_Angle[id][2]);

	kv.SetString("position", spos);
	kv.SetString("angles", sangle);
	
	kv.Rewind();
	kv.ExportToFile(Configfile);
	
	CPrintToChat(client, "%T", "Edit Saved", client);
	
	delete kv;
}

stock bool IsValidClient(int client)
{
	if (client <= 0) return false;
	if (client > MaxClients) return false;
	if (!IsClientConnected(client)) return false;
	return IsClientInGame(client);
}