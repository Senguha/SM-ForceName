#if defined _forcename_included
	#endinput
#endif
#define _forcename_included
#pragma newdecls required

/**
 * Called when a client gets to have a permanent name
 *
 * @param userName		Name of the user that got renamed
 * @param userAuth		SteamID of the user that got renamed
 * @param adminName		Name of the admin that renamed the user
 * @param adminAuth		SteamID of the admin that renamed the user
 * @param newname		Name that is forced on a user
 *
 * @noreturn
 */
forward void Forcename_OnBan(char[] userName, char[] userAuth, char[] adminName, char[] adminAuth, char[] newName);

public SharedPlugin __pl_forcename =
{
	name = "Forcename",
	file = "forcename.smx",
	#if defined REQUIRE_PLUGIN
	required = 1,
	#else
	required = 0,
	#endif
};