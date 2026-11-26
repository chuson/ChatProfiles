-- The options panel. It's under Esc > Options > AddOns > ChatProfiles, and /chatprofiles or /chatp opens it too.

local _, ns = ...
local Profiles, ExportString = ns.Profiles, ns.ExportString

local LEFT_MARGIN = 16
local CONTENT_WIDTH = 600
local MAX_DETAIL_LINES = 8
local CATEGORIES = {
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

local panel = CreateFrame("Frame")
-- New frames start shown. SettingsPanelMixin:DisplayLayout reparents the panel into a canvas that
-- may already be visible, then calls Show, so a shown panel would never fire OnShow the first time.
panel:Hide()
local settingsCategory = Settings.RegisterCanvasLayoutCategory(panel, "ChatProfiles")
Settings.RegisterAddOnCategory(settingsCategory)

-- The widgets are built the first time the panel opens, since most sessions never open it.
local widgets

local function StatusText(name, applyFailed, differences)
	if not name then
		return "This character isn't using a profile."
	elseif applyFailed then
		return "Some settings couldn't be applied, so changes won't be saved until you reload or log in again."
	elseif #differences == 0 then
		return "Your chat settings match the profile."
	elseif #differences == 1 then
		return "1 unsaved change. It will be saved when you log out."
	end
	return #differences .. " unsaved changes. They'll be saved when you log out."
end

local function DetailText(differences, duplicateTabNames)
	local lines = {}
	for i = 1, math.min(#differences, MAX_DETAIL_LINES) do
		table.insert(lines, differences[i].text)
	end
	if #differences > MAX_DETAIL_LINES then
		table.insert(lines, "...and " .. (#differences - MAX_DETAIL_LINES) .. " more")
	end
	if #duplicateTabNames > 0 then
		local names = table.concat(duplicateTabNames, ", ")
		table.insert(lines, "Only the first tab with each of these names is used: " .. names)
	end
	return table.concat(lines, "\n")
end

-- Everything the next save would store: checkbox changes first, then each setting that differs.
-- Both are nil when this character has no profile.
local function UnsavedChanges()
	local differences, duplicateTabNames = Profiles.Differences()
	if not differences then
		return nil
	end
	local changes = {}
	local categoryChanges = Profiles.UnsavedCategoryChanges()
	for _, category in ipairs(CATEGORIES) do
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

local function Refresh()
	local name, profile = Profiles.Selected()
	local applyFailed = Profiles.LastApplyFailed()
	local categories = Profiles.Categories()

	-- The dropdown doesn't notice profile changes on its own.
	widgets.dropdown:GenerateMenu()
	for _, checkbox in ipairs(widgets.checkboxes) do
		checkbox:SetChecked(categories ~= nil and categories[checkbox.category])
		checkbox:SetEnabled(profile ~= nil)
	end
	-- With every box unchecked, saving would keep nothing, so it waits for one to be checked.
	local hasCategory = categories ~= nil and Profiles.HasCategoryOn(categories)
	widgets.categoryWarning:SetShown(profile ~= nil and not hasCategory)
	widgets.rename:SetEnabled(profile ~= nil)
	widgets.delete:SetEnabled(profile ~= nil)
	widgets.export:SetEnabled(profile ~= nil)
	widgets.saveNow:SetEnabled(hasCategory and not applyFailed)

	local changes, duplicateTabNames = UnsavedChanges()
	widgets.status:SetText(StatusText(name, applyFailed, changes))
	widgets.details:SetText(DetailText(changes or {}, duplicateTabNames or {}))
	widgets.UpdateExport()
end

local function ShowMessage(text)
	widgets.message:SetText(text or "")
end

local function SwitchProfile(name)
	local remaining, reason = Profiles.Select(name)
	if not remaining then
		ShowMessage(reason)
	elseif #remaining > 0 then
		ShowMessage("Some settings couldn't be applied. They're listed above.")
	else
		ShowMessage(nil)
	end
	Refresh()
end

local function HidePasteArea()
	for _, part in ipairs(widgets.pasteArea) do
		part:Hide()
	end
end

-- New, Rename and Import ask for a name in this popup, and `data.save` saves it. Returning
-- true keeps the popup open, so a rejected name can be fixed.
local function AcceptName(dialog, data)
	local name, reason = data.save(dialog:GetEditBox():GetText())
	if not name then
		UIErrorsFrame:AddMessage(reason, RED_FONT_COLOR:GetRGB())
		return true
	end
	if data.onSaved then
		data.onSaved()
	end
	ShowMessage(data.successText:format(name))
	Refresh()
end

StaticPopupDialogs.CHAT_PROFILES_NAME = {
	text = "%s",
	button1 = "Save",
	button2 = "Cancel",
	hasEditBox = true,
	OnShow = function(dialog, data)
		-- The popup clears its box when it hides, so the text is set again on every show.
		local editBox = dialog:GetEditBox()
		editBox:SetMaxLetters(Profiles.MAX_PROFILE_NAME_LENGTH)
		editBox:SetText(data.currentName or "")
		editBox:HighlightText()
		editBox:SetFocus()
	end,
	OnAccept = AcceptName,
	-- Enter doesn't press Save on its own.
	EditBoxOnEnterPressed = function(editBox, data)
		local dialog = editBox:GetParent()
		if not AcceptName(dialog, data) then
			dialog:Hide()
		end
	end,
	EditBoxOnEscapePressed = function(editBox)
		editBox:GetParent():Hide()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

local function AskForName(prompt, data)
	StaticPopup_Show("CHAT_PROFILES_NAME", prompt, nil, data)
end

StaticPopupDialogs.CHAT_PROFILES_DELETE = {
	text = 'Delete "%s"? Characters using it keep their chat settings.',
	button1 = "Delete",
	button2 = "Cancel",
	OnAccept = function(_, name)
		Profiles.Delete(name)
		ShowMessage('Deleted "' .. name .. '".')
		Refresh()
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

-- A character that isn't using a profile may have settings that match no profile, and applying
-- one would lose them.
StaticPopupDialogs.CHAT_PROFILES_REPLACE = {
	text = 'This character\'s chat settings don\'t match any of your profiles. Replace them with "%s"?\n\n'
		.. "To keep them, cancel and click New first.",
	button1 = "Replace",
	button2 = "Cancel",
	OnAccept = function(_, name)
		SwitchProfile(name)
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

local function SelectProfile(name)
	if name and not Profiles.Selected() and Profiles.WouldLoseUnsavedSettings(name) then
		StaticPopup_Show("CHAT_PROFILES_REPLACE", name, nil, name)
	else
		SwitchProfile(name)
	end
end

local function Label(text, font, anchor, x, y)
	local label = panel:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
	label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x or 0, y or -16)
	label:SetJustifyH("LEFT")
	label:SetText(text)
	return label
end

local function Button(text, width, onClick)
	local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	button:SetText(text)
	button:SetSize(width, 22)
	button:SetScript("OnClick", onClick)
	return button
end

-- A gold heading with a line under it. Returns the line, so the section's contents can sit below it.
local function SectionHeading(text, anchor)
	local heading = Label(text, "GameFontNormal", anchor, 0, -20)
	local line = panel:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(1, 1, 1, 0.15)
	line:SetSize(CONTENT_WIDTH, 1)
	line:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -4)
	return line
end

local function BuildProfileSection(anchor)
	local line = SectionHeading("Profile", anchor)

	widgets.dropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
	widgets.dropdown:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, -12)
	widgets.dropdown:SetWidth(220)
	widgets.dropdown:SetupMenu(function(_, root)
		root:CreateRadio("None", function()
			return Profiles.Selected() == nil
		end, function()
			SelectProfile(nil)
		end)
		for _, name in ipairs(Profiles.Names()) do
			root:CreateRadio(name, function()
				return Profiles.Selected() == name
			end, function()
				SelectProfile(name)
			end)
		end
	end)

	local new = Button("New", 80, function()
		AskForName("Name the new profile. It starts from your current chat settings.", {
			save = Profiles.SaveAsNew,
			successText = 'Saved your chat settings as "%s". This character now uses it.',
		})
	end)
	new:SetPoint("LEFT", widgets.dropdown, "RIGHT", 12, 0)

	widgets.rename = Button("Rename", 80, function()
		local oldName = Profiles.Selected()
		AskForName("Rename the profile:", {
			currentName = oldName,
			save = function(name)
				return Profiles.Rename(oldName, name)
			end,
			successText = 'Renamed to "%s".',
		})
	end)
	widgets.rename:SetPoint("LEFT", new, "RIGHT", 6, 0)

	widgets.delete = Button("Delete", 80, function()
		local name = Profiles.Selected()
		StaticPopup_Show("CHAT_PROFILES_DELETE", name, nil, name)
	end)
	widgets.delete:SetPoint("LEFT", widgets.rename, "RIGHT", 6, 0)

	widgets.saveNow = Button("Save now", 100, function()
		Profiles.SaveSelected()
		ShowMessage('Saved your chat settings to "' .. Profiles.Selected() .. '".')
		Refresh()
	end)
	widgets.saveNow:SetPoint("TOPLEFT", widgets.dropdown, "BOTTOMLEFT", 0, -12)

	widgets.status = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	widgets.status:SetPoint("LEFT", widgets.saveNow, "RIGHT", 12, 0)
	widgets.status:SetWidth(CONTENT_WIDTH - widgets.saveNow:GetWidth() - 12)
	widgets.status:SetJustifyH("LEFT")

	widgets.details = Label("", "GameFontDisableSmall", widgets.saveNow, 0, -8)
	widgets.details:SetWidth(CONTENT_WIDTH)
	return widgets.details
end

local function BuildCategorySection(anchor)
	local line = SectionHeading("Saved in this profile", anchor)
	widgets.checkboxes = {}
	local previous
	for _, category in ipairs(CATEGORIES) do
		local checkbox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
		if previous then
			checkbox:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -6)
		else
			checkbox:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, -8)
		end
		checkbox.Text:SetText(category.label)
		local description = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		description:SetPoint("TOPLEFT", checkbox.Text, "BOTTOMLEFT", 0, -2)
		description:SetText(category.description)

		checkbox.category = category.key
		checkbox:SetScript("OnClick", function(self)
			Profiles.SetCategoryEnabled(self.category, self:GetChecked())
			Refresh()
		end)
		table.insert(widgets.checkboxes, checkbox)
		previous = checkbox
	end

	widgets.categoryWarning = Label(
		"Check at least one category. Until then, changes aren't saved to this profile.",
		"GameFontHighlightSmall",
		previous,
		0,
		-6
	)
	widgets.categoryWarning:SetTextColor(RED_FONT_COLOR:GetRGB())
	return widgets.categoryWarning
end

local function BuildSharingSection(anchor)
	local line = SectionHeading("Sharing", anchor)

	widgets.export = Button("Export", 100)
	widgets.export:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, -12)
	local import = Button("Import", 100)
	import:SetPoint("LEFT", widgets.export, "RIGHT", 6, 0)
	local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	hint:SetPoint("LEFT", import, "RIGHT", 12, 0)
	hint:SetText("Copy a profile to another account, or share it with a friend.")

	-- One text box serves both directions, and it only appears once Export or Import is clicked.
	local pasteBox = CreateFrame("ScrollFrame", nil, panel, "InputScrollFrameTemplate")
	pasteBox:SetSize(CONTENT_WIDTH - 10, 80)
	pasteBox:SetPoint("TOPLEFT", widgets.export, "BOTTOMLEFT", 6, -12)
	pasteBox.EditBox:SetWidth(CONTENT_WIDTH - 30) -- room for the scroll bar
	pasteBox.EditBox:SetAutoFocus(false)
	pasteBox.CharCount:Hide()

	local addImported = Button("Add profile", 110, function()
		local profile, importReason = ExportString.Import(pasteBox.EditBox:GetText())
		if not profile then
			ShowMessage("Couldn't import: " .. importReason .. ".")
			return
		end
		AskForName("Name the imported profile:", {
			save = function(name)
				return Profiles.AddImported(name, profile)
			end,
			successText = 'Imported "%s". Choose it from the Profile menu to use it.',
			onSaved = HidePasteArea,
		})
	end)
	addImported:SetPoint("TOPLEFT", pasteBox, "BOTTOMLEFT", -6, -10)

	local pasteHint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	pasteHint:SetPoint("LEFT", addImported, "RIGHT", 12, 0)
	pasteHint:SetWidth(CONTENT_WIDTH - addImported:GetWidth() - 12)
	pasteHint:SetJustifyH("LEFT")

	widgets.pasteArea = { pasteBox, addImported, pasteHint }
	local function ShowPasteBox(text, hintText, isImport)
		pasteBox.EditBox:SetText(text)
		pasteHint:SetText(hintText)
		pasteBox:Show()
		pasteHint:Show()
		addImported:SetShown(isImport)
		pasteBox.EditBox:SetFocus()
	end

	local showingExport = false
	local function ExportHint()
		local hintText = "Control + C to copy"
		if #UnsavedChanges() > 0 then
			hintText = hintText .. "  ·  " .. RED_FONT_COLOR:WrapTextInColorCode("Save now to include your changes")
		end
		return hintText
	end

	widgets.export:SetScript("OnClick", function()
		local _, profile = Profiles.Selected()
		showingExport = true
		-- Addons can't write to the clipboard, so select the text for the player to copy.
		ShowPasteBox(ExportString.Export(profile), ExportHint())
		pasteBox.EditBox:HighlightText()
	end)
	import:SetScript("OnClick", function()
		showingExport = false
		ShowPasteBox("", "Paste a ChatProfiles export in the box, then click Add profile.", true)
	end)

	-- Called on every Refresh, so an open export follows saves and profile switches. The text is
	-- only replaced when it changes, since replacing it clears the player's selection.
	function widgets.UpdateExport()
		if not showingExport or not pasteBox:IsShown() then
			return
		end
		local _, profile = Profiles.Selected()
		if not profile then
			showingExport = false
			HidePasteArea()
			return
		end
		local text = ExportString.Export(profile)
		if text ~= pasteBox.EditBox:GetText() then
			-- Clicking Save now took focus from the box, and Ctrl+C only copies from a focused box.
			pasteBox.EditBox:SetText(text)
			pasteBox.EditBox:SetFocus()
			pasteBox.EditBox:HighlightText()
		end
		pasteHint:SetText(ExportHint())
	end
	return addImported
end

local function BuildWidgets()
	widgets = {}

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", LEFT_MARGIN, -16)
	title:SetText("ChatProfiles")
	local intro = Label(
		"Share one chat setup across your characters. Changes are saved when you log out.",
		"GameFontHighlightSmall",
		title,
		0,
		-8
	)

	local last = BuildProfileSection(intro)
	last = BuildCategorySection(last)
	last = BuildSharingSection(last)

	widgets.message = Label("", "GameFontNormal", last, 0, -14)
	widgets.message:SetWidth(CONTENT_WIDTH)
end

panel:SetScript("OnShow", function()
	if not widgets then
		BuildWidgets()
	end
	HidePasteArea()
	ShowMessage(nil)
	Refresh()
end)

-- Changing chat settings fires no events, so the status is checked again when the mouse comes
-- back to the panel, as it does after a change in the chat window. Motion only, so clicks
-- still reach whatever is underneath.
panel:SetMouseMotionEnabled(true)
panel:SetScript("OnEnter", function()
	if widgets then
		Refresh()
	end
end)

SLASH_CHATPROFILES1 = "/chatprofiles"
SLASH_CHATPROFILES2 = "/chatp"
SlashCmdList.CHATPROFILES = function()
	Settings.OpenToCategory(settingsCategory:GetID())
end
