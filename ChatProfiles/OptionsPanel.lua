-- The options panel. It's under Esc > Options > AddOns > ChatProfiles, and /chatprofiles or /chatp opens it too.

local _, ns = ...
local Profiles, ExportString, PanelText = ns.Profiles, ns.ExportString, ns.PanelText

local LEFT_MARGIN = 16
local CONTENT_WIDTH = 600

local panel = CreateFrame("Frame")
-- New frames start shown. SettingsPanelMixin:DisplayLayout reparents the panel into a canvas that
-- may already be visible, then calls Show, so a shown panel would never fire OnShow the first time.
panel:Hide()
local settingsCategory = Settings.RegisterCanvasLayoutCategory(panel, "ChatProfiles")
Settings.RegisterAddOnCategory(settingsCategory)

-- The room Settings gives the page depends on screen size and UI scale, so the page scrolls
-- when its contents don't fit.
local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "ScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT")
scrollFrame:SetPoint("BOTTOMRIGHT", -24, 0) -- room for the scroll bar
local content = CreateFrame("Frame", nil, scrollFrame)
content:SetSize(LEFT_MARGIN + CONTENT_WIDTH, 1)
scrollFrame:SetScrollChild(content)

-- The widgets are built the first time the panel opens, since most sessions never open it.
local widgets

-- Sizes the page to what's shown, so it only scrolls when that doesn't fit. The paste box is
-- the lowest part when it's open.
local function FitContent()
	local lowest = widgets.pasteMode and widgets.addImported or widgets.export
	local top, bottom = content:GetTop(), lowest:GetBottom()
	if top and bottom then
		content:SetHeight(top - bottom + 16)
	end
end

local function Refresh()
	local name, profile = Profiles.Selected()
	local categories = Profiles.Categories()

	-- The dropdown doesn't notice profile changes on its own.
	widgets.dropdown:GenerateMenu()
	for _, checkbox in ipairs(widgets.checkboxes) do
		checkbox:SetChecked(categories ~= nil and categories[checkbox.category])
		checkbox:SetEnabled(profile ~= nil)
	end
	-- With every box unchecked, saving would keep nothing, warning prompts for at least one checked box.
	local hasCategory = categories ~= nil and Profiles.HasCategoryOn(categories)
	widgets.categoryWarning:SetShown(profile ~= nil and not hasCategory)
	widgets.rename:SetEnabled(profile ~= nil)
	widgets.delete:SetEnabled(profile ~= nil)
	widgets.export:SetEnabled(profile ~= nil)
	widgets.saveNow:SetEnabled(Profiles.CanSave())

	local changes, duplicateTabNames = PanelText.UnsavedChanges()
	widgets.status:SetText(PanelText.Status(name, changes))
	widgets.details:SetText(PanelText.Details(changes or {}, duplicateTabNames or {}))
	widgets.UpdateExport(changes)
	FitContent()
end

local function ShowError(text)
	UIErrorsFrame:AddMessage(text, RED_FONT_COLOR:GetRGB())
end

-- If some settings don't apply, the status line says so and lists them.
local function SwitchProfile(name)
	local remaining, reason = Profiles.Select(name)
	if not remaining then
		ShowError(reason)
	end
	Refresh()
end

local function HidePasteArea()
	for _, part in ipairs(widgets.pasteArea) do
		part:Hide()
	end
	widgets.pasteMode = nil
	FitContent()
end

-- New, Rename and Import ask for a name in this popup, and `data.save` saves it. Returning
-- true keeps the popup open, so a rejected name can be fixed.
local function AcceptName(dialog, data)
	local name, reason = data.save(dialog:GetEditBox():GetText())
	if not name then
		ShowError(reason)
		return true
	end
	if data.onSaved then
		data.onSaved(name)
	end
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
	local label = content:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
	label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x or 0, y or -16)
	label:SetJustifyH("LEFT")
	label:SetText(text)
	return label
end

local function Button(text, width, onClick)
	local button = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
	button:SetText(text)
	button:SetSize(width, 22)
	button:SetScript("OnClick", onClick)
	return button
end

-- A gold heading with a line under it. Returns the line, so the section's contents can sit below it.
local function SectionHeading(text, anchor)
	local heading = Label(text, "GameFontNormal", anchor, 0, -20)
	local line = content:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(1, 1, 1, 0.15)
	line:SetSize(CONTENT_WIDTH, 1)
	line:SetPoint("TOPLEFT", heading, "BOTTOMLEFT", 0, -4)
	return line
end

local function BuildProfileSection(anchor)
	local line = SectionHeading("Profile", anchor)

	widgets.dropdown = CreateFrame("DropdownButton", nil, content, "WowStyle1DropdownTemplate")
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
		Refresh()
	end)
	widgets.saveNow:SetPoint("TOPLEFT", widgets.dropdown, "BOTTOMLEFT", 0, -12)

	widgets.status = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
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
	for _, category in ipairs(PanelText.CATEGORIES) do
		local checkbox = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
		if previous then
			checkbox:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -6)
		else
			checkbox:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, -8)
		end
		checkbox.Text:SetText(category.label)
		local description = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
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
	-- Also confirms an import, since nothing else on the panel changes when one is added.
	widgets.sharingHint = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	widgets.sharingHint:SetPoint("LEFT", import, "RIGHT", 12, 0)

	-- One text box serves both directions, and it only appears once Export or Import is clicked.
	local pasteBox = CreateFrame("ScrollFrame", nil, content, "InputScrollFrameTemplate")
	pasteBox:SetSize(CONTENT_WIDTH - 10, 80)
	pasteBox:SetPoint("TOPLEFT", widgets.export, "BOTTOMLEFT", 6, -12)
	pasteBox.EditBox:SetWidth(CONTENT_WIDTH - 30) -- room for the scroll bar
	pasteBox.EditBox:SetAutoFocus(false)
	pasteBox.CharCount:Hide()

	local pasteHint = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	local addImported = Button("Add profile", 110, function()
		local profile, importReason = ExportString.Import(pasteBox.EditBox:GetText())
		if not profile then
			pasteHint:SetText(RED_FONT_COLOR:WrapTextInColorCode("Couldn't import: " .. importReason .. "."))
			return
		end
		AskForName("Name the imported profile:", {
			save = function(name)
				return Profiles.AddImported(name, profile)
			end,
			onSaved = function(name)
				HidePasteArea()
				widgets.sharingHint:SetText('Imported "' .. name .. '". Choose it from the Profile menu to use it.')
			end,
		})
	end)
	addImported:SetPoint("TOPLEFT", pasteBox, "BOTTOMLEFT", -6, -10)
	widgets.addImported = addImported
	pasteHint:SetPoint("LEFT", addImported, "RIGHT", 12, 0)
	pasteHint:SetWidth(CONTENT_WIDTH - addImported:GetWidth() - 12)
	pasteHint:SetJustifyH("LEFT")

	-- `pasteMode` is "export" or "import" while the box is open, and nil once it's hidden.
	widgets.pasteArea = { pasteBox, addImported, pasteHint }
	local function ShowPasteBox(mode, text, hintText)
		widgets.pasteMode = mode
		pasteBox.EditBox:SetText(text)
		pasteHint:SetText(hintText)
		pasteBox:Show()
		pasteHint:Show()
		addImported:SetShown(mode == "import")
		pasteBox.EditBox:SetFocus()
		FitContent()
	end

	widgets.export:SetScript("OnClick", function()
		local _, profile = Profiles.Selected()
		-- Addons can't write to the clipboard, so select the text for the player to copy.
		ShowPasteBox("export", ExportString.Export(profile), PanelText.ExportHint(PanelText.UnsavedChanges()))
		pasteBox.EditBox:HighlightText()
	end)
	import:SetScript("OnClick", function()
		ShowPasteBox("import", "", "Paste a ChatProfiles export in the box, then click Add profile.")
	end)

	-- Called on every Refresh, so an open export follows saves and profile switches. The text is
	-- only replaced when it changes, since replacing it clears the player's selection.
	function widgets.UpdateExport(changes)
		if widgets.pasteMode ~= "export" then
			return
		end
		local _, profile = Profiles.Selected()
		if not profile then
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
		pasteHint:SetText(PanelText.ExportHint(changes))
	end
end

local function BuildWidgets()
	widgets = {}

	local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
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
	BuildSharingSection(last)
end

panel:SetScript("OnShow", function()
	if not widgets then
		BuildWidgets()
	end
	HidePasteArea()
	widgets.sharingHint:SetText("Copy a profile to another account, or share it with a friend.")
	Refresh()
end)

-- Changing chat settings fires no events, so the status is checked again when the mouse comes
-- back to the panel, as it does after a change in the chat window. Motion only, so clicks and
-- the scroll wheel still reach whatever is underneath.
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
