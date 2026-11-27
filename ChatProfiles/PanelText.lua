-- The options panel's text: the status line, the list of changes and the export hint, worked out
-- from Profiles. Kept apart from the frames in OptionsPanel.lua so the tests can check it.

local _, ns = ...
local Profiles = ns.Profiles

local PanelText = {}
ns.PanelText = PanelText

local MAX_DETAIL_LINES = 8

-- The categories a profile can save, in the order the panel lists them.
PanelText.CATEGORIES = {
	{
		key = "tabs",
		label = "Tabs",
		description = "Which tabs you have, their order, the position of undocked tabs, and whether each tab is locked",
	},
	{
		key = "messagesAndChannels",
		label = "Message filters",
		description = "Which messages and channels each tab shows",
	},
	{
		key = "fontAndBackground",
		label = "Font and background",
		description = "Text size, background color, and background opacity",
	},
	{ key = "colors", label = "Chat colors", description = "Colors for all message types" },
}

-- Everything the next save would store: checkbox changes first, then each setting that differs.
-- Both are nil when this character has no profile.
function PanelText.UnsavedChanges()
	local differences, duplicateTabNames = Profiles.Differences()
	if not differences then
		return nil
	end
	-- Until the login apply runs, the live settings are this character's own, and nothing saves.
	if Profiles.LoginApplyPending() then
		return {}, {}
	end
	local changes = {}
	local categoryChanges = Profiles.UnsavedCategoryChanges()
	for _, category in ipairs(PanelText.CATEGORIES) do
		local on = categoryChanges[category.key]
		if on ~= nil then
			table.insert(changes, { text = category.label .. (on and " turned on" or " turned off") })
		end
	end
	for _, difference in ipairs(differences) do
		table.insert(changes, difference)
	end
	return changes, duplicateTabNames
end

function PanelText.Status(name, changes)
	if not name then
		return "This character isn't using a profile."
	elseif Profiles.LoginApplyPending() then
		return "Exit combat to apply changes."
	elseif Profiles.LastApplyFailed() then
		return "Some settings couldn't be applied, so changes won't be saved until you reload or log in again."
	elseif #changes == 0 then
		return "Your chat settings match the profile."
	elseif #changes == 1 then
		return "1 unsaved change. It will be saved when you log out."
	end
	return #changes .. " unsaved changes. They'll be saved when you log out."
end

function PanelText.Details(changes, duplicateTabNames)
	local lines = {}
	for i = 1, math.min(#changes, MAX_DETAIL_LINES) do
		table.insert(lines, changes[i].text)
	end
	if #changes > MAX_DETAIL_LINES then
		table.insert(lines, "...and " .. (#changes - MAX_DETAIL_LINES) .. " more")
	end
	if #duplicateTabNames > 0 then
		local names = table.concat(duplicateTabNames, ", ")
		table.insert(lines, "Only the first tab with each of these names is used: " .. names)
	end
	return table.concat(lines, "\n")
end

-- The export is the saved profile, so unsaved changes aren't in it.
function PanelText.ExportHint(changes)
	local hintText = "Control + C to copy"
	if #changes > 0 then
		hintText = hintText .. "  ·  " .. RED_FONT_COLOR:WrapTextInColorCode("Save now to include your changes")
	end
	return hintText
end
