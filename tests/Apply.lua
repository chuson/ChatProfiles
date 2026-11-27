-- Tests that applying a profile leaves nothing different, against the model of the client in
-- tests/FakeChat.lua: first for chosen layouts, then for random ones from a fixed seed.

local helpers = dofile("tests/helpers.lua")
local Check, Equal = helpers.Check, helpers.Equal
local FakeChat = dofile("tests/FakeChat.lua")

FakeChat.Install()
local ns = {}
helpers.LoadAddonFile("ChatProfiles/ChatSettings.lua", ns)
local ChatSettings = ns.ChatSettings

local ALL_CATEGORIES = { tabs = true, messagesAndChannels = true, fontAndBackground = true, colors = true }

local function WithFields(window, fields)
	for field, value in pairs(fields or {}) do
		window[field] = value
	end
	return window
end

local function General(fields)
	return WithFields({ key = "window:1", name = "General", docked = true }, fields)
end

local function CombatLog(fields)
	return WithFields({ key = "window:2", name = "Combat Log" }, fields)
end

local function Tab(name, fields)
	return WithFields({ key = "name:" .. name, name = name }, fields)
end

-- Docked tabs other than General are always locked: unlocking one undocks it.
local DOCKED = { docked = true, locked = true }

local function Docked(name, fields)
	return Tab(name, WithFields(helpers.DeepCopy(DOCKED), fields))
end

local function Undocked(window)
	return WithFields(window, {
		docked = false,
		point = "TOPLEFT",
		xOffset = 0.1,
		yOffset = -0.25,
		width = 430,
		height = 120,
	})
end

local function Texts(differences)
	local texts = {}
	for i, difference in ipairs(differences) do
		texts[i] = difference.text
	end
	return texts
end

-- Saves `to` as a profile with `categories`, the way the addon does: by reading it from the client.
local function ProfileOf(to, categories)
	FakeChat.Load(to)
	local live = ChatSettings.Read(categories)
	return { categories = categories, windows = live.windows, colors = live.colors }
end

-- Sets the client up as `from` and applies a profile saved from `to`. Returns what still differs.
local function ApplyTo(from, to, categories)
	local profile = ProfileOf(to, categories or ALL_CATEGORIES)
	FakeChat.Load(from)
	local remaining, firstError = ChatSettings.Apply(profile)
	return Texts(remaining), firstError
end

local function ExpectApplies(description, from, to, categories)
	local remaining, firstError = ApplyTo(from, to, categories)
	Equal(remaining, {}, description .. ": differences remain after applying")
	Check(firstError == nil, description .. ": a change raised an error: " .. tostring(firstError))
end

-- Chosen layouts

ExpectApplies("a fresh character getting a full setup", { windows = { General() } }, {
	windows = {
		General({ fontSize = 16, messageGroups = { "SAY", "GUILD" } }),
		CombatLog(DOCKED),
		Docked("party", { messageGroups = { "PARTY" }, channels = { { name = "Trade", zoneChannelID = 2 } } }),
		Docked("trade", { channels = { { name = "cpTEST", zoneChannelID = 0 } } }),
		Undocked(Tab("whispers", { messageGroups = { "WHISPER" } })),
	},
	colors = { SAY = { r = 1, g = 0.5, b = 0, classColoredNames = true } },
})
ExpectApplies(
	"docked tabs in a different order",
	{ windows = { General(), Docked("trade"), Docked("party"), Docked("whispers") } },
	{ windows = { General(), Docked("party"), Docked("trade"), Docked("whispers") } }
)
ExpectApplies(
	"reordering after a docked Combat Log",
	{ windows = { General(), CombatLog(DOCKED), Docked("trade"), Docked("party") } },
	{ windows = { General(), CombatLog(DOCKED), Docked("party"), Docked("trade") } }
)
ExpectApplies(
	"undocking the Combat Log while reordering",
	{ windows = { General(), CombatLog(DOCKED), Docked("trade"), Docked("party") } },
	{ windows = { General(), Docked("party"), Docked("trade"), Undocked(CombatLog()) } }
)
ExpectApplies(
	"docking the Combat Log and a tab after it",
	{ windows = { General(), Docked("party"), Undocked(CombatLog()), Undocked(Tab("trade")) } },
	{ windows = { General(), CombatLog(DOCKED), Docked("party"), Docked("trade") } }
)
ExpectApplies(
	"a new tab between docked tabs",
	{ windows = { General(), Docked("party"), Docked("trade") } },
	{ windows = { General(), Docked("party"), Docked("loot"), Docked("trade") } }
)
ExpectApplies(
	"undocking a docked tab that isn't selected",
	{ windows = { General(), Docked("party"), Docked("trade") } },
	{ windows = { General(), Docked("trade"), Undocked(Tab("party")) } }
)
ExpectApplies(
	"closing every tab",
	{ windows = { General(), Docked("party"), Undocked(Tab("trade")) } },
	{ windows = { General() } }
)
-- Every custom window is in use, so the extra tab has to close before the new one can open.
local SEVEN_TABS = { "a", "b", "c", "d", "e", "f", "g" }
local fromTabs, toTabs = { General() }, { General() }
for i, name in ipairs(SEVEN_TABS) do
	table.insert(fromTabs, Docked(name))
	table.insert(toTabs, Docked(i == 4 and "new" or name))
end
ExpectApplies("swapping a tab while every window is in use", { windows = fromTabs }, { windows = toTabs })

-- Random layouts. The generator is written out, not math.random, so every Lua version produces
-- the same cases and a failing case number can be run again.

local seed = 20261126
local function Random(n) -- 1 to n
	seed = seed * 16807 % 2147483647
	return seed % n + 1
end
local function Chance()
	return Random(2) == 1
end

local function Shuffled(list)
	local copy = helpers.DeepCopy(list)
	for i = #copy, 2, -1 do
		local j = Random(i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

local function SomeOf(list)
	local chosen = {}
	for _, item in ipairs(list) do
		if Chance() then
			table.insert(chosen, helpers.DeepCopy(item))
		end
	end
	return chosen
end

local TAB_NAMES = { "party", "trade", "whispers", "guild", "loot", "pvp" }
local GROUPS = { "SAY", "GUILD", "PARTY", "LOOT", "SYSTEM" }
local CHANNELS = {
	{ name = "General", zoneChannelID = 1 },
	{ name = "Trade", zoneChannelID = 2 },
	{ name = "cpTEST", zoneChannelID = 0 },
}
local POINTS = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }

local function RandomColor()
	return Random(256) - 1, Random(256) - 1, Random(256) - 1
end

local function RandomSettings(window)
	window.locked = Chance()
	window.fontSize = 10 + Random(8)
	local r, g, b = RandomColor()
	window.r, window.g, window.b, window.a = r / 255, g / 255, b / 255, (Random(256) - 1) / 255
	window.messageGroups = SomeOf(GROUPS)
	window.channels = SomeOf(CHANNELS)
	return window
end

local function RandomlyUndocked(window)
	if Chance() then
		window.docked, window.locked = true, true
		return window, true
	end
	window.docked = false
	window.point = POINTS[Random(#POINTS)]
	window.xOffset, window.yOffset = Random(100) / 200, -Random(100) / 200
	window.width, window.height = 200 + Random(300), 100 + Random(200)
	return window, false
end

local function RandomSetup()
	local docked, undocked = { RandomSettings(General()) }, {}
	local function Add(window)
		local _, isDocked = RandomlyUndocked(RandomSettings(window))
		table.insert(isDocked and docked or undocked, window)
	end
	Add(CombatLog())
	local names = Shuffled(TAB_NAMES)
	for i = 1, Random(#names + 1) - 1 do
		Add(Tab(names[i]))
	end
	local windows = docked
	for _, window in ipairs(undocked) do
		table.insert(windows, window)
	end

	local colors = {}
	for _, chatType in ipairs({ "SAY", "GUILD" }) do
		local r, g, b = RandomColor()
		colors[chatType] = { r = r / 255, g = g / 255, b = b / 255, classColoredNames = Chance() }
	end
	return { windows = windows, colors = colors }
end

-- Each category is on three times in four, with at least one on.
local function RandomCategories()
	local categories, anyOn = {}, false
	for category in pairs(ALL_CATEGORIES) do
		categories[category] = Random(4) > 1
		anyOn = anyOn or categories[category]
	end
	if not anyOn then
		categories.tabs = true
	end
	return categories
end

local CASES = 500
local failedCases = 0
for case = 1, CASES do
	local from, to, categories = RandomSetup(), RandomSetup(), RandomCategories()
	local remaining, firstError = ApplyTo(from, to, categories)
	if #remaining > 0 or firstError then
		failedCases = failedCases + 1
		-- The first few are enough to debug from, and the count says how widespread it is.
		if failedCases <= 3 then
			Equal(remaining, {}, "random case " .. case .. ": differences remain after applying")
			Check(firstError == nil, "random case " .. case .. ": a change raised an error: " .. tostring(firstError))
		end
	end
end
Check(failedCases == 0, failedCases .. " of " .. CASES .. " random cases left differences")

return helpers.Failures()
