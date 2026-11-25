-- The options panel, under Esc > Options > AddOns > ChatCopy, also opened with /chatcopy.

local _, ns = ...
local Profiles, Codec = ns.Profiles, ns.Codec

local LEFT = 16
local WIDTH = 600
local MAX_DETAIL_LINES = 8
local CATEGORIES = {
	{ key = "tabs", label = "Tabs" },
	{ key = "contents", label = "Messages and channels" },
	{ key = "look", label = "Font and background" },
	{ key = "colors", label = "Chat colors" },
}

local panel = CreateFrame("Frame")
local category = Settings.RegisterCanvasLayoutCategory(panel, "ChatCopy")
Settings.RegisterAddOnCategory(category)

-- Widgets, built the first time the panel opens. Most sessions never open it.
local ui

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

local function Refresh()
	local name, profile = Profiles.Selected()
	local failed = Profiles.HasFailed()

	-- The dropdown doesn't notice profile changes on its own.
	ui.dropdown:GenerateMenu()
	for _, checkbox in ipairs(ui.checkboxes) do
		checkbox:SetChecked(profile ~= nil and profile.include[checkbox.category])
		checkbox:SetEnabled(profile ~= nil)
	end
	ui.rename:SetEnabled(profile ~= nil)
	ui.delete:SetEnabled(profile ~= nil)
	ui.export:SetEnabled(profile ~= nil)
	ui.saveNow:SetEnabled(profile ~= nil and not failed)

	-- Both nil when there's no profile.
	local changes, duplicates = Profiles.Status()
	local status
	if not name then
		status = "This character isn't using a profile."
	elseif failed then
		status = "Some settings couldn't be applied, so changes won't be saved until you reload or log in again."
	elseif #changes == 0 then
		status = "Your chat settings match the profile."
	elseif #changes == 1 then
		status = "1 unsaved change. It will be saved when you log out."
	else
		status = #changes .. " unsaved changes. They'll be saved when you log out."
	end
	ui.status:SetText(status)

	local lines = {}
	for i = 1, math.min(#(changes or {}), MAX_DETAIL_LINES) do
		table.insert(lines, changes[i].text)
	end
	if changes and #changes > MAX_DETAIL_LINES then
		table.insert(lines, "...and " .. (#changes - MAX_DETAIL_LINES) .. " more")
	end
	if duplicates and #duplicates > 0 then
		table.insert(lines, "Only the first tab with each of these names is used: " .. table.concat(duplicates, ", "))
	end
	ui.details:SetText(table.concat(lines, "\n"))
end

local function ShowMessage(text)
	ui.message:SetText(text or "")
end

local function SelectProfile(name)
	local remaining = Profiles.Select(name)
	ShowMessage(#remaining > 0 and "Some settings couldn't be applied. They're listed above." or nil)
	Refresh()
end

-- Shows the result of a Profiles call that returns a name, or nil and a reason.
local function Report(successText, name, reason)
	ShowMessage(name and successText:format(name) or reason)
	Refresh()
end

local function Build()
	ui = {}

	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", LEFT, -16)
	title:SetText("ChatCopy")

	local profileLabel = Label("Profile:", nil, title, 0, -24)
	ui.dropdown = CreateFrame("DropdownButton", nil, panel, "WowStyle1DropdownTemplate")
	ui.dropdown:SetPoint("LEFT", profileLabel, "RIGHT", 12, 0)
	ui.dropdown:SetWidth(220)
	ui.dropdown:SetupMenu(function(_, root)
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

	local managesLabel = Label("Includes:", nil, hint, 0, -18)
	ui.checkboxes = {}
	local previous
	for _, info in ipairs(CATEGORIES) do
		local checkbox = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
		if previous then
			checkbox:SetPoint("LEFT", previous.Text, "RIGHT", 12, 0)
		else
			checkbox:SetPoint("LEFT", managesLabel, "RIGHT", 8, 0)
		end
		checkbox.Text:SetText(info.label)
		checkbox.category = info.key
		checkbox:SetScript("OnClick", function(self)
			Profiles.SetInclude(self.category, self:GetChecked())
			Refresh()
		end)
		table.insert(ui.checkboxes, checkbox)
		previous = checkbox
	end

	-- One name box serves Save as new, Rename and Import.
	local nameLabel = Label("Name:", nil, managesLabel, 0, -26)
	ui.name = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
	ui.name:SetPoint("LEFT", nameLabel, "RIGHT", 14, 0)
	ui.name:SetSize(180, 20)
	-- Otherwise the box grabs the keyboard as soon as the panel opens.
	ui.name:SetAutoFocus(false)
	ui.name:SetMaxLetters(Profiles.MAX_NAME_LENGTH)

	local saveAsNew = Button("Save as new profile", 150, function()
		local name, reason = Profiles.SaveAsNew(ui.name:GetText())
		Report('Saved your chat settings as "%s". This character now uses it.', name, reason)
	end)
	saveAsNew:SetPoint("LEFT", ui.name, "RIGHT", 10, 0)

	ui.rename = Button("Rename", 80, function()
		local oldName = Profiles.Selected()
		local name, reason = Profiles.Rename(oldName, ui.name:GetText())
		Report('Renamed to "%s".', name, reason)
	end)
	ui.rename:SetPoint("LEFT", saveAsNew, "RIGHT", 6, 0)

	-- Deleting takes a second click within a few seconds, since there is no undo.
	local confirmTimer
	ui.delete = Button("Delete", 80, function(self)
		if not confirmTimer then
			self:SetText("Confirm")
			confirmTimer = C_Timer.NewTimer(3, function()
				confirmTimer = nil
				self:SetText("Delete")
			end)
			return
		end
		confirmTimer:Cancel()
		confirmTimer = nil
		self:SetText("Delete")
		local name = Profiles.Selected()
		Profiles.Delete(name)
		ShowMessage('Deleted "' .. name .. '". Your chat settings stay as they are.')
		Refresh()
	end)
	ui.delete:SetPoint("LEFT", ui.rename, "RIGHT", 6, 0)

	ui.status = Label("", nil, nameLabel, 0, -24)
	ui.status:SetWidth(WIDTH)
	ui.details = Label("", "GameFontDisableSmall", ui.status, 12, -6)
	ui.details:SetWidth(WIDTH - 12)

	ui.saveNow = Button("Save Now", 100, function()
		Profiles.SaveSelected()
		local name = Profiles.Selected()
		ShowMessage('Saved your chat settings to "' .. name .. '".')
		Refresh()
	end)
	ui.saveNow:SetPoint("TOPLEFT", ui.details, "BOTTOMLEFT", -12, -16)

	local pasteBox = CreateFrame("ScrollFrame", nil, panel, "InputScrollFrameTemplate")
	pasteBox:SetSize(WIDTH - 10, 80)
	pasteBox:SetPoint("TOPLEFT", ui.saveNow, "BOTTOMLEFT", 6, -12)
	pasteBox.EditBox:SetWidth(WIDTH - 30) -- room for the scroll bar
	pasteBox.EditBox:SetAutoFocus(false)
	pasteBox.CharCount:Hide()

	ui.export = Button("Export", 100, function()
		local _, profile = Profiles.Selected()
		-- Addons can't write to the clipboard, so select the text for the player to copy.
		pasteBox.EditBox:SetText(Codec.Export(profile))
		pasteBox.EditBox:HighlightText()
		pasteBox.EditBox:SetFocus()
		ShowMessage("Press Ctrl+C to copy it.")
	end)
	ui.export:SetPoint("LEFT", ui.saveNow, "RIGHT", 6, 0)

	local import = Button("Import", 100, function()
		local profile, importError = Codec.Import(pasteBox.EditBox:GetText())
		if not profile then
			ShowMessage("Couldn't import: " .. importError .. ".")
			return
		end
		local name, reason = Profiles.Add(ui.name:GetText(), profile)
		Report('Imported "%s". Choose it from the Profile menu to use it.', name, reason)
	end)
	import:SetPoint("LEFT", ui.export, "RIGHT", 6, 0)

	local importHint = Label(
		"To import a profile, paste it in the box, give it a name above, and click Import.",
		"GameFontHighlightSmall",
		pasteBox,
		-6,
		-10
	)

	ui.message = Label("", "GameFontNormal", importHint, 0, -14)
	ui.message:SetWidth(WIDTH)
end

panel:SetScript("OnShow", function()
	if not ui then
		Build()
	end
	ShowMessage(nil)
	Refresh()
end)

SLASH_CHATCOPY1 = "/chatcopy"
SlashCmdList.CHATCOPY = function()
	Settings.OpenToCategory(category:GetID())
end
