#include "discord_rpc.h"
#include "discord_register.h"

// Registering the discord:// URL handler is a desktop idea: the macOS file
// does it through NSWorkspace and the Linux one writes a .desktop file and
// then shells out to xdg-mime. iOS and tvOS have neither AppKit nor system(),
// which the SDK marks unavailable outright rather than letting it fail - and
// there is no Discord client on either to register with in the first place.
//
// So the two entry points exist and do nothing, which is what "not available
// here" honestly looks like. Borrowing the Linux file instead got one file
// further and then stopped on system() for the same underlying reason.

extern "C" {

void Discord_Register(const char* /*applicationId*/, const char* /*command*/)
{
}

void Discord_RegisterSteamGame(const char* /*applicationId*/, const char* /*steamId*/)
{
}

}
