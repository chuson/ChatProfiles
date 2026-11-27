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
local GAME_APIS = {
	"C_ChatInfo",
	"C_EncodingUtil",
	"C_Timer",
	"ChangeChatColor",
	"ChatTypeInfo",
	"Constants",
	"CopyTable",
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

read_globals = GAME_APIS

-- The tests replace the game with stand-ins, and each test file runs in its own Lua process, so
-- they may set any game API. They also set chat types' display names, and swap print to keep
-- what the addon prints.
local testGlobals = { "SAY", "GUILD", "print" }
for _, name in ipairs(GAME_APIS) do
	table.insert(testGlobals, name)
end
files["tests/**/*.lua"] = { globals = testGlobals }

-- The recording converter runs outside the game, with its command-line arguments in `arg`.
files["tests/record-fixture.lua"] = { read_globals = { "arg" } }
