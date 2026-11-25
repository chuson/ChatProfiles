std = "lua51"
max_line_length = 120

-- Globals the addon creates.
globals = {
	"ChatProfilesDB",
	"SLASH_CHATPROFILES1",
	"SlashCmdList",
	-- tools/ChatCopyProbe
	"ChatCopyProbeDB",
	"SLASH_CHATCOPYPROBE1",
}

-- Game APIs in use. Check each new one against Blizzard's UI source and in game first
-- (see CONTRIBUTING.md).
read_globals = {
	"C_ChatInfo",
	"C_EncodingUtil",
	"C_Timer",
	"ChangeChatColor",
	"ChatTypeInfo",
	"Constants",
	"CreateFrame",
	"FCF_Close",
	"FCF_OpenNewWindow",
	"FCF_SetChatWindowFontSize",
	"FCF_SetLocked",
	"FCF_SetWindowAlpha",
	"FCF_SetWindowColor",
	"GetChatWindowChannels",
	"GetChatWindowInfo",
	"GetChatWindowMessages",
	"GetNormalizedRealmName",
	"GetTime",
	"SetChatColorNameByClass",
	"Settings",
	"UnitName",
	"date",
}

-- The test sets up its own stand-ins for game globals.
files["tests/validate.lua"] = {
	globals = { "Constants", "ChatTypeInfo" },
}
