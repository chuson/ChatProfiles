-- The options panel. It's under Esc > Options > AddOns > Chat Profiles, and /chatprofiles opens it too.

local _, ns = ...
local Profiles, ExportString = ns.Profiles, ns.ExportString

local LEFT_MARGIN = 16
local CONTENT_WIDTH = 600
local MAX_DETAIL_LINES = 8
local CATEGORIES = {
	{ key = "tabs", label = "Tabs" },
	{ key = "messagesAndChannels", label = "Messages and channels" },
	{ key = "fontAndBackground", label = "Font and background" },
	{ key = "colors", label = "Chat colors" },
}

local panel = CreateFrame("Frame")
local settingsCategory = Settings.RegisterCanvasLayoutCategory(panel, "Chat Profiles")
Settings.RegisterAddOnCategory(settingsCategory)

-- The widgets are built the first time the panel opens, since most sessions never open it.
local widgets

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

-- Delete takes a second click within a few seconds, since there is no undo. Every refresh
-- cancels a pending confirm, so it can't carry over to a different profile.
local deleteConfirmTimer

local function CancelDeleteConfirm()
	if deleteConfirmTimer then
		deleteConfirmTimer:Cancel()
		deleteConfirmTimer = nil
	end
	widgets.delete:SetText("Delete")
end

local function Refresh()
	local name, profile = Profiles.Selected()
	local applyFailed = Profiles.LastApplyFailed()

	CancelDeleteConfirm()
	-- The dropdown doesn't notice profile changes on its own.
	widgets.dropdown:GenerateMenu()
	for _, checkbox in ipairs(widgets.checkboxes) do
		checkbox:SetChecked(profile ~= nil and profile.categories[checkbox.category])
		checkbox:SetEnabled(profile ~= nil)
	end
	widgets.rename:SetEnabled(profile ~= nil)
	widgets.delete:SetEnabled(profile ~= nil)
	widgets.export:SetEnabled(profile ~= nil)
	widgets.saveNow:SetEnabled(profile ~= nil and not applyFailed)

	-- Both are nil when this character has no profile.
	local differences, duplicateTabNames = Profiles.Differences()
	widgets.status:SetText(StatusText(name, applyFailed, differences))
	widgets.details:SetText(DetailText(differences or {}, duplicateTabNames or {}))
end

local function ShowMessage(text)
	widgets.message:SetText(text or "")
end

local function SelectProfile(name)
	local remaining = Profiles.Select(name)
	ShowMessage(#remaining > 0 and "Some settings couldn't be applied. They're listed above." or nil)
	Refresh()
end

-- Shows the result of a Profiles call that returns a name, or nil and a reason.
local function ShowResult(successText, name, reason)
	ShowMessage(name and successText:format(name) or reason)
	Refresh()
end

local function BuildWidgets()
	widgets = {}

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", LEFT_MARGIN, -16)
	title:SetText("Chat Profiles")

	local profileLabel = Label("Profile:", nil, title, 0, -24)
	widgets.dropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
	widgets.dropdown:SetPoint("LEFT", profileLabel, "RIGHT", 12, 0)
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

	local hint = Label(
		"Any changes you make to your chat settings are saved to this profile when you log out.",
		"GameFontHighlightSmall",
		profileLabel,
		0,
		-14
	)

	local categoriesLabel = Label("Includes:", nil, hint, 0, -18)
	widgets.checkboxes = {}
	local previous
	for _, category in ipairs(CATEGORIES) do
		local checkbox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
		if previous then
			checkbox:SetPoint("LEFT", previous.Text, "RIGHT", 12, 0)
		else
			checkbox:SetPoint("LEFT", categoriesLabel, "RIGHT", 8, 0)
		end
		checkbox.Text:SetText(category.label)
		checkbox.category = category.key
		checkbox:SetScript("OnClick", function(self)
			Profiles.SetCategoryEnabled(self.category, self:GetChecked())
			Refresh()
		end)
		table.insert(widgets.checkboxes, checkbox)
		previous = checkbox
	end

	-- One name box serves Save as new profile, Rename and Import.
	local nameLabel = Label("Name:", nil, categoriesLabel, 0, -26)
	widgets.nameBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
	widgets.nameBox:SetPoint("LEFT", nameLabel, "RIGHT", 14, 0)
	widgets.nameBox:SetSize(180, 20)
	-- Without this, the box grabs the keyboard as soon as the panel opens.
	widgets.nameBox:SetAutoFocus(false)
	widgets.nameBox:SetMaxLetters(Profiles.MAX_PROFILE_NAME_LENGTH)

	local saveAsNew = Button("Save as new profile", 150, function()
		local name, reason = Profiles.SaveAsNew(widgets.nameBox:GetText())
		ShowResult('Saved your chat settings as "%s". This character now uses it.', name, reason)
	end)
	saveAsNew:SetPoint("LEFT", widgets.nameBox, "RIGHT", 10, 0)

	widgets.rename = Button("Rename", 80, function()
		local oldName = Profiles.Selected()
		local name, reason = Profiles.Rename(oldName, widgets.nameBox:GetText())
		ShowResult('Renamed to "%s".', name, reason)
	end)
	widgets.rename:SetPoint("LEFT", saveAsNew, "RIGHT", 6, 0)

	widgets.delete = Button("Delete", 80, function(self)
		if not deleteConfirmTimer then
			self:SetText("Confirm")
			deleteConfirmTimer = C_Timer.NewTimer(3, CancelDeleteConfirm)
			return
		end
		local name = Profiles.Selected()
		Profiles.Delete(name)
		ShowMessage('Deleted "' .. name .. '". Your chat settings stay as they are.')
		Refresh()
	end)
	widgets.delete:SetPoint("LEFT", widgets.rename, "RIGHT", 6, 0)

	widgets.status = Label("", nil, nameLabel, 0, -24)
	widgets.status:SetWidth(CONTENT_WIDTH)
	widgets.details = Label("", "GameFontDisableSmall", widgets.status, 12, -6)
	widgets.details:SetWidth(CONTENT_WIDTH - 12)

	widgets.saveNow = Button("Save now", 100, function()
		Profiles.SaveSelected()
		local name = Profiles.Selected()
		ShowMessage('Saved your chat settings to "' .. name .. '".')
		Refresh()
	end)
	widgets.saveNow:SetPoint("TOPLEFT", widgets.details, "BOTTOMLEFT", -12, -16)

	local pasteBox = CreateFrame("ScrollFrame", nil, panel, "InputScrollFrameTemplate")
	pasteBox:SetSize(CONTENT_WIDTH - 10, 80)
	pasteBox:SetPoint("TOPLEFT", widgets.saveNow, "BOTTOMLEFT", 6, -12)
	pasteBox.EditBox:SetWidth(CONTENT_WIDTH - 30) -- room for the scroll bar
	pasteBox.EditBox:SetAutoFocus(false)
	pasteBox.CharCount:Hide()

	widgets.export = Button("Export", 100, function()
		local _, profile = Profiles.Selected()
		-- Addons can't write to the clipboard, so select the text for the player to copy.
		pasteBox.EditBox:SetText(ExportString.Export(profile))
		pasteBox.EditBox:HighlightText()
		pasteBox.EditBox:SetFocus()
		ShowMessage("Press Ctrl+C to copy it.")
	end)
	widgets.export:SetPoint("LEFT", widgets.saveNow, "RIGHT", 6, 0)

	local import = Button("Import", 100, function()
		local profile, importReason = ExportString.Import(pasteBox.EditBox:GetText())
		if not profile then
			ShowMessage("Couldn't import: " .. importReason .. ".")
			return
		end
		local name, reason = Profiles.AddImported(widgets.nameBox:GetText(), profile)
		ShowResult('Imported "%s". Choose it from the Profile menu to use it.', name, reason)
	end)
	import:SetPoint("LEFT", widgets.export, "RIGHT", 6, 0)

	local importHint = Label(
		"To import a profile, paste it in the box, give it a name above, and click Import.",
		"GameFontHighlightSmall",
		pasteBox,
		-6,
		-10
	)

	widgets.message = Label("", "GameFontNormal", importHint, 0, -14)
	widgets.message:SetWidth(CONTENT_WIDTH)
end

panel:SetScript("OnShow", function()
	if not widgets then
		BuildWidgets()
	end
	ShowMessage(nil)
	Refresh()
end)

SLASH_CHATPROFILES1 = "/chatprofiles"
SlashCmdList.CHATPROFILES = function()
	Settings.OpenToCategory(settingsCategory:GetID())
end
