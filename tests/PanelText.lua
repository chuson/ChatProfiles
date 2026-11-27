-- Tests for PanelText: the panel's status line, list of changes and export hint.

local helpers = dofile("tests/helpers.lua")
local Equal = helpers.Equal

RED_FONT_COLOR = {
	WrapTextInColorCode = function(_, text)
		return "|cffff2020" .. text .. "|r"
	end,
}

-- A stand-in for Profiles. Each test sets what it returns.
local state
local FakeProfiles = {
	Differences = function()
		return state.differences, state.duplicateTabNames
	end,
	UnsavedCategoryChanges = function()
		return state.categoryChanges or {}
	end,
	LoginApplyPending = function()
		return state.loginApplyPending
	end,
	LastApplyFailed = function()
		return state.lastApplyFailed
	end,
}

local ns = { Profiles = FakeProfiles }
helpers.LoadAddonFile("ChatProfiles/PanelText.lua", ns)
local PanelText = ns.PanelText

local function Changes(count)
	local changes = {}
	for i = 1, count do
		changes[i] = { text = "change " .. i }
	end
	return changes
end

local function Texts(changes)
	local texts = {}
	for i, change in ipairs(changes) do
		texts[i] = change.text
	end
	return texts
end

-- The list of changes

state = {}
Equal({ PanelText.UnsavedChanges() }, {}, "a character with no profile had changes")

state = { differences = Changes(2), duplicateTabNames = { "trade" }, loginApplyPending = true }
Equal({ PanelText.UnsavedChanges() }, { {}, {} }, "changes were listed while the login apply waits")

state = {
	differences = Changes(1),
	duplicateTabNames = {},
	categoryChanges = { colors = false, tabs = true },
}
local changes, duplicateTabNames = PanelText.UnsavedChanges()
Equal(
	Texts(changes),
	{ "Tabs turned on", "Chat colors turned off", "change 1" },
	"checkbox changes weren't listed first, in the panel's order"
)
Equal(duplicateTabNames, {}, "duplicate tab names weren't passed on")

-- The status line

state = {}
Equal(PanelText.Status(nil, nil), "This character isn't using a profile.", "wrong status without a profile")
state = { loginApplyPending = true, lastApplyFailed = true }
Equal(PanelText.Status("Main", {}), "Exit combat to apply changes.", "wrong status while the login apply waits")
state = { lastApplyFailed = true }
Equal(
	PanelText.Status("Main", Changes(3)),
	"Some settings couldn't be applied, so changes won't be saved until you reload or log in again.",
	"wrong status after a failed apply"
)
state = {}
Equal(PanelText.Status("Main", {}), "Your chat settings match the profile.", "wrong status with no changes")
Equal(
	PanelText.Status("Main", Changes(1)),
	"1 unsaved change. It will be saved when you log out.",
	"wrong status with one change"
)
Equal(
	PanelText.Status("Main", Changes(2)),
	"2 unsaved changes. They'll be saved when you log out.",
	"wrong status with two changes"
)

-- The details under it

Equal(PanelText.Details(Changes(2), {}), "change 1\nchange 2", "wrong details for two changes")
Equal(
	PanelText.Details(Changes(8), {}),
	table.concat(Texts(Changes(8)), "\n"),
	"eight changes weren't all listed"
)
Equal(
	PanelText.Details(Changes(9), {}),
	table.concat(Texts(Changes(8)), "\n") .. "\n...and 1 more",
	"a ninth change wasn't counted instead of listed"
)
Equal(
	PanelText.Details({}, { "trade", "loot" }),
	"Only the first tab with each of these names is used: trade, loot",
	"duplicate tab names weren't listed"
)

-- The export hint

Equal(PanelText.ExportHint({}), "Control + C to copy", "wrong export hint with no changes")
Equal(
	PanelText.ExportHint(Changes(1)),
	"Control + C to copy  ·  |cffff2020Save now to include your changes|r",
	"the export hint didn't say to save first"
)

return helpers.Failures()
