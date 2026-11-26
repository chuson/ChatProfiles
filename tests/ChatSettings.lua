-- Tests for ChatSettings.Diff: what it reports when the live settings and a profile differ, in
-- what order, and what each entry's apply calls.

local helpers = dofile("tests/helpers.lua")
local Check, Equal = helpers.Check, helpers.Equal

-- Stand-ins for the game. Display names come from the client's global strings; a chat type
-- without one (EMOTE here) is shown by its key. The client knows zone channel 2 as "Trade".
Constants = { ChatFrameConstants = { MaxChatWindows = 10 } }
SAY, GUILD = "Say", "Guild"
C_ChatInfo = {
	GetChannelShortcutForChannelID = function(id)
		return id == 2 and "Trade" or nil
	end,
}

-- Every game call an apply makes is recorded as a line, e.g. "FCF_Close ChatFrame4".
local calls = {}
local function Record(name, ...)
	local line = { name }
	for i = 1, select("#", ...) do
		local value = select(i, ...)
		table.insert(line, type(value) == "table" and value.name or tostring(value))
	end
	table.insert(calls, table.concat(line, " "))
end

for windowNumber = 1, 10 do
	local frame = { name = "ChatFrame" .. windowNumber }
	for _, method in ipairs({ "AddMessageGroup", "RemoveMessageGroup", "AddChannel", "RemoveChannel" }) do
		frame[method] = function(self, value)
			Record(self.name .. ":" .. method, value)
		end
	end
	frame.GetID = function()
		return windowNumber
	end
	frame.GetName = function(self)
		return self.name
	end
	_G[frame.name] = frame
	_G[frame.name .. "Tab"] = { name = frame.name .. "Tab" }
end
local GAME_FUNCTIONS = {
	"FCF_Close",
	"FCF_OpenNewWindow",
	"FCF_DockFrame",
	"FCF_UnDockFrame",
	"FCF_SetTabPosition",
	"FCF_CheckShowChatFrame",
	"FCF_RestorePositionAndDimensions",
	"SetChatWindowSavedPosition",
	"SetChatWindowSavedDimensions",
	"FCF_SetLocked",
	"FCF_SetChatWindowFontSize",
	"FCF_SetWindowColor",
	"FCF_SetWindowAlpha",
	"ChangeChatColor",
	"SetChatColorNameByClass",
	"FCFDock_SelectWindow",
}
for _, name in ipairs(GAME_FUNCTIONS) do
	_G[name] = function(...)
		Record(name, ...)
	end
end

-- The dock's selected tab. A test sets it to check that reordering selects it again.
GENERAL_CHAT_DOCK = { name = "GENERAL_CHAT_DOCK" }
local selectedTab
function FCFDock_GetSelectedWindow()
	return selectedTab
end

local ns = {}
helpers.LoadAddonFile("ChatProfiles/ChatSettings.lua", ns)
local Diff = ns.ChatSettings.Diff

local ALL_CATEGORIES = { tabs = true, messagesAndChannels = true, fontAndBackground = true, colors = true }

local function AllCategoriesExcept(category)
	local categories = {}
	for name in pairs(ALL_CATEGORIES) do
		categories[name] = name ~= category
	end
	return categories
end

local function WithFields(window, fields)
	for field, value in pairs(fields or {}) do
		window[field] = value
	end
	return window
end

local function General(fields)
	return WithFields({ key = "window:1", name = "General" }, fields)
end

local function CombatLog(fields)
	return WithFields({ key = "window:2", name = "Combat Log" }, fields)
end

local function Tab(name, fields)
	return WithFields({ key = "name:" .. name, name = name }, fields)
end

-- Live settings in the shape ChatSettings.Read returns. Custom tabs get windows 4, 5, ... in
-- list order, after the three reserved windows.
local function Live(windows, colors)
	local live = { windows = windows, windowNumbers = {}, colors = colors }
	local nextCustomWindow = 4
	for _, window in ipairs(windows) do
		local windowNumber = tonumber(window.key:match("^window:(%d+)$"))
		if not windowNumber then
			windowNumber = nextCustomWindow
			nextCustomWindow = nextCustomWindow + 1
		end
		live.windowNumbers[window.key] = windowNumber
	end
	return live
end

local function Profile(windows, colors, categories)
	return { categories = categories or ALL_CATEGORIES, windows = windows, colors = colors }
end

local function Texts(differences)
	local texts = {}
	for i, difference in ipairs(differences) do
		texts[i] = difference.text
	end
	return texts
end

-- Runs each entry's apply in order and returns the game calls they made.
local function ApplyAll(differences)
	calls = {}
	for _, difference in ipairs(differences) do
		difference.apply()
	end
	return calls
end

local function ExpectDiff(description, live, profile, expectedTexts, expectedCalls)
	local differences = Diff(live, profile)
	Equal(Texts(differences), expectedTexts, description .. ": wrong differences")
	if expectedCalls then
		Equal(ApplyAll(differences), expectedCalls, description .. ": wrong calls on apply")
	end
	return differences
end

-- A General window with every setting filled in, as Read returns it with all categories on.
local function FullGeneral()
	return General({
		locked = true,
		fontSize = 14,
		r = 0,
		g = 0,
		b = 0,
		a = 0.25,
		messageGroups = { "GUILD", "SAY" },
		channels = { { name = "Trade", zoneChannelID = 2 } },
	})
end

-- Nothing differs

ExpectDiff(
	"identical settings",
	Live({ FullGeneral(), CombatLog({ locked = true }), Tab("trade") }, { SAY = { r = 1, g = 1, b = 1 } }),
	Profile({ FullGeneral(), CombatLog({ locked = true }), Tab("trade") }, { SAY = { r = 1, g = 1, b = 1 } }),
	{}
)

-- Tabs

local tabChanges = ExpectDiff(
	"an extra tab and a missing tab",
	Live({ General(), Tab("old") }),
	Profile({ General(), Tab("new") }),
	{ 'Extra tab "old"', 'Missing tab "new"' },
	{ "FCF_Close ChatFrame4", "FCF_OpenNewWindow new true" }
)
Check(
	tabChanges[1].opensOrClosesTab and tabChanges[2].opensOrClosesTab,
	"opening and closing tabs aren't flagged for Apply's first pass"
)

ExpectDiff(
	"an extra tab and a missing tab with Tabs off",
	Live({ General(), Tab("old") }),
	Profile({ General(), Tab("new") }, nil, AllCategoriesExcept("tabs")),
	{}
)
ExpectDiff(
	"General and Combat Log missing from the live settings",
	Live({ Tab("trade") }),
	Profile({ General(), CombatLog(), Tab("trade") }),
	{}
)

-- Lock

local lockChange = ExpectDiff(
	"a different lock",
	Live({ General({ locked = false }) }),
	Profile({ General({ locked = true }) }),
	{ "General: locked differently" },
	{ "FCF_SetLocked ChatFrame1 true" }
)
Check(not lockChange[1].opensOrClosesTab, "a lock change is flagged as opening or closing a tab")

ExpectDiff(
	"a different lock with Tabs off",
	Live({ General({ locked = false }) }),
	Profile({ General({ locked = true }) }, nil, AllCategoriesExcept("tabs")),
	{}
)
ExpectDiff(
	"a profile without a lock",
	Live({ General({ locked = false }) }),
	Profile({ General() }),
	{}
)

-- Dock state, position and size

local UNDOCKED = { docked = false, point = "TOPLEFT", xOffset = 0.1, yOffset = -0.25, width = 430, height = 120 }

ExpectDiff(
	"an undocked tab the profile has docked",
	Live({ General({ docked = true }), Tab("whispers", UNDOCKED) }),
	Profile({ General({ docked = true }), Tab("whispers", { docked = true }) }),
	{ "whispers: undocked instead of docked" },
	{ "FCF_DockFrame ChatFrame4 2" }
)
ExpectDiff(
	"docking a tab after other docked tabs",
	Live({ General({ docked = true }), Tab("party", { docked = true }), Tab("whispers", UNDOCKED) }),
	Profile({ General({ docked = true }), Tab("party", { docked = true }), Tab("whispers", { docked = true }) }),
	{ "whispers: undocked instead of docked" },
	{ "FCF_DockFrame ChatFrame5 3" }
)
ExpectDiff(
	"a docked tab the profile has undocked",
	Live({ General({ docked = true }), Tab("whispers", { docked = true }) }),
	Profile({ General({ docked = true }), Tab("whispers", UNDOCKED) }),
	{ "whispers: docked instead of undocked", "whispers: different position", "whispers: different size" },
	{
		"FCF_UnDockFrame ChatFrame4",
		"FCF_SetTabPosition ChatFrame4 0",
		"FCF_CheckShowChatFrame ChatFrame4",
		"FCF_CheckShowChatFrame ChatFrame4Tab",
		"SetChatWindowSavedPosition 4 TOPLEFT 0.1 -0.25",
		"FCF_RestorePositionAndDimensions ChatFrame4",
		"SetChatWindowSavedDimensions 4 430 120",
		"FCF_RestorePositionAndDimensions ChatFrame4",
	}
)
ExpectDiff(
	"an undocked tab in a different position",
	Live({ Tab("whispers", UNDOCKED) }),
	Profile({ Tab("whispers", WithFields(helpers.DeepCopy(UNDOCKED), { xOffset = 0.2 })) }),
	{ "whispers: different position" },
	{ "SetChatWindowSavedPosition 4 TOPLEFT 0.2 -0.25", "FCF_RestorePositionAndDimensions ChatFrame4" }
)
ExpectDiff(
	"an undocked tab in a different corner",
	Live({ Tab("whispers", UNDOCKED) }),
	Profile({ Tab("whispers", WithFields(helpers.DeepCopy(UNDOCKED), { point = "BOTTOMLEFT" })) }),
	{ "whispers: different position" }
)
ExpectDiff(
	"an undocked tab of a different size",
	Live({ Tab("whispers", UNDOCKED) }),
	Profile({ Tab("whispers", WithFields(helpers.DeepCopy(UNDOCKED), { height = 200 })) }),
	{ "whispers: different size" },
	{ "SetChatWindowSavedDimensions 4 430 200", "FCF_RestorePositionAndDimensions ChatFrame4" }
)
ExpectDiff(
	"a position and size within rounding of each other",
	Live({ Tab("whispers", WithFields(helpers.DeepCopy(UNDOCKED), { xOffset = 0.1004, width = 429.99997 })) }),
	Profile({ Tab("whispers", UNDOCKED) }),
	{}
)
ExpectDiff(
	"an undocked tab the profile has no position for",
	Live({ Tab("whispers", { docked = true }) }),
	Profile({ Tab("whispers", { docked = false }) }),
	{ "whispers: docked instead of undocked" }
)
ExpectDiff(
	"a profile saved before dock state was stored",
	Live({ General({ docked = true }), Tab("whispers", UNDOCKED) }),
	Profile({ General(), Tab("whispers") }),
	{}
)
ExpectDiff(
	"a different dock state with Tabs off",
	Live({ Tab("whispers", UNDOCKED) }),
	Profile({ Tab("whispers", { docked = true }) }, nil, AllCategoriesExcept("tabs")),
	{}
)
ExpectDiff(
	"docking a tab that should also be locked",
	Live({ Tab("whispers", WithFields(helpers.DeepCopy(UNDOCKED), { locked = false })) }),
	Profile({ Tab("whispers", { docked = true, locked = true }) }),
	{ "whispers: undocked instead of docked", "whispers: locked differently" }
)

-- Tab order. Live tabs here get windows 4, 5, ... in list order, and Read lists docked tabs in
-- dock order, so the order of the Live list is the dock order.

local function Docked(name)
	return Tab(name, { docked = true })
end

ExpectDiff(
	"docked tabs in the profile's order",
	Live({ General({ docked = true }), Docked("party"), Docked("trade") }),
	Profile({ General({ docked = true }), Docked("party"), Docked("trade") }),
	{}
)
local reorder = ExpectDiff(
	"docked tabs in a different order",
	Live({ General({ docked = true }), Docked("trade"), Docked("party"), Docked("whispers") }),
	Profile({ General({ docked = true }), Docked("party"), Docked("trade"), Docked("whispers") }),
	{ "Tabs in a different order" },
	{
		"FCF_UnDockFrame ChatFrame5",
		"FCF_DockFrame ChatFrame5 2",
		"FCF_UnDockFrame ChatFrame4",
		"FCF_DockFrame ChatFrame4 3",
		"FCF_UnDockFrame ChatFrame6",
		"FCF_DockFrame ChatFrame6 4",
	}
)
Check(not reorder[1].opensOrClosesTab, "reordering is flagged as opening or closing a tab")

selectedTab = ChatFrame4
Equal(
	ApplyAll(Diff(
		Live({ General({ docked = true }), Docked("trade"), Docked("party") }),
		Profile({ General({ docked = true }), Docked("party"), Docked("trade") })
	))[5],
	"FCFDock_SelectWindow GENERAL_CHAT_DOCK ChatFrame4",
	"the selected tab wasn't selected again after reordering"
)
selectedTab = nil

ExpectDiff(
	"an order that differs only by a tab about to be docked",
	Live({ General({ docked = true }), Docked("party"), Tab("trade", UNDOCKED) }),
	Profile({ General({ docked = true }), Docked("trade"), Docked("party") }),
	{ "trade: undocked instead of docked" },
	{ "FCF_DockFrame ChatFrame5 2" }
)
ExpectDiff(
	"an order that differs only by a tab the profile has undocked",
	Live({ General({ docked = true }), Docked("trade"), Docked("party") }),
	Profile({ General({ docked = true }), Docked("party"), Tab("trade", { docked = false }) }),
	{ "trade: docked instead of undocked" }
)
ExpectDiff(
	"a different order from a profile saved before dock state was stored",
	Live({ General({ docked = true }), Docked("trade"), Docked("party") }),
	Profile({ General(), Tab("party"), Tab("trade") }),
	{ "Tabs in a different order" }
)
ExpectDiff(
	"a different order with Tabs off",
	Live({ General({ docked = true }), Docked("trade"), Docked("party") }),
	Profile({ General(), Docked("party"), Docked("trade") }, nil, AllCategoriesExcept("tabs")),
	{}
)
ExpectDiff(
	"reordering before a lock change",
	Live({ General({ docked = true }), Docked("trade"), Tab("party", { docked = true, locked = false }) }),
	Profile({ General({ docked = true }), Tab("party", { docked = true, locked = true }), Docked("trade") }),
	{ "Tabs in a different order", "party: locked differently" }
)

-- The Combat Log is a static tab: the dock always draws it right after General.
ExpectDiff(
	"a profile with the Combat Log after other docked tabs",
	Live({ General({ docked = true }), CombatLog({ docked = true }), Docked("party"), Docked("trade") }),
	Profile({ General({ docked = true }), Docked("party"), Docked("trade"), CombatLog({ docked = true }) }),
	{}
)
ExpectDiff(
	"reordering after a docked Combat Log",
	Live({ General({ docked = true }), CombatLog({ docked = true }), Docked("trade"), Docked("party") }),
	Profile({ General({ docked = true }), CombatLog({ docked = true }), Docked("party"), Docked("trade") }),
	{ "Tabs in a different order" },
	{
		"FCF_UnDockFrame ChatFrame5",
		"FCF_DockFrame ChatFrame5 3",
		"FCF_UnDockFrame ChatFrame4",
		"FCF_DockFrame ChatFrame4 4",
	}
)
ExpectDiff(
	"docking the Combat Log and a tab after it",
	Live({ General({ docked = true }), Docked("party"), CombatLog(UNDOCKED), Tab("trade", UNDOCKED) }),
	Profile({ General({ docked = true }), Docked("party"), Docked("trade"), CombatLog({ docked = true }) }),
	{ "trade: undocked instead of docked", "Combat Log: undocked instead of docked" },
	{ "FCF_DockFrame ChatFrame5 4", "FCF_DockFrame ChatFrame2 2" }
)

-- Font and background

local looks = { fontSize = 12, r = 0.5, g = 0, b = 0, a = 0.25 }
ExpectDiff(
	"a different font size, background color and opacity",
	Live({ General(looks) }),
	Profile({ General({ fontSize = 14, r = 0.6, g = 0, b = 0, a = 0.5 }) }),
	{
		"General: different font size",
		"General: different background color",
		"General: different background opacity",
	},
	{
		"FCF_SetChatWindowFontSize nil ChatFrame1 14",
		"FCF_SetWindowColor ChatFrame1 0.6 0 0",
		"FCF_SetWindowAlpha ChatFrame1 0.5",
	}
)
ExpectDiff(
	"colors within rounding of each other",
	Live({ General(looks) }),
	Profile({ General({ fontSize = 12, r = 0.505, g = 0.004, b = 0, a = 0.255 }) }),
	{}
)
ExpectDiff(
	"font size 0, which means it was never set",
	Live({ General(looks) }),
	Profile({ General({ fontSize = 0 }) }),
	{}
)
ExpectDiff(
	"a profile without font or background settings",
	Live({ General(looks) }),
	Profile({ General() }),
	{}
)
ExpectDiff(
	"different font and background with that category off",
	Live({ General(looks) }),
	Profile(
		{ General({ fontSize = 14, r = 0.6, g = 0, b = 0, a = 0.5 }) },
		nil,
		AllCategoriesExcept("fontAndBackground")
	),
	{}
)

-- Message groups

ExpectDiff(
	"missing and extra message groups",
	Live({ General({ messageGroups = { "EMOTE", "SAY" } }) }),
	Profile({ General({ messageGroups = { "GUILD", "SAY" } }) }),
	{ "General: doesn't show Guild messages", "General: also shows EMOTE messages" },
	{ "ChatFrame1:AddMessageGroup GUILD", "ChatFrame1:RemoveMessageGroup EMOTE" }
)
ExpectDiff(
	"a profile saved while Message filters was off",
	Live({ General({ messageGroups = { "SAY" } }) }),
	Profile({ General() }),
	{}
)
ExpectDiff(
	"different message groups on the Combat Log",
	Live({ CombatLog({ messageGroups = { "LOOT", "OPENING" }, channels = {} }) }),
	Profile({ CombatLog({ messageGroups = { "OPENING", "SKILL" }, channels = {} }) }),
	{ "Combat Log: doesn't show SKILL messages", "Combat Log: also shows LOOT messages" },
	{ "ChatFrame2:AddMessageGroup SKILL", "ChatFrame2:RemoveMessageGroup LOOT" }
)
ExpectDiff(
	"a Combat Log saved before its message groups were saved",
	Live({ CombatLog({ messageGroups = { "LOOT", "OPENING" }, channels = {} }) }),
	Profile({ CombatLog() }),
	{}
)
ExpectDiff(
	"different message groups with Message filters off",
	Live({ General({ messageGroups = { "EMOTE" } }) }),
	Profile({ General({ messageGroups = { "GUILD" } }) }, nil, AllCategoriesExcept("messagesAndChannels")),
	{}
)

-- Channels

local function Channels(...)
	local channels = {}
	for i = 1, select("#", ...), 2 do
		table.insert(channels, { name = select(i, ...), zoneChannelID = select(i + 1, ...) })
	end
	return General({ channels = channels })
end

ExpectDiff(
	"a zone channel with a name from another language",
	Live({ Channels("Handel", 2) }),
	Profile({ Channels("Trade", 2) }),
	{}
)
ExpectDiff(
	"a custom channel in different case",
	Live({ Channels("cpTEST", 0) }),
	Profile({ Channels("Cptest", 0) }),
	{}
)
ExpectDiff(
	"a missing zone channel saved in another language",
	Live({ Channels() }),
	Profile({ Channels("Commerce", 2) }),
	{ "General: doesn't show the Trade channel" },
	{ "ChatFrame1:AddChannel Trade" }
)
ExpectDiff(
	"a missing zone channel this client doesn't know",
	Live({ Channels() }),
	Profile({ Channels("Newcomers", 99) }),
	{ "General: doesn't show the Newcomers channel" },
	{ "ChatFrame1:AddChannel Newcomers" }
)
ExpectDiff(
	"a missing custom channel",
	Live({ Channels() }),
	Profile({ Channels("cpTEST", 0) }),
	{ "General: doesn't show the cpTEST channel" },
	{ "ChatFrame1:AddChannel cpTEST" }
)
ExpectDiff(
	"an extra channel",
	Live({ Channels("Handel", 2) }),
	Profile({ Channels() }),
	{ "General: also shows the Handel channel" },
	{ "ChatFrame1:RemoveChannel Handel" }
)

-- Chat colors

ExpectDiff(
	"a different color and different name coloring",
	Live({ General() }, {
		SAY = { r = 1, g = 1, b = 1 },
		GUILD = { r = 0.25, g = 1, b = 0.25, classColoredNames = false },
	}),
	Profile({ General() }, {
		SAY = { r = 1, g = 0, b = 0 },
		GUILD = { r = 0.25, g = 1, b = 0.25, classColoredNames = true },
	}),
	{ "Different name coloring for Guild", "Different color for Say" },
	{ "SetChatColorNameByClass GUILD true", "ChangeChatColor SAY 1 0 0" }
)
ExpectDiff(
	"a chat type this client doesn't have",
	Live({ General() }, {}),
	Profile({ General() }, { WHISPER_FROM_ANOTHER_CLIENT = { r = 1, g = 0, b = 0 } }),
	{}
)
ExpectDiff(
	"colors within rounding of each other",
	Live({ General() }, { SAY = { r = 1, g = 1, b = 1 } }),
	Profile({ General() }, { SAY = { r = 0.996, g = 1, b = 1 } }),
	{}
)
ExpectDiff(
	"name coloring that only one side reports",
	Live({ General() }, { SAY = { r = 1, g = 1, b = 1 } }),
	Profile({ General() }, { SAY = { r = 1, g = 1, b = 1, classColoredNames = true } }),
	{}
)
ExpectDiff(
	"a profile without colors",
	Live({ General() }, { SAY = { r = 1, g = 1, b = 1 } }),
	Profile({ General() }),
	{}
)
ExpectDiff(
	"different colors with Chat colors off",
	Live({ General() }, { SAY = { r = 1, g = 1, b = 1 } }),
	Profile({ General() }, { SAY = { r = 1, g = 0, b = 0 } }, AllCategoriesExcept("colors")),
	{}
)

-- Order: tabs close first, so a new one can open when every window is in use. Then each
-- profile tab in order, then colors.

ExpectDiff(
	"changes of every kind",
	Live({ General({ locked = false }), Tab("old") }, { SAY = { r = 1, g = 1, b = 1 } }),
	Profile({ General({ locked = true }), Tab("new") }, { SAY = { r = 1, g = 0, b = 0 } }),
	{ 'Extra tab "old"', "General: locked differently", 'Missing tab "new"', "Different color for Say" }
)

-- Reading. The game's chat functions replay tests/fixtures/ChatRecording.lua, which was
-- recorded from a real client, so Read is checked against what the game actually returns.

helpers.LoadAddonFile("ChatProfiles/ExportString.lua", ns)
local Read, Validate = ns.ChatSettings.Read, ns.ExportString.Validate
local Unpack = helpers.Unpack

local RECORDING = dofile("tests/fixtures/ChatRecording.lua")
local recording

function GetChatWindowInfo(windowNumber)
	-- 10 values, some of them nil, so the length is given.
	return Unpack(recording.windows[windowNumber].info, 1, 10)
end
function GetChatWindowMessages(windowNumber)
	return Unpack(recording.windows[windowNumber].messageGroups)
end
function GetChatWindowChannels(windowNumber)
	return Unpack(recording.windows[windowNumber].channels)
end
function GetChatWindowSavedPosition(windowNumber)
	return Unpack(recording.windows[windowNumber].savedPosition or {})
end
function GetChatWindowSavedDimensions(windowNumber)
	return Unpack(recording.windows[windowNumber].savedSize or {})
end
C_ChatInfo.GetNumReservedChatWindows = function()
	return recording.reserved
end

-- Replays a copy of the recording, after `change` edits it.
local function UseRecording(change)
	recording = helpers.DeepCopy(RECORDING)
	if change then
		change(recording)
	end
	local entries = {}
	for chatType, color in pairs(recording.colors) do
		entries[chatType] = { r = color[1], g = color[2], b = color[3], colorNameByClass = color[4] }
	end
	ChatTypeInfo = helpers.ChatTypeInfoProxy(entries)
end

local function Keys(windows)
	local keys = {}
	for i, window in ipairs(windows) do
		keys[i] = window.key
	end
	return keys
end

local function WindowWithKey(windows, key)
	for _, window in ipairs(windows) do
		if window.key == key then
			return window
		end
	end
end

local function IsSorted(list)
	for i = 2, #list do
		if list[i - 1] > list[i] then
			return false
		end
	end
	return true
end

-- In the recording, General, party and trade are docked in that order, and Combat Log and
-- whispers are undocked. Undocked tabs come after docked ones, by window number.
local RECORDED_KEYS = { "window:1", "name:party", "name:trade", "window:2", "name:whispers" }

UseRecording()
local live = Read(ALL_CATEGORIES)

Equal(Keys(live.windows), RECORDED_KEYS, "Read didn't return the docked tabs in dock order, then the undocked ones")
Equal(
	live.windowNumbers,
	{ ["window:1"] = 1, ["window:2"] = 2, ["name:party"] = 4, ["name:trade"] = 5, ["name:whispers"] = 6 },
	"Read returned the wrong window numbers"
)
Equal(live.duplicateTabNames, {}, "Read found duplicate tab names in a recording without any")

Equal(WindowWithKey(live.windows, "name:party"), {
	key = "name:party",
	name = "party",
	locked = true,
	docked = true,
	fontSize = 18,
	r = 0,
	g = 0,
	b = 0,
	a = 0.2470588386058807,
	messageGroups = { "BN_WHISPER", "CHANNEL", "PARTY", "PARTY_LEADER", "WHISPER" },
	channels = {},
}, "a docked tab that isn't selected (shown = false) wasn't read correctly")

local whispers = WindowWithKey(live.windows, "name:whispers")
Equal(whispers.locked, false, "an unlocked undocked tab wasn't read as unlocked")
Equal(whispers.docked, false, "an undocked tab wasn't read as undocked")
Equal(WindowWithKey(live.windows, "window:2").docked, false, "the undocked Combat Log wasn't read as undocked")
Equal(WindowWithKey(live.windows, "window:1").docked, true, "General wasn't read as docked")

-- Undocked tabs store the saved position and size the client returned.
local function PositionAndSize(window)
	return { window.point, window.xOffset, window.yOffset, window.width, window.height }
end
local function Recorded(windowNumber)
	local position, size = RECORDING.windows[windowNumber].savedPosition, RECORDING.windows[windowNumber].savedSize
	return { position[1], position[2], position[3], size[1], size[2] }
end
Equal(PositionAndSize(whispers), Recorded(6), "an undocked tab's position or size wasn't read")
Equal(
	PositionAndSize(WindowWithKey(live.windows, "window:2")),
	Recorded(2),
	"the undocked Combat Log's position or size wasn't read"
)

-- trade was undocked and docked again, so the client still has a saved position and size for it.
-- Docked tabs follow General, so neither is stored.
local trade = WindowWithKey(live.windows, "name:trade")
Check(RECORDING.windows[5].savedPosition ~= nil, "the recording no longer has a stale position for trade")
Equal(PositionAndSize(trade), {}, "a docked tab's stale position or size was read")

Equal(WindowWithKey(live.windows, "name:trade").channels, {
	{ name = "General", zoneChannelID = 1 },
	{ name = "LocalDefense", zoneChannelID = 22 },
	{ name = "Services", zoneChannelID = 42 },
	{ name = "Trade", zoneChannelID = 2 },
	{ name = "TradeLocal", zoneChannelID = 46 },
}, "zone channels weren't read as sorted name and ID pairs")

local general = WindowWithKey(live.windows, "window:1")
Equal(general.channels, {
	{ name = "ChromieTime", zoneChannelID = 36 },
	{ name = "NewcomerChat", zoneChannelID = 32 },
	{ name = "OOC", zoneChannelID = 47 },
	{ name = "ShadowlandsBetaDiscussion", zoneChannelID = 33 },
	{ name = "ShadowlandsPTRDiscussion", zoneChannelID = 34 },
	{ name = "WarWithinTestDiscussion", zoneChannelID = 35 },
}, "General's channels weren't read as sorted name and ID pairs")
Check(
	#general.messageGroups == #RECORDING.windows[1].messageGroups and IsSorted(general.messageGroups),
	"General's message groups weren't all read, or weren't sorted"
)
Equal(general.fontSize, 0, "a font size that was never set wasn't read as 0")

local combatLog = WindowWithKey(live.windows, "window:2")
Equal(combatLog.messageGroups, {
	"COMBAT_HONOR_GAIN",
	"COMBAT_MISC_INFO",
	"COMBAT_XP_GAIN",
	"OPENING",
	"PET_INFO",
	"TRADESKILLS",
}, "the Combat Log's message groups weren't read")
Equal(combatLog.channels, {}, "the Combat Log's empty channel list wasn't read")

local colorCount, recordedColorCount = 0, 0
for _ in pairs(live.colors) do
	colorCount = colorCount + 1
end
for _ in pairs(RECORDING.colors) do
	recordedColorCount = recordedColorCount + 1
end
Equal(colorCount, recordedColorCount, "Read didn't find every chat color through the ChatTypeInfo proxy")
Equal(live.colors.SAY, { r = 1, g = 1, b = 1, classColoredNames = false }, "Say's color wasn't read correctly")
Equal(live.colors.BN_ALERT, { r = 1, g = 1, b = 1 }, "a chat type without name coloring reported the flag")

-- Categories that are turned off

UseRecording()
local tabsOnly = Read({ tabs = true })
Equal(
	WindowWithKey(tabsOnly.windows, "name:party"),
	{ key = "name:party", name = "party", locked = true, docked = true },
	"Tabs alone read more than tabs"
)
Check(tabsOnly.colors == nil, "colors were read with Chat colors off")

local looksOnly = Read({ fontAndBackground = true })
Equal(WindowWithKey(looksOnly.windows, "name:party"), {
	key = "name:party",
	name = "party",
	fontSize = 18,
	r = 0,
	g = 0,
	b = 0,
	a = 0.2470588386058807,
}, "Font and background alone read the wrong fields")

-- Cases the recording doesn't have, made by editing a copy. A closed window reports
-- shown = false and docked = nil, as the unused windows do in the recording.

UseRecording(function(r)
	r.windows[6].info[1] = "trade"
end)
local duplicate = Read(ALL_CATEGORIES)
Equal(
	Keys(duplicate.windows),
	{ "window:1", "name:party", "name:trade", "window:2" },
	"a second tab named trade was read"
)
Equal(duplicate.duplicateTabNames, { "trade" }, "a duplicate tab name wasn't listed")
Equal(duplicate.windowNumbers["name:trade"], 5, "the first tab named trade wasn't the one kept")

UseRecording(function(r)
	r.windows[3].info[9] = 6 -- the Voice tab is docked while voice transcription is on
end)
Equal(Keys(Read(ALL_CATEGORIES).windows), RECORDED_KEYS, "the Voice tab was read")

UseRecording(function(r)
	r.windows[7].info[1] = "old" -- a closed tab keeps its name, with shown = false and docked = nil
end)
Equal(Keys(Read(ALL_CATEGORIES).windows), RECORDED_KEYS, "a closed tab that kept its name was read")

-- The whole path: settings read from the client match themselves and pass the import validator.

UseRecording()
local recorded = Read(ALL_CATEGORIES)
local recordedProfile = { categories = ALL_CATEGORIES, windows = recorded.windows, colors = recorded.colors }
Equal(Texts(Diff(Read(ALL_CATEGORIES), recordedProfile)), {}, "settings read from the client differ from themselves")
local validated, reason = Validate(recordedProfile)
Check(validated ~= nil, "settings read from the client fail the import validator: " .. tostring(reason))
if validated then
	Equal(validated, recordedProfile, "the import validator changed settings read from the client")
end

return helpers.Failures()
