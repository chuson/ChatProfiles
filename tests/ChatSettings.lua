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
	_G[frame.name] = frame
end
local GAME_FUNCTIONS = {
	"FCF_Close",
	"FCF_OpenNewWindow",
	"FCF_SetLocked",
	"FCF_SetChatWindowFontSize",
	"FCF_SetWindowColor",
	"FCF_SetWindowAlpha",
	"ChangeChatColor",
	"SetChatColorNameByClass",
}
for _, name in ipairs(GAME_FUNCTIONS) do
	_G[name] = function(...)
		Record(name, ...)
	end
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
	"the combat log, which has no message groups",
	Live({ CombatLog() }),
	Profile({ CombatLog({ messageGroups = { "SAY" }, channels = { { name = "Trade", zoneChannelID = 2 } } }) }),
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

return helpers.Failures()
