std = "lua51"
max_line_length = 120

-- Globals the addon sets.
globals = {
	"ChatProfilesDB",
	"SLASH_CHATPROFILES1",
	"SLASH_CHATPROFILES2",
	"SlashCmdList",
	"StaticPopupDialogs",
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
	"FCF_CheckShowChatFrame",
	"FCF_Close",
	"FCF_DockFrame",
	"FCF_OpenNewWindow",
	"FCF_RestorePositionAndDimensions",
	"FCF_SetChatWindowFontSize",
	"FCF_SetLocked",
	"FCF_SetTabPosition",
	"FCF_SetWindowAlpha",
	"FCF_SetWindowColor",
	"FCF_UnDockFrame",
	"FCFDock_GetSelectedWindow",
	"FCFDock_SelectWindow",
	"GENERAL_CHAT_DOCK",
	"GetChatWindowChannels",
	"GetChatWindowInfo",
	"GetChatWindowMessages",
	"GetChatWindowSavedDimensions",
	"GetChatWindowSavedPosition",
	"GetNormalizedRealmName",
	"InCombatLockdown",
	"RED_FONT_COLOR",
	"SetChatColorNameByClass",
	"SetChatWindowSavedDimensions",
	"SetChatWindowSavedPosition",
	"Settings",
	"StaticPopup_Show",
	"UIErrorsFrame",
	"UnitName",
	"strlenutf8",
}

-- The tests set up their own stand-ins for game globals.
files["tests/ExportString.lua"] = {
	globals = { "Constants", "ChatTypeInfo", "C_EncodingUtil" },
}
files["tests/ChatSettings.lua"] = {
	globals = {
		"Constants",
		"C_ChatInfo",
		"ChatTypeInfo",
		"GetChatWindowInfo",
		"GetChatWindowMessages",
		"GetChatWindowChannels",
		"GetChatWindowSavedPosition",
		"GetChatWindowSavedDimensions",
		"GENERAL_CHAT_DOCK",
		"FCFDock_GetSelectedWindow",
		"SAY",
		"GUILD",
	},
}
