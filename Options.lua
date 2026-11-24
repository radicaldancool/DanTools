-- DanTools settings window (minimap button or /dantools): a General page with every tool's on/off
-- switch, and a page per tool with its options, click bindings and, for text displays, its look.

local _, DanTools = ...
local Options = {}
DanTools.Options = Options

local PAGE_W = 430
local DEFAULT_FONT = "Game default"
local FONT_ROWS = 12
local CLEAR, BLACK = { 0, 0, 0, 0 }, { 0, 0, 0, 1 }

local window, scroll, selected
local listButtons, pages = {}, {}
local fontPopup, menu, minimapButton

---------------------------------------------------------------------------------------------------
-- Widgets. A page is laid out top to bottom: page.y is where the next row starts.

local function text(parent, str, font, width)
	local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
	fs:SetJustifyH("LEFT")
	fs:SetJustifyV("TOP")
	if width then fs:SetWidth(width) end
	fs:SetText(str)
	if parent.group then table.insert(parent.group, fs) end
	return fs
end

local function add(page, widget, height, indent)
	widget:SetPoint("TOPLEFT", page, "TOPLEFT", indent or 0, page.y)
	page.y = page.y - height
	return widget
end

local function header(page, str)
	page.y = page.y - 8
	add(page, text(page, str, "GameFontNormal"), 20)
end

local function rowLabel(page, str)
	local fs = text(page, str)
	fs:SetPoint("TOPLEFT", page, "TOPLEFT", 4, page.y - 5)
	return fs
end

local function button(parent, label, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(label)
	b:SetScript("OnClick", onClick)
	if parent.group then table.insert(parent.group, b) end
	return b
end

local function check(page, label, get, set)
	local box = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
	box:SetSize(24, 24)
	if page.group then table.insert(page.group, box) end
	local fs = text(page, label)
	fs:SetPoint("LEFT", box, "RIGHT", 2, 0)
	box:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
	table.insert(page.refreshers, function() box:SetChecked(get() and true or false) end)
	return add(page, box, 26)
end

local function pickColor(r, g, b, a, hasAlpha, onChange)
	local r0, g0, b0, a0 = r, g, b, a
	if hasAlpha and a == 0 then a = 0.6 end -- an invisible color: start it visible, or picking one shows nothing
	local function changed()
		local nr, ng, nb = ColorPickerFrame:GetColorRGB()
		local na = a
		if hasAlpha then
			if ColorPickerFrame.GetColorAlpha then
				na = ColorPickerFrame:GetColorAlpha()
			elseif OpacitySliderFrame then
				na = 1 - OpacitySliderFrame:GetValue()
			end
		end
		onChange(nr, ng, nb, na)
	end
	local function cancelled()
		onChange(r0, g0, b0, a0)
	end
	if ColorPickerFrame.SetupColorPickerAndShow then
		ColorPickerFrame:SetupColorPickerAndShow({
			r = r, g = g, b = b, opacity = a, hasOpacity = hasAlpha,
			swatchFunc = changed, opacityFunc = changed, cancelFunc = cancelled,
		})
	else
		ColorPickerFrame.func, ColorPickerFrame.opacityFunc, ColorPickerFrame.cancelFunc = changed, changed, cancelled
		ColorPickerFrame.hasOpacity, ColorPickerFrame.opacity = hasAlpha, 1 - a
		ColorPickerFrame:SetColorRGB(r, g, b)
		ColorPickerFrame:Hide()
		ColorPickerFrame:Show()
	end
	if a ~= a0 then onChange(r, g, b, a) end
end

-- A small color square that opens the color picker. get() returns { r, g, b, a }; set gets a new one.
local function swatch(page, get, set)
	local s = CreateFrame("Button", nil, page)
	s:SetSize(20, 20)
	if page.group then table.insert(page.group, s) end
	local edge = s:CreateTexture(nil, "BACKGROUND")
	edge:SetAllPoints()
	edge:SetColorTexture(1, 1, 1)
	local fill = s:CreateTexture(nil, "ARTWORK")
	fill:SetPoint("TOPLEFT", 1, -1)
	fill:SetPoint("BOTTOMRIGHT", -1, 1)
	local function refresh()
		local c = get()
		fill:SetColorTexture(c[1], c[2], c[3])
	end
	s:SetScript("OnClick", function()
		local c = get()
		pickColor(c[1], c[2], c[3], c[4] or 1, true, function(r, g, b, a)
			set({ r, g, b, a })
			refresh()
		end)
	end)
	table.insert(page.refreshers, refresh)
	return s
end

-- "Size   [-] 12 [+]"
local function stepper(page, label, get, set, min, max, step)
	rowLabel(page, label)
	local value = text(page, "")
	local function change(by)
		set(math.max(min, math.min(max, get() + by)))
		value:SetText(get())
	end
	local less = button(page, "-", 24, function() change(-step) end)
	less:SetPoint("TOPLEFT", page, "TOPLEFT", 110, page.y)
	value:SetWidth(30)
	value:SetJustifyH("CENTER")
	value:SetPoint("LEFT", less, "RIGHT", 4, 0)
	local more = button(page, "+", 24, function() change(step) end)
	more:SetPoint("LEFT", less, "RIGHT", 38, 0)
	table.insert(page.refreshers, function() value:SetText(get()) end)
	page.y = page.y - 26
end

-- "Keep item   [ Alt + Right-click ]  [Default]": click the middle button, then click it again with
-- the new modifier keys and mouse button.
local function bindingRow(page, tool, b)
	rowLabel(page, b.label):SetWidth(172)
	local capture = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	capture:SetSize(160, 22)
	capture:SetPoint("TOPLEFT", page, "TOPLEFT", 180, page.y)
	capture:RegisterForClicks("AnyUp")
	local function refresh()
		capture.waiting = false
		capture:SetText(DanTools.ComboText(DanTools:Binding(tool, b.key)))
	end
	capture:SetScript("OnClick", function(self, mouseButton)
		if self.waiting then
			tool.db.bindings[b.key] = DanTools.ClickCombo(mouseButton)
			refresh()
		else
			self.waiting = true
			self:SetText("Click...")
		end
	end)
	local default = button(page, "Default", 70, function()
		tool.db.bindings[b.key] = nil
		refresh()
	end)
	default:SetPoint("LEFT", capture, "RIGHT", 6, 0)
	table.insert(page.refreshers, refresh)
	page.y = page.y - 26
end

-- A list of choices under a button. onHover, if given, hears of each one the mouse passes over.
local function showMenu(anchor, choices, current, onPick, onHover)
	if not menu then
		menu = CreateFrame("Frame", nil, window, BackdropTemplateMixin and "BackdropTemplate" or nil)
		menu:SetFrameStrata("TOOLTIP")
		menu:EnableMouse(true)
		DanTools.Skin(menu)
		menu.rows = {}
	end
	if menu:IsShown() and menu.anchor == anchor then
		menu:Hide()
		return
	end
	menu.anchor, menu.onPick, menu.onHover = anchor, onPick, onHover
	for i, choice in ipairs(choices) do
		local row = menu.rows[i]
		if not row then
			row = CreateFrame("Button", nil, menu)
			row:SetHeight(18)
			row:SetPoint("TOPLEFT", 6, -5 - (i - 1) * 18)
			row:SetPoint("TOPRIGHT", -6, -5 - (i - 1) * 18)
			row:SetHighlightTexture([[Interface\QuestFrame\UI-QuestTitleHighlight]], "ADD")
			row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			row.text:SetPoint("LEFT", 2, 0)
			row:SetScript("OnClick", function(self)
				menu:Hide()
				menu.onPick(self.choice)
			end)
			row:SetScript("OnEnter", function(self)
				if menu.onHover then menu.onHover(self.choice) end
			end)
			menu.rows[i] = row
		end
		row.choice = choice
		row.text:SetText(choice)
		if choice == current then
			row.text:SetTextColor(1, 0.82, 0)
		else
			row.text:SetTextColor(1, 1, 1)
		end
		row:Show()
	end
	for i = #choices + 1, #menu.rows do menu.rows[i]:Hide() end
	menu:SetSize(anchor:GetWidth(), #choices * 18 + 10)
	menu:ClearAllPoints()
	menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	menu:Show()
end

local function showFontPopup(anchor, onPick)
	if not fontPopup then
		fontPopup = CreateFrame("Frame", nil, window, BackdropTemplateMixin and "BackdropTemplate" or nil)
		fontPopup:SetFrameStrata("TOOLTIP")
		fontPopup:SetSize(220, FONT_ROWS * 18 + 10)
		fontPopup:EnableMouse(true)
		fontPopup:EnableMouseWheel(true)
		DanTools.Skin(fontPopup)
		fontPopup.rows = {}
		for i = 1, FONT_ROWS do
			local row = CreateFrame("Button", nil, fontPopup)
			row:SetSize(208, 18)
			row:SetPoint("TOPLEFT", 6, -5 - (i - 1) * 18)
			row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
			row.text = row:CreateFontString(nil, "OVERLAY")
			row.text:SetFont(STANDARD_TEXT_FONT, 12, "")
			row.text:SetPoint("LEFT", 2, 0)
			row:SetScript("OnClick", function(self)
				fontPopup:Hide()
				fontPopup.onPick(self.font)
			end)
			fontPopup.rows[i] = row
		end
		function fontPopup:Fill()
			for i, row in ipairs(self.rows) do
				local name = self.names[i + self.offset]
				row:SetShown(name ~= nil)
				if name then
					row.font = name ~= DEFAULT_FONT and name or nil
					row.text:SetFont(DanTools:FontPath(row.font), 12, "")
					row.text:SetText(name)
				end
			end
		end
		fontPopup:SetScript("OnMouseWheel", function(self, delta)
			self.offset = math.max(0, math.min(#self.names - FONT_ROWS, self.offset - delta * 3))
			self:Fill()
		end)
	end
	if fontPopup:IsShown() and fontPopup.anchor == anchor then
		fontPopup:Hide()
		return
	end
	fontPopup.anchor, fontPopup.onPick, fontPopup.offset = anchor, onPick, 0
	fontPopup.names = DanTools:FontNames()
	table.insert(fontPopup.names, 1, DEFAULT_FONT)
	fontPopup:ClearAllPoints()
	fontPopup:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
	fontPopup:Fill()
	fontPopup:Show()
end

-- Font, text size, background and border for one text display.
local function appearance(page, tool)
	local look = tool.db.look
	local function apply()
		DanTools:ApplyLook(tool)
		page:Refresh()
	end
	header(page, "Appearance")

	rowLabel(page, "Font")
	local fontButton = button(page, "", 200, function(self)
		showFontPopup(self, function(name)
			look.font = name
			apply()
		end)
	end)
	fontButton:SetPoint("TOPLEFT", page, "TOPLEFT", 110, page.y)
	table.insert(page.refreshers, function() fontButton:SetText(look.font or DEFAULT_FONT) end)
	page.y = page.y - 26

	stepper(page, "Size", function() return look.size or 12 end, function(size)
		look.size = size
		apply()
	end, 8, 32, 1)

	rowLabel(page, "Background")
	local bg = swatch(page, function() return look.bg or CLEAR end, function(c)
		look.bg = c
		apply()
	end)
	bg:SetPoint("TOPLEFT", page, "TOPLEFT", 110, page.y - 1)
	local noBg = button(page, "None", 60, function()
		look.bg = nil
		apply()
	end)
	noBg:SetPoint("LEFT", bg, "RIGHT", 8, 0)
	page.y = page.y - 26

	local borderY = page.y
	check(page, "Border", function() return look.border end, function(on)
		look.border = on or nil
		apply()
	end)
	local borderColor = swatch(page, function() return look.borderColor or BLACK end, function(c)
		look.borderColor = c
		apply()
	end)
	borderColor:SetPoint("TOPLEFT", page, "TOPLEFT", 110, borderY - 2)

	page.y = page.y - 6
	local all = button(page, "Apply to all", 110, function()
		for _, other in ipairs(DanTools.tools) do
			if other.display and other ~= tool then
				wipe(other.db.look)
				for k, v in pairs(look) do
					other.db.look[k] = type(v) == "table" and CopyTable(v) or v
				end
				DanTools:ApplyLook(other)
			end
		end
	end)
	all:SetPoint("TOPLEFT", page, "TOPLEFT", 0, page.y)
	local resetLook = button(page, "Reset look", 100, function()
		wipe(look)
		apply()
	end)
	resetLook:SetPoint("LEFT", all, "RIGHT", 6, 0)
	page.y = page.y - 26
end

---------------------------------------------------------------------------------------------------
-- Pages

local function newPage()
	local page = CreateFrame("Frame", nil, scroll)
	page:SetSize(PAGE_W, 10)
	page:Hide()
	page.y = 0
	page.refreshers = {}
	function page:Refresh()
		for _, refresh in ipairs(self.refreshers) do refresh() end
	end
	return page
end

local function toggleTool(tool, on)
	DanTools:SetEnabled(tool, on)
	Options.RefreshList()
end

local function buildGeneralPage()
	local page = newPage()
	add(page, text(page, "General", "GameFontNormalLarge"), 28)
	check(page, "Minimap button",
		function() return not DanTools.account.minimap.hide end,
		function(on)
			DanTools.account.minimap.hide = not on or nil
			Options.UpdateMinimapButton()
		end)
	check(page, "Lock displays", function() return DanTools.account.locked end, function(on) DanTools:SetLocked(on) end)
	header(page, "Tools")
	for _, tool in ipairs(DanTools.tools) do
		check(page, tool.name, function() return tool.db.enabled end, function(on) toggleTool(tool, on) end)
	end
	page:SetHeight(-page.y + 10)
	return page
end

-- One setting's row. With o.needs, it greys out while that other setting is off.
local function optionRow(page, tool, o)
	local function get() return tool.db[o.key] end
	local function set(value)
		tool.db[o.key] = value
		if tool.OnOption then tool:OnOption(o.key, value) end
		page:Refresh()
	end
	page.group = {}
	if o.type == "number" then
		stepper(page, o.label, get, set, o.min, o.max, o.step)
	elseif o.type == "color" then
		rowLabel(page, o.label)
		swatch(page, get, set):SetPoint("TOPLEFT", page, "TOPLEFT", 110, page.y - 1)
		page.y = page.y - 26
	elseif o.type == "choice" then -- a button showing the current choice; a click lists the rest
		rowLabel(page, o.label)
		local pick = button(page, "", 110, function(self)
			showMenu(self, o.choices, get(), set, tool.OnPreview and function(choice)
				tool:OnPreview(o.key, choice)
			end)
		end)
		pick:SetPoint("TOPLEFT", page, "TOPLEFT", 110, page.y)
		local arrow = pick:CreateTexture(nil, "OVERLAY")
		arrow:SetSize(12, 12)
		arrow:SetPoint("RIGHT", -4, 0)
		arrow:SetTexture([[Interface\ChatFrame\ChatFrameExpandArrow]])
		arrow:SetRotation(-math.pi / 2)
		table.insert(page.refreshers, function() pick:SetText(get()) end)
		page.y = page.y - 26
	else
		check(page, o.label, get, set)
	end
	local group = page.group
	page.group = nil
	if not o.needs then return end
	table.insert(page.refreshers, function()
		local need = tool.db[o.needs]
		local on = need and need ~= "Off" and true or false
		for _, widget in ipairs(group) do
			widget:SetAlpha(on and 1 or 0.35)
			if widget.SetEnabled then widget:SetEnabled(on) end
		end
	end)
end

local function buildToolPage(tool)
	local page = newPage()
	add(page, text(page, tool.name, "GameFontNormalLarge"), 28)
	check(page, "Enabled", function() return tool.db.enabled end, function(on) toggleTool(tool, on) end)
	if tool.display and tool.display.hideIdle ~= nil then
		check(page, "Hide when inactive", function() return tool.db.hideIdle end, function(on)
			tool.db.hideIdle = on
			DanTools:UpdateVisibility(tool)
		end)
	end
	for _, o in ipairs(tool.options or {}) do
		if o.type == "header" then
			header(page, o.label)
		else
			optionRow(page, tool, o)
		end
	end
	if tool.BuildPreview then -- the tool's own picture of what its settings do
		local frame, height, refresh = tool:BuildPreview(page)
		page.y = page.y - 6
		add(page, frame, height)
		table.insert(page.refreshers, refresh)
	end

	if tool.bindings then
		header(page, "Clicks")
		for _, b in ipairs(tool.bindings) do bindingRow(page, tool, b) end
	end

	local buttons = {}
	if tool.frame then
		buttons[1] = { text = "Reset position", onClick = function()
			tool.db.pos = nil
			DanTools:Place(tool)
		end }
	end
	for _, b in ipairs(tool.buttons or {}) do buttons[#buttons + 1] = b end
	if #buttons > 0 then
		page.y = page.y - 6
		for i, b in ipairs(buttons) do
			local widget = button(page, b.text, 138, b.onClick)
			widget:SetPoint("TOPLEFT", page, "TOPLEFT", ((i - 1) % 3) * 144, page.y)
			if i % 3 == 0 or i == #buttons then page.y = page.y - 26 end
		end
	end

	if tool.display then appearance(page, tool) end
	page:SetHeight(-page.y + 10)
	return page
end

---------------------------------------------------------------------------------------------------
-- Window

function Options.RefreshList()
	if not window then return end
	for key, b in pairs(listButtons) do
		local tool = DanTools.byKey[key]
		b.selected:SetShown(key == selected)
		if tool and not tool.db.enabled then
			b.text:SetTextColor(0.5, 0.5, 0.5)
		else
			b.text:SetTextColor(1, 1, 1)
		end
	end
end

function Options.Select(key)
	if fontPopup then fontPopup:Hide() end
	if menu then menu:Hide() end
	if selected and pages[selected] then pages[selected]:Hide() end
	selected = key
	local page = pages[key]
	if not page then
		page = key == "general" and buildGeneralPage() or buildToolPage(DanTools.byKey[key])
		pages[key] = page
	end
	scroll:SetScrollChild(page)
	page:Show()
	page:Refresh()
	scroll:SetVerticalScroll(0)
	Options.RefreshList()
end

local function listButton(key, name, index)
	local b = CreateFrame("Button", nil, window)
	b:SetSize(144, 22)
	b:SetPoint("TOPLEFT", 10, -38 - (index - 1) * 23)
	b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
	b.selected = b:CreateTexture(nil, "BACKGROUND")
	b.selected:SetAllPoints()
	b.selected:SetColorTexture(1, 0.82, 0, 0.18)
	b.selected:Hide()
	b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	b.text:SetPoint("LEFT", 6, 0)
	b.text:SetText(name)
	b:SetScript("OnClick", function() Options.Select(key) end)
	listButtons[key] = b
end

local function build()
	window = CreateFrame("Frame", "DanToolsOptions", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	window:Hide()
	window:SetSize(650, 500)
	window:SetPoint("CENTER")
	window:SetFrameStrata("HIGH")
	window:SetToplevel(true)
	window:SetClampedToScreen(true)
	window:EnableMouse(true)
	window:SetMovable(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", window.StopMovingOrSizing)
	DanTools.Skin(window)
	table.insert(UISpecialFrames, "DanToolsOptions") -- Escape closes it

	local title = window:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 14, -12)
	title:SetText("DanTools")
	local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	listButton("general", "General", 1)
	for i, tool in ipairs(DanTools.tools) do listButton(tool.key, tool.name, i + 1) end
	local divider = window:CreateTexture(nil, "ARTWORK")
	divider:SetColorTexture(1, 1, 1, 0.12)
	divider:SetWidth(1)
	divider:SetPoint("TOPLEFT", 160, -38)
	divider:SetPoint("BOTTOMLEFT", 160, 12)

	scroll = DanTools.ScrollFrame(window, "DanToolsOptionsScroll")
	scroll:SetPoint("TOPLEFT", 172, -38)
	scroll:SetPoint("BOTTOMRIGHT", -32, 12)

	window:SetScript("OnShow", function()
		DanTools:SetSettingsOpen(true)
		Options.Select(selected or "general")
	end)
	window:SetScript("OnHide", function()
		DanTools:SetSettingsOpen(false)
		if fontPopup then fontPopup:Hide() end
		if menu then menu:Hide() end
	end)
end

function Options.Toggle(show)
	if not window then build() end
	if show == true then
		window:Show()
	else
		window:SetShown(not window:IsShown())
	end
end

---------------------------------------------------------------------------------------------------
-- Minimap button: click opens or closes the settings window, drag moves it around the minimap.

local function placeMinimapButton()
	local angle = DanTools.account.minimap.angle or 3.6
	local radius = Minimap:GetWidth() / 2 + 6
	minimapButton:ClearAllPoints()
	minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function Options.UpdateMinimapButton()
	minimapButton:SetShown(not DanTools.account.minimap.hide)
end

local function buildMinimapButton()
	local b = CreateFrame("Button", "DanToolsMinimapButton", Minimap)
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("LeftButtonUp")
	b:RegisterForDrag("LeftButton")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local back = b:CreateTexture(nil, "BACKGROUND")
	back:SetSize(20, 20)
	back:SetPoint("TOPLEFT", 7, -5)
	back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetSize(17, 17)
	icon:SetPoint("TOPLEFT", 7, -6)
	icon:SetTexture("Interface\\Icons\\INV_Misc_Wrench_01")
	icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	local ring = b:CreateTexture(nil, "OVERLAY")
	ring:SetSize(53, 53)
	ring:SetPoint("TOPLEFT")
	ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

	b:SetScript("OnClick", function() Options.Toggle() end)
	b:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local cx, cy = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			DanTools.account.minimap.angle = math.atan2(cy / scale - my, cx / scale - mx)
			placeMinimapButton()
		end)
	end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("DanTools")
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function() GameTooltip:Hide() end)
	minimapButton = b
	placeMinimapButton()
	Options.UpdateMinimapButton()
end

-- Esc > Options > AddOns > DanTools: just a button that opens the real window.
local function registerBlizzardPanel()
	local panel = CreateFrame("Frame")
	panel.name = "DanTools"
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("DanTools")
	local open = button(panel, "Open", 100, function()
		if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
		Options.Toggle(true)
	end)
	open:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
	if Settings and Settings.RegisterCanvasLayoutCategory then
		Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(panel, "DanTools"))
	elseif InterfaceOptions_AddCategory then
		InterfaceOptions_AddCategory(panel)
	end
end

function Options.Init()
	buildMinimapButton()
	registerBlizzardPanel()
end

SLASH_DANTOOLS1 = "/dantools"
SlashCmdList.DANTOOLS = function(msg)
	local word = msg and msg:lower():match("^%s*(%a+)")
	if word == "mana" then -- what the mana watcher last saw
		DanTools:PrintManaLog()
	elseif word == "mouseover" then
		DanTools:PrintMouseover()
	else
		Options.Toggle()
	end
end
