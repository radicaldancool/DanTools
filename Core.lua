-- DanTools: small tools in one addon, switched on or off in the settings window (minimap button or
-- /dantools). Each tool file registers itself with DanTools:AddTool. Per-character settings live in
-- DanToolsDB[tool.key] (tool.db); account-wide data (Grudge list, kept bag items, minimap button) in
-- DanToolsAccountDB (DanTools.account).
--
-- On-screen text stays terse: a word or two per label, nothing that explains how a tool works.
--
-- Tool fields: key, name, and optionally
--   display  = { width, lines, pos = { point, relPoint, x, y }, hideIdle }  a draggable text display:
--              the tool gets tool.frame (a Button) and tool.lines, and writes with DanTools:SetLines.
--              hideIdle (true/false) is the default for hiding the display while DanTools:SetIdle is on.
--   options  = { { key, label, default } }   settings stored in tool.db[key]: a checkbox, or with
--              type = "number" (plus min, max, step) a stepper, type = "color" a { r, g, b, a } swatch,
--              or type = "choice" (plus choices = { ... }) a button that steps through them
--   bindings = { { key, label, default } }   modifier+click combos like "ALT-RightButton", user-changeable
--   buttons  = { { text, onClick } }         extra buttons on the tool's settings page
--   OnLoad, OnEnable, OnDisable, OnOption(key, value), and for displays OnClick(mouseButton), OnTooltip(tooltip)
-- A display can also have bars (DanTools:NewBar, DanTools:ShowBar); tool.stack then lists its lines and
-- bars in the order they stack, top to bottom.

local _, DanTools = ...
DanTools.tools = {} -- in the order they were added, which is also their order in the settings window
DanTools.byKey = {}

local PAD = 4 -- space between a display's text and the edge of its background
DanTools.PAD = PAD

-- Plays Sounds\<name>.ogg from this addon's folder, if the file is there, and returns whether it did.
-- The game only finds a newly added file after a full restart.
function DanTools.PlayOwnSound(name)
	local file = [[Interface\AddOns\DanTools\Sounds\]] .. name .. ".ogg"
	local ok, played = pcall(PlaySoundFile, file, "Master")
	return (ok and played) and true or false
end
local CLEAR, BLACK = { 0, 0, 0, 0 }, { 0, 0, 0, 1 }

function DanTools.plain(v)
	if issecretvalue and issecretvalue(v) then return nil end
	return v
end
local plain = DanTools.plain

function DanTools.IsEnemyPlayer(unit)
	if not plain(UnitIsPlayer(unit)) then return false end
	local faction = plain(UnitFactionGroup(unit))
	return faction ~= nil and faction ~= UnitFactionGroup("player")
end

-- Forever gives players a surname, and UnitName returns it second (where other versions of the game
-- return a realm). Returns "First Surname", which is the name the Death Recap and /targetexact use,
-- and the first name on its own. Units with no surname (mobs) get the same name twice.
function DanTools.FullName(unit)
	local first, surname = UnitName(unit)
	first, surname = plain(first), plain(surname)
	if type(first) ~= "string" or first == "" then return nil end
	if type(surname) ~= "string" or surname == "" then return first, first end
	if first:sub(-#surname - 1) == " " .. surname then return first, first end -- already holds both
	return first .. " " .. surname, first
end

function DanTools.Number(n)
	n = math.floor(n + 0.5)
	return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

-- "12g 40s", "40s 5c" or "5c", in coin colors
function DanTools.Money(copper)
	local sign = copper < 0 and "-" or ""
	copper = math.floor(math.abs(copper) + 0.5)
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	if g > 0 then return ("%s%s|cffffd100g|r %d|cffc7c7cfs|r"):format(sign, DanTools.Number(g), s) end
	if s > 0 then return ("%s%d|cffc7c7cfs|r %d|cffeda55fc|r"):format(sign, s, c) end
	return ("%s%d|cffeda55fc|r"):format(sign, c)
end

-- "45s", "12m" or "1h 05m"
function DanTools.Duration(sec)
	sec = math.floor(sec)
	if sec < 60 then return sec .. "s" end
	if sec < 3600 then return math.floor(sec / 60) .. "m" end
	return ("%dh %02dm"):format(math.floor(sec / 3600), math.floor(sec % 3600 / 60))
end

-- The dark panel look shared by DanTools' own windows.
function DanTools.Skin(frame)
	if not frame.SetBackdrop then return end
	frame:SetBackdrop({
		bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	frame:SetBackdropColor(0.06, 0.06, 0.08, 0.96)
	frame:SetBackdropBorderColor(0.5, 0.5, 0.55)
end

-- A scroll frame with Blizzard's scroll bar, or mouse-wheel-only if that template isn't there.
function DanTools.ScrollFrame(parent, name)
	local ok, scroll = pcall(CreateFrame, "ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
	if not ok then
		scroll = CreateFrame("ScrollFrame", name, parent)
		scroll:EnableMouseWheel(true)
		scroll:SetScript("OnMouseWheel", function(self, delta)
			local child = self:GetScrollChild()
			local max = math.max(0, (child and child:GetHeight() or 0) - self:GetHeight())
			self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * 30)))
		end)
	end
	return scroll
end

---------------------------------------------------------------------------------------------------
-- Fonts: the game's own, plus every font other addons registered with LibSharedMedia.

local BUILTIN_FONTS = {
	["Arial Narrow"] = "Fonts\\ARIALN.TTF", ["Friz Quadrata"] = "Fonts\\FRIZQT__.TTF",
	["Morpheus"] = "Fonts\\MORPHEUS.TTF", ["Skurri"] = "Fonts\\SKURRI.TTF",
}

local function sharedMedia()
	return LibStub and LibStub("LibSharedMedia-3.0", true)
end

function DanTools:FontNames()
	local names, have = {}, {}
	local lsm = sharedMedia()
	for _, name in ipairs(lsm and lsm:List("font") or {}) do
		names[#names + 1] = name
		have[name] = true
	end
	for name in pairs(BUILTIN_FONTS) do
		if not have[name] then names[#names + 1] = name end
	end
	table.sort(names)
	return names
end

function DanTools:FontPath(name) -- nil is the game's default font
	if not name then return STANDARD_TEXT_FONT end
	local lsm = sharedMedia()
	return lsm and lsm:IsValid("font", name) and lsm:Fetch("font", name) or BUILTIN_FONTS[name] or STANDARD_TEXT_FONT
end

---------------------------------------------------------------------------------------------------
-- Text displays

local function createDisplay(tool)
	local frame = CreateFrame("Button", "DanTools_" .. tool.key, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:RegisterForClicks("AnyUp")
	local dragged
	frame:SetScript("OnMouseDown", function() dragged = false end)
	frame:SetScript("OnDragStart", function(self)
		if DanTools.account.locked then return end
		dragged = true
		tool.dragging = true
		self:StartMoving()
	end)
	-- Also runs if the display is hidden mid-drag. A drag that never gets stopped leaves the frame
	-- stuck to the cursor, where it swallows every click.
	local function stopDrag(self)
		if not tool.dragging then return end
		tool.dragging = nil
		self:StopMovingOrSizing()
		local x, top = self:GetCenter(), self:GetTop()
		if x and top then
			-- anchored by its top edge, so a display that gains a line grows downward
			tool.db.pos = { "TOP", "BOTTOMLEFT", x, top }
		end
		DanTools:Place(tool)
		DanTools:UpdateVisibility(tool)
	end
	frame:SetScript("OnDragStop", stopDrag)
	frame:SetScript("OnHide", stopDrag)
	frame:SetScript("OnClick", function(_, mouseButton)
		if not dragged and tool.OnClick then tool:OnClick(mouseButton) end
	end)
	frame:SetScript("OnEnter", function(self)
		if not tool.OnTooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(tool.name)
		tool:OnTooltip(GameTooltip)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
	frame:Hide()
	tool.frame, tool.lines = frame, {}
	for i = 1, tool.display.lines do
		local line = frame:CreateFontString(nil, "OVERLAY")
		line:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
		if tool.display.icons then -- rows: an icon left of the text, and a strip behind both for the tool to color
			line.icon = frame:CreateTexture(nil, "ARTWORK")
			line.icon:Hide()
			line.back = frame:CreateTexture(nil, "BORDER")
			line.back:Hide()
		end
		tool.lines[i] = line
	end
end

function DanTools:AddTool(tool)
	if tool.display then createDisplay(tool) end
	table.insert(self.tools, tool)
	self.byKey[tool.key] = tool
	return tool
end

function DanTools:Place(tool)
	local p = tool.db.pos or tool.display.pos
	tool.frame:ClearAllPoints()
	tool.frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

-- Height of a row: a line with an icon (tool.display.icons).
function DanTools:RowHeight(tool)
	return (tool.db.look.size or 12) + 10
end

-- Stacks what the display is showing, top to bottom, and sizes the frame (and so its background)
-- around it: the lines that have text, and the bars that are switched on, each with room for a
-- label outside it (bar.labelAt). Bars line up: labels at the left or right all get the widest one's room.
-- A line with an icon is a row: taller, with the text left-aligned beside the icon (line.noIcon
-- turns that off for a line).
function DanTools:Layout(tool)
	local size = tool.db.look.size or 12
	local stack = tool.stack or tool.lines
	local left, right, barWidth = 0, 0, nil
	for _, item in ipairs(stack) do
		if item.isBar and item.on then
			barWidth = math.max(barWidth or 0, item.w)
			local labelWidth = item.outside:GetStringWidth() + 4
			if item.labelAt == "Left" then left = math.max(left, labelWidth) end
			if item.labelAt == "Right" then right = math.max(right, labelWidth) end
		end
	end
	local height = 0
	for _, item in ipairs(stack) do
		item:ClearAllPoints()
		if item.isBar then
			local at = item.on and item.labelAt or nil
			item:SetShown(item.on or false)
			item.outside:ClearAllPoints()
			item.outside:SetShown(at ~= nil)
			if item.on then
				if at == "Above" then height = height + size + 2 end
				item:SetSize(item.w, item.h)
				item:SetPoint("TOPLEFT", tool.frame, "TOPLEFT", PAD + left, -(PAD + height))
				height = height + item.h + 2
				if at == "Above" then
					item.outside:SetPoint("BOTTOM", item, "TOP", 0, 2)
				elseif at == "Below" then
					item.outside:SetPoint("TOP", item, "BOTTOM", 0, -2)
					height = height + size + 2
				elseif at == "Left" then
					item.outside:SetPoint("RIGHT", item, "LEFT", -4, 0)
				elseif at == "Right" then
					item.outside:SetPoint("LEFT", item, "RIGHT", 4, 0)
				end
			end
		elseif (item.dtText or "") ~= "" then
			if item.icon and not item.noIcon then
				local row = self:RowHeight(tool)
				item.icon:ClearAllPoints()
				item.icon:SetSize(row - 2, row - 2)
				item.icon:SetPoint("TOPLEFT", tool.frame, "TOPLEFT", PAD, -(PAD + height + 1))
				item.icon:Show()
				item.back:ClearAllPoints()
				item.back:SetPoint("TOPLEFT", tool.frame, "TOPLEFT", 1, -(PAD + height))
				item.back:SetPoint("BOTTOMRIGHT", tool.frame, "TOPRIGHT", -1, -(PAD + height + row))
				item:SetPoint("LEFT", item.icon, "RIGHT", 4, 0)
				height = height + row
			else
				if item.icon then item.icon:Hide() end
				item:SetPoint("TOP", tool.frame, "TOP", 0, -(PAD + height))
				height = height + size + 2
			end
		elseif item.icon then
			item.icon:Hide()
		end
	end
	if height == 0 then height = size + 2 end
	local width = barWidth and (left + barWidth + right) or tool.display.width * size / 12
	tool.frame:SetSize(width + PAD * 2, height + PAD * 2 - 2)
end

-- A bar for a display, with a label and a value (DanTools:SetBarText). It stays hidden until
-- DanTools:ShowBar, and goes where tool.stack puts it.
function DanTools:NewBar(tool)
	local bar = CreateFrame("StatusBar", nil, tool.frame)
	bar.isBar = true
	bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
	bar:Hide()
	local back = bar:CreateTexture(nil, "BACKGROUND")
	back:SetAllPoints()
	back:SetColorTexture(0, 0, 0, 0.5)
	bar.texts = {} -- the text on the bar
	for where, x in pairs({ LEFT = 4, CENTER = 0, RIGHT = -4 }) do
		local text = bar:CreateFontString(nil, "OVERLAY")
		text:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
		text:SetPoint(where, x, 0)
		bar.texts[where] = text
	end
	bar.outside = tool.frame:CreateFontString(nil, "OVERLAY") -- the label, when it sits beside the bar
	bar.outside:SetFont(STANDARD_TEXT_FONT, 12, "OUTLINE")
	bar.outside:Hide()
	tool.bars = tool.bars or {}
	table.insert(tool.bars, bar)
	return bar
end

DanTools.LABEL_PLACES = { "In bar", "Above", "Below", "Left", "Right" }

-- A bar's label and value. `at` is one of LABEL_PLACES: "In bar" puts the label at the bar's left
-- end and the value at its right; the others put the label beside the bar and center the value on
-- it. With no label ("") the value is centered too.
function DanTools:SetBarText(tool, bar, label, value, at)
	local beside = label ~= "" and at ~= "In bar" and at or nil
	local onBar = label ~= "" and not beside
	bar.texts.LEFT:SetText(onBar and label or "")
	bar.texts.RIGHT:SetText(onBar and value or "")
	bar.texts.CENTER:SetText(onBar and "" or value)
	bar.outside:SetText(beside and label or "")
	local key = beside and (beside .. label) or ""
	if bar.outsideKey ~= key then -- the label's place or size changed
		bar.labelAt, bar.outsideKey = beside, key
		if bar.on then self:Layout(tool) end
	end
end

-- Shows a bar at a size, or hides it (on = false, no size needed).
function DanTools:ShowBar(tool, bar, on, width, height)
	on = on and true or false
	if bar.on == on and (not on or (bar.w == width and bar.h == height)) then return end
	bar.on = on
	if on then bar.w, bar.h = width, height end
	self:Layout(tool)
end

-- Sets a display's lines, top to bottom. A line left out or "" takes no space.
function DanTools:SetLines(tool, ...)
	local relayout
	for i, line in ipairs(tool.lines) do
		local new = select(i, ...) or ""
		local old = line.dtText or ""
		if new ~= old then
			if (new == "") ~= (old == "") then relayout = true end
			line.dtText = new
			line:SetText(new)
		end
	end
	if relayout then self:Layout(tool) end
end

-- tool.db.look = { font, size, bg = { r, g, b, a }, border, borderColor = { r, g, b, a } }, all optional
function DanTools:ApplyLook(tool)
	local look, frame = tool.db.look, tool.frame
	local path, size = self:FontPath(look.font), look.size or 12
	for _, line in ipairs(tool.lines) do line:SetFont(path, size, "OUTLINE") end
	for _, bar in ipairs(tool.bars or {}) do
		for _, text in pairs(bar.texts) do text:SetFont(path, size, "OUTLINE") end
		bar.outside:SetFont(path, size, "OUTLINE")
	end
	if frame.SetBackdrop then
		local bg, edge = look.bg or CLEAR, look.borderColor or BLACK
		frame:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8x8",
			edgeFile = look.border and "Interface\\Buttons\\WHITE8x8" or nil, edgeSize = 1,
		})
		frame:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
		if look.border then frame:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4] or 1) end
	end
	self:Layout(tool)
end

-- An idle display is hidden (tool.db.hideIdle) or dimmed, except while the settings window is open.
-- With displays locked (DanTools.account.locked) none can be dragged, and one with nothing to click
-- or hover lets the mouse through.
function DanTools:UpdateVisibility(tool)
	local frame = tool.frame
	-- not mid-drag: a frame that loses its mouse then never gets OnDragStop (stopDrag catches up after)
	if not frame or tool.dragging then return end
	local idle = tool.idle and not self.settingsOpen
	local hidden = idle and tool.db.hideIdle
	local usesMouse = not self.account.locked or tool.OnClick ~= nil or tool.OnTooltip ~= nil
	frame:SetAlpha(hidden and 0 or idle and 0.4 or 1)
	frame:EnableMouse(not hidden and usesMouse)
end

function DanTools:SetIdle(tool, idle)
	if tool.idle ~= idle then
		tool.idle = idle
		self:UpdateVisibility(tool)
	end
end

function DanTools:SetSettingsOpen(on)
	self.settingsOpen = on
	for _, tool in ipairs(self.tools) do self:UpdateVisibility(tool) end
end

function DanTools:SetLocked(on)
	self.account.locked = on or nil
	for _, tool in ipairs(self.tools) do self:UpdateVisibility(tool) end
end

function DanTools:SetEnabled(tool, on)
	on = on and true or false
	tool.db.enabled = on
	if tool.frame then tool.frame:SetShown(on) end
	local handler = on and tool.OnEnable or tool.OnDisable
	if handler then handler(tool) end
	if on then self:UpdateVisibility(tool) end
end

---------------------------------------------------------------------------------------------------
-- Click bindings: a combo is the held modifiers plus the mouse button, like "ALT-RightButton".

local BUTTON_TEXT = { LeftButton = "Left-click", RightButton = "Right-click", MiddleButton = "Middle-click" }

function DanTools.ClickCombo(mouseButton)
	return (IsAltKeyDown() and "ALT-" or "") .. (IsControlKeyDown() and "CTRL-" or "")
		.. (IsShiftKeyDown() and "SHIFT-" or "") .. mouseButton
end

function DanTools.ComboText(combo) -- "ALT-RightButton" -> "Alt + Right-click"
	local mods, button = combo:match("^(.-)([^%-]+)$")
	local parts = {}
	if mods:find("ALT") then parts[#parts + 1] = "Alt" end
	if mods:find("CTRL") then parts[#parts + 1] = "Ctrl" end
	if mods:find("SHIFT") then parts[#parts + 1] = "Shift" end
	parts[#parts + 1] = BUTTON_TEXT[button] or (button:gsub("Button", "Mouse button ") .. " click")
	return table.concat(parts, " + ")
end

function DanTools:Binding(tool, key)
	local chosen = tool.db.bindings[key]
	if chosen then return chosen end
	for _, b in ipairs(tool.bindings) do
		if b.key == key then return b.default end
	end
end

function DanTools:IsBinding(tool, key, mouseButton)
	return self.ClickCombo(mouseButton) == self:Binding(tool, key)
end

---------------------------------------------------------------------------------------------------
-- Bag item buttons: tools add a decorator (text or marks on each item icon) or a click handler.

local IsModernBags = ContainerFrameMixin ~= nil
local NUM_FRAMES = NUM_TOTAL_BAG_FRAMES or NUM_CONTAINER_FRAMES
local bagFrames, bagDecorators, bagClicks = {}, {}, {}
local refreshQueued

function DanTools.BagSlot(button)
	return button.GetBagID and button:GetBagID() or button:GetParent():GetID(), button:GetID()
end

-- Per-button storage for the things tools add to a Blizzard item button.
function DanTools.ButtonData(button)
	local data = button.DanToolsData
	if not data then
		data = {}
		button.DanToolsData = data
	end
	return data
end

local function decorate(button)
	local data = DanTools.ButtonData(button)
	if not data.clickHooked then
		data.clickHooked = true
		button:HookScript("OnClick", function(self, mouseButton)
			for _, fn in ipairs(bagClicks) do fn(self, mouseButton) end
		end)
	end
	for _, d in ipairs(bagDecorators) do d.button(button) end
end

local function decorateFrame(frame)
	if IsModernBags then
		for _, button in frame:EnumerateValidItems() do decorate(button) end
	else
		local prefix = frame:GetName() .. "Item"
		for i = 1, frame.size or 0 do
			local button = _G[prefix .. i]
			if button then decorate(button) end
		end
	end
end

local function beforePass()
	for _, d in ipairs(bagDecorators) do
		if d.before then d.before() end
	end
end

-- d.button(button) runs for every bag item button on each update; d.before() once before each pass.
function DanTools:AddBagDecorator(d)
	table.insert(bagDecorators, d)
end

function DanTools:AddBagClick(fn) -- fn(button, mouseButton)
	table.insert(bagClicks, fn)
end

function DanTools:RefreshBags()
	self.bagWaiting = false -- a decorator sets this when item info wasn't loaded yet
	beforePass()
	for _, frame in ipairs(bagFrames) do
		if frame:IsShown() then decorateFrame(frame) end
	end
end

local function onBagFrameUpdate(frame)
	beforePass()
	decorateFrame(frame)
end

local function hookBags()
	if ContainerFrameCombinedBags then bagFrames[#bagFrames + 1] = ContainerFrameCombinedBags end
	for i = 1, NUM_FRAMES or 0 do bagFrames[#bagFrames + 1] = _G["ContainerFrame" .. i] end
	if IsModernBags then
		-- hooking the mixin doesn't reach bag frames that already exist, so hook those too
		hooksecurefunc(ContainerFrameMixin, "UpdateItems", onBagFrameUpdate)
		for _, frame in ipairs(bagFrames) do hooksecurefunc(frame, "UpdateItems", onBagFrameUpdate) end
	elseif ContainerFrame_Update then
		hooksecurefunc("ContainerFrame_Update", onBagFrameUpdate)
	end
end

---------------------------------------------------------------------------------------------------
-- Mana spending: tools are told each time you spend mana. It's seen as your mana dropping; where
-- Forever hides your mana from addons, as a spell you finished casting that costs mana.

local MANA = Enum and Enum.PowerType and Enum.PowerType.Mana or 0
DanTools.MANA = MANA
local manaListeners = {}
local lastMana -- nil while your mana is hidden

-- fn(amount): amount is nil when mana was spent but how much is hidden
function DanTools:OnManaSpent(fn)
	table.insert(manaListeners, fn)
end

local function manaSpent(amount)
	for _, fn in ipairs(manaListeners) do fn(amount) end
end

-- A spell's mana cost: a number (0 for none), or nil if it can't be read.
local function readManaCost(spellID)
	local costs = C_Spell.GetSpellPowerCost(spellID)
	if type(costs) ~= "table" then return nil end
	for _, c in ipairs(costs) do
		local kind, cost = plain(c.type), plain(c.cost)
		if kind == nil or cost == nil then return nil end
		if kind == MANA then return cost end
	end
	return 0
end

local manaWatcher = CreateFrame("Frame")
manaWatcher:SetScript("OnEvent", function(_, event, _, _, spellID)
	if event == "UNIT_SPELLCAST_SUCCEEDED" then
		if lastMana ~= nil then return end -- mana is readable, so the drop itself reports the spending
		spellID = plain(spellID)
		local cost
		if spellID and C_Spell and C_Spell.GetSpellPowerCost then
			local ok, result = pcall(readManaCost, spellID)
			if ok then cost = result end
		end
		if cost == nil then
			-- can't tell which spell or what it cost: count it if mana is what you're using right now
			if plain(UnitPowerType("player")) == MANA then manaSpent(nil) end
		elseif cost > 0 then
			manaSpent(cost)
		end
	else -- your mana changed
		local mana = plain(UnitPower("player", MANA))
		if mana and lastMana and mana < lastMana then manaSpent(lastMana - mana) end
		lastMana = mana
	end
end)

local function watchMana()
	lastMana = plain(UnitPower("player", MANA))
	manaWatcher:RegisterUnitEvent("UNIT_POWER_UPDATE", "player")
	manaWatcher:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
	manaWatcher:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
end

---------------------------------------------------------------------------------------------------
-- Grudge and Bag Value used to be separate addons. If one is still installed it loads first
-- (OptionalDeps) and its saved data is copied in once. It is switched off only on a later login,
-- once that copy has been saved with DanTools' own data.

function DanTools:ImportOld(addon, var, copy)
	local old = _G[var]
	if type(old) ~= "table" then return end
	if self.account.imported[addon] then
		if C_AddOns and C_AddOns.DisableAddOn then pcall(C_AddOns.DisableAddOn, addon) end
	else
		copy(old)
		self.account.imported[addon] = true
		print("DanTools: imported " .. addon .. ".")
	end
end

---------------------------------------------------------------------------------------------------

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_LOGIN" then
		DanToolsDB = DanToolsDB or {}
		DanToolsAccountDB = DanToolsAccountDB or {}
		local account = DanToolsAccountDB
		account.imported = account.imported or {}
		account.minimap = account.minimap or {}
		DanTools.account = account
		hookBags()
		-- every tool gets its settings, then its OnLoad, before any is switched on: tools use each other
		for _, tool in ipairs(DanTools.tools) do
			local db = DanToolsDB[tool.key] or {}
			DanToolsDB[tool.key] = db
			tool.db = db
			if db.enabled == nil then db.enabled = true end
			db.bindings = db.bindings or {}
			for _, o in ipairs(tool.options or {}) do
				if db[o.key] == nil then
					db[o.key] = type(o.default) == "table" and CopyTable(o.default) or o.default
				end
			end
			if tool.display then
				db.look = db.look or {}
				if db.hideIdle == nil then db.hideIdle = tool.display.hideIdle end
			end
		end
		for _, tool in ipairs(DanTools.tools) do
			if tool.OnLoad then tool:OnLoad() end
		end
		for _, tool in ipairs(DanTools.tools) do
			local db = tool.db
			if tool.frame then
				DanTools:Place(tool)
				DanTools:ApplyLook(tool)
			end
			DanTools:SetEnabled(tool, db.enabled)
		end
		if DanTools.Options then DanTools.Options.Init() end
		watchMana()
		self:RegisterEvent("BAG_UPDATE_DELAYED")
		self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		if DanTools.bagWaiting and not refreshQueued then
			refreshQueued = true
			C_Timer.After(0.2, function()
				refreshQueued = false
				DanTools:RefreshBags()
			end)
		end
	else
		DanTools:RefreshBags()
	end
end)
