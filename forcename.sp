#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools_functions>
#include <forcename>

Database g_Database;

int g_iConnections;

StringMap forcedNames;

Handle g_hBanForward;

public Plugin myinfo = {
	name = "Force Name",
	description = "Forces players to have a permanent name they cannot change",
	author = "Mtseng",
	version = "1.0",
	url = "",
}

public void OnPluginStart() {
	
    RegAdminCmd("sm_forcename", Command_ForceName, ADMFLAG_KICK, "Forces players to have a permanent name");
	RegAdminCmd("sm_unbanname", Command_UnBanName, ADMFLAG_KICK, "Allows players to change their name again");
    
    HookEvent("player_changename", player_changename);
	HookUserMessage(GetUserMessageId("SayText2"), suppress_NameChange, true);
	
	LoadTranslations("common.phrases");
    
	SQL_Connector();
    
	forcedNames = CreateTrie();
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {

	g_hBanForward = CreateGlobalForward("Forcename_OnBan", ET_Ignore, Param_String, Param_String,Param_String,Param_String,Param_String);
	RegPluginLibrary("Forcename");

	return APLRes_Success;
}

void ForwardRename(char[] userName, char[] userAuth, char[] adminName, char[] adminAuth, char[] newName){
	Call_StartForward(g_hBanForward);
	Call_PushString(userName);
	Call_PushString(userAuth);
	Call_PushString(adminName);
	Call_PushString(adminAuth);
	Call_PushString(newName);
	Call_Finish();
}

//Connects us to the database and reads the databases.cfg
void SQL_Connector() {
	delete g_Database;

	if (!SQL_CheckConfig("forceName")) {
		SetFailState("PLUGIN STOPPED - Reason: No config entry found for 'forceName' in databases.cfg - PLUGIN STOPPED");
	}
	Database.Connect(SQL_ConnectorCallback, "forceName");
}

//What actually is called to establish a connection to the database.
public void SQL_ConnectorCallback(Database db, const char[] error, any data) {
	if (!db || error[0]) {
		LogError("Connection to SQL database has failed, reason: %s", error);

		g_iConnections++;

		SQL_Connector();

		if (g_iConnections == 5) {
			SetFailState("Connection to SQL database has failed too many times, plugin unloaded to prevent spam.");
		}
		return;
	}

	g_Database = db;

	SQL_LockDatabase(g_Database);
	SQL_FastQuery(g_Database, "SET NAMES \"UTF8\"");
	SQL_UnlockDatabase(g_Database);
	g_Database.Query(SQL_CreateTableCallback, "CREATE TABLE IF NOT EXISTS `forceName` ( \
  		`auth` VARCHAR(45) NOT NULL, \
  		`forcedName` VARCHAR(45) NOT NULL, \
  		`created` INT NOT NULL, \
  		`adminID` VARCHAR(45) NOT NULL, \
  		PRIMARY KEY (`auth`)) ENGINE = InnoDB CHARACTER SET utf8 COLLATE utf8_general_ci;");
}

public void SQL_CreateTableCallback(Database db, DBResultSet results, const char[] error, any data) {
	if (!db || !results || error[0]) {
		LogError(error);
		return;
	}
}

public Action Command_ForceName(int client, int args){
    char fullArg[128], err[128], newName[64], target[MAX_NAME_LENGTH];
	
	GetCmdArgString(fullArg, sizeof(fullArg));
	
	if (!GetCmdArgsTN(fullArg, target, sizeof target, newName, sizeof newName, err, sizeof err)) {
		ReplyToCommand(client, err);
		return Plugin_Handled;
	}
	
	int iTarget = FindTarget(client, target, true, true);

	if (!IsValidClient(iTarget) && IsClientSourceTV(client) && IsClientReplay(client)){
		ReplyToCommand(client, "Invalid target");
		return Plugin_Handled;
	}

	if (strcmp(newName, "STEAM2")==0)
		GetClientAuthId(iTarget, AuthId_Steam2, newName, sizeof newName);
	if(strcmp(newName, "STEAM3")==0)
		GetClientAuthId(iTarget, AuthId_Steam3, newName, sizeof newName);
	if(strcmp(newName, "STEAM64")==0)
		GetClientAuthId(iTarget, AuthId_SteamID64, newName, sizeof newName);

	char query[1024];
	char authAdmin[MAX_AUTHID_LENGTH], authTarget[MAX_AUTHID_LENGTH];
	GetClientAuthId(iTarget, AuthId_Steam2, authTarget, sizeof(authTarget));
	GetClientAuthId(client, AuthId_Steam2, authAdmin, sizeof(authAdmin));

	DataPack pack = new DataPack();
	pack.WriteCell(GetClientUserId(client));
	pack.WriteCell(GetClientUserId(iTarget));
	pack.WriteString(newName);
	
	g_Database.Format(query, sizeof(query), "INSERT INTO forcename (`auth`, `forcedName`, `created`, `adminID`) \
	VALUES ('%s', '%s', UNIX_TIMESTAMP(), '%s') \
	ON DUPLICATE KEY UPDATE \
    `forcedName` = VALUES(`forcedName`), \
    `adminID` = VALUES(`adminID`), \
	`created` = VALUES(created);", authTarget, newName, authAdmin);

	SQL_TQuery(g_Database,SQL_ForceNameCallback ,query, pack);
	
	return Plugin_Handled;
}

public void SQL_ForceNameCallback(Database db, DBResultSet results, const char[] error, DataPack pack) {
	
	pack.Reset();
	int clientID = pack.ReadCell();
	int targetID = pack.ReadCell();
	char newName[MAX_NAME_LENGTH];
	pack.ReadString(newName, sizeof(newName));
	delete pack;

	int iClient = GetClientOfUserId(clientID);
	int iTarget = GetClientOfUserId(targetID);
	
	if (!db || error[0]) {
		LogError("SQL error in SQL_ForceNameCallback: %s", error);
		ReplyToCommand(iClient, "DB Error");
		return;
	}

	char targetKey[3];
	IntToString(iTarget, targetKey, 3);
	forcedNames.SetString(targetKey, newName);

	char clientName[MAX_NAME_LENGTH];
	GetClientName(iClient, clientName, sizeof(clientName));
	char clientAuth[MAX_AUTHID_LENGTH];
	GetClientAuthId(iClient, AuthId_Steam2, clientAuth, sizeof(clientAuth));
	char adminName[MAX_NAME_LENGTH];
	GetClientName(iTarget, adminName, sizeof(adminName));
	char adminAuth[MAX_AUTHID_LENGTH];
	GetClientAuthId(iTarget, AuthId_Steam2, adminAuth, sizeof(adminAuth));

	ForwardRename(clientName, clientAuth, adminName, adminAuth, newName);

	LogAction(iClient, iTarget, "%L Forced %L to permanent name %s", iClient, iTarget, newName);
	ShowActivity2(iClient, "[ForceName] ", "%N навсегда изменил имя %N на %s", iClient, iTarget, newName);

	SetClientName(iTarget, newName);
}

public Action Command_UnBanName(int client, int args){
	
	if (args < 1)
	{
		ReplyToCommand(client, "Usage: sm_unbanname <target>");
		return Plugin_Handled;
	}

	char fullArg[128];
	GetCmdArgString(fullArg, sizeof(fullArg));

	int iTarget = FindTarget(client, fullArg, true, true);

	if (!IsValidClient(iTarget) && IsClientSourceTV(client) && IsClientReplay(client)){
		ReplyToCommand(client, "Invalid target");
		return Plugin_Handled;
	}

	char authTarget[MAX_AUTHID_LENGTH];
	GetClientAuthId(iTarget, AuthId_Steam2, authTarget, sizeof(authTarget));

	DataPack pack = new DataPack();
	pack.WriteCell(GetClientUserId(client));
	pack.WriteCell(GetClientUserId(iTarget));
	
	char query[1024];	
	g_Database.Format(query, sizeof(query), "DELETE FROM forcename WHERE `auth` = '%s'", authTarget);
	SQL_TQuery(g_Database, SQL_UnBanNameCallback, query, pack);
	return Plugin_Handled;
}

public void SQL_UnBanNameCallback(Database db, DBResultSet results, const char[] error, DataPack pack) {
	
	pack.Reset();
	int clientID = pack.ReadCell();
	int targetID = pack.ReadCell();
	delete pack;

	int client = GetClientOfUserId(clientID);
	int target = GetClientOfUserId(targetID);
	
	if (!db || error[0]) {
		LogError("SQL error in SQL_UnBanNameCallback: %s", error);
		ReplyToCommand(client, "DB Error");
		return;
	}
	char targetKey[3];
	IntToString(target, targetKey, 3);
	forcedNames.Remove(targetKey);

	LogAction(client, target, "%L Removed permanent name from %L", client, target);
	ShowActivity2(client, "[ForceName] ", "%N убрал постоянное имя c %N", client, target);
}

public Action player_changename(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	char clientKey[3], clientForcedName[MAX_NAME_LENGTH];
	IntToString(client, clientKey, 3);
	
	if (forcedNames.GetString(clientKey,clientForcedName, sizeof(clientForcedName))) {
		char clientName[MAX_NAME_LENGTH];
		GetEventString(event, "newname", clientName, sizeof(clientName));
		if (strcmp(clientName, clientForcedName)!=0)
			SetClientName(client, clientForcedName);
	}
    return Plugin_Continue;
}

public void OnClientAuthorized(int client, const char[] auth){
    CheckForcedName(client);
}
public void OnClientDisconnect(int client){
	char clientKey[3];
	IntToString(client, clientKey, 3);
	forcedNames.Remove(clientKey);
}
public void OnMapStart(){
	forcedNames.Clear();
}
void CheckForcedName(int client){
	
	if (!IsValidClient(client)){
		LogError("Client %L not authed in CheckName, waiting 5 sec...", client);
		CreateTimer(5.0, timerCheckName, GetClientUserId(client));
		return;
	}

	if (!g_Database){
		LogError("Database not connected in CheckName");
		return;
	}

	char auth[32];
	if (!GetClientAuthId(client, AuthId_Steam2, auth, 32, true))
	{
		CreateTimer(5.0, timerCheckName, GetClientUserId(client));
		return;
	}

	char query[1024];

	g_Database.Format(query, sizeof(query), "\
	SELECT `forcedname` \
	FROM `forceName` WHERE `auth` = '%s' LIMIT 1", auth);

	SQL_TQuery(g_Database, sqlQuery_CheckName, query, GetClientUserId(client));
}

public void sqlQuery_CheckName(Database db, DBResultSet results, const char[] error, int userid) {
	if (!db || !results || error[0]){
		LogError("CheckBan query failed. (%s)", error);
		return;
	}

	int client = GetClientOfUserId(userid);

	if (results.HasResults && results.RowCount && results.FetchRow()){
		char forcedName[MAX_NAME_LENGTH];
		results.FetchString(0, forcedName, sizeof(forcedName));
		
		char clientKey[16];
		IntToString(client, clientKey, sizeof(clientKey));
		forcedNames.SetString(clientKey, forcedName, true);

		SetClientName(client, forcedName);
	}
}

public Action timerCheckName(Handle timer, int userid) {
	int client = GetClientOfUserId(userid);
	if (!client)
	{
		return Plugin_Stop;
	}

	CheckForcedName(client);

	return Plugin_Stop;
}
//Suppress the name change server messages
public Action suppress_NameChange(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)	{

		char buffer[25];
		view_as<BfRead>(msg).ReadChar();
		view_as<BfRead>(msg).ReadChar();
		view_as<BfRead>(msg).ReadString(buffer, sizeof(buffer));
	
		if(StrContains(buffer, "Name_Change", false) != -1)
			return Plugin_Handled;

	return Plugin_Continue;
}

//Gets the command arguments from input. Target, newName. returns false if args are invalid
bool GetCmdArgsTN(char[] input, char[] target, int targetS, char[] newName, int newNameS, char[] err, int errS){
	int iLen;
	
	if ((iLen = BreakString(input, target, targetS)) == -1){
			strcopy(err, errS, "Usage: sm_forcename <target/STEAM2/STEAM3/STEAM64> [name]");
		return false;
	}
		
	strcopy(newName, newNameS, input[iLen]);
	
	return true;
}

stock bool IsValidClient(int client) {
	return (0 < client <= MAXPLAYERS && IsClientInGame(client));
}