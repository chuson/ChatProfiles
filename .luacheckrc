std = "lua51"
max_line_length = 120

-- Globals the addon sets.
globals = {
	"ChatProfilesDB",
	"SLASH_CHATPROFILES1",
	"SlashCmdList",
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
	"SetChatColorNameByClass",
	"Settings",
	"UnitName",
	"strlenutf8",
}

-- The test sets up its own stand-ins for game globals.
files["tests/validate.lua"] = {
	globals = { "Constants", "ChatTypeInfo", "C_EncodingUtil" },
}
