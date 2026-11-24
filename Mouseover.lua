-- Mouseover Cast: Forever's "Mouseover Cast" setting sends an action bar spell at whoever is under your
-- cursor: a heal at a friend there, an attack at an enemy there. This chooses which of the two it
-- does. A spell that doesn't follow the cursor goes to your target, as it would with the setting off.
--
-- The game asks each action button, as it's pressed, whether it follows the cursor (the button's
-- "checkmouseovercast" attribute). This turns that on or off per button to suit what's on it.
-- Addons can't touch the buttons during combat, so the answer for each of the 180 action slots is
-- worked out beforehand and handed to a secure frame. When the main bar changes page mid-fight (a
-- druid form, a stance, stealth), that frame resets the bar's 12 buttons from those answers.
-- Something dragged onto a bar mid-fight is only picked up once the fight is over.
-- A spell that works on friends and enemies alike (a dispel, say) follows the cursor to both if
-- either box is ticked: a button can't be told who is under the cursor.

local _, DanTools = ...
local plain = DanTools.plain

local SWITCH = "checkmouseovercast"
local PER_BAR, SLOTS = 12, 180
local BARS = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
	"MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }
-- changes whenever the main bar's page might have: a bar picked, or a form, stance or stealth
local PAGE_CHANGES = "[bar:2] 2; [bar:3] 3; [bar:4] 4; [bar:5] 5; [bar:6] 6; [bonusbar:1] 7; [bonusbar:2] 8; "
	.. "[bonusbar:3] 9; [bonusbar:4] 10; [bonusbar:5] 11; [bonusbar:6] 12; 1"

-- "Hover bar": while a friend is under the cursor, the main bar's keys press this bar's buttons
-- instead, so one set of keys attacks your target and heals whoever you point at.
-- The bars go by their Edit Mode numbers. Picking one lights its buttons up green for a few seconds.
local HOVER_CHOICES = { "Off", "Bar 2", "Bar 3", "Bar 4", "Bar 5", "Bar 6", "Bar 7", "Bar 8" }
local HOVER_BARS = { ["Bar 2"] = "MultiBarBottomLeftButton", ["Bar 3"] = "MultiBarBottomRightButton",
	["Bar 4"] = "MultiBarRightButton", ["Bar 5"] = "MultiBarLeftButton", ["Bar 6"] = "MultiBar5Button",
	["Bar 7"] = "MultiBar6Button", ["Bar 8"] = "MultiBar7Button",
	-- the names 2.6.0 saved
	["Bottom Left"] = "MultiBarBottomLeftButton", ["Bottom Right"] = "MultiBarBottomRightButton",
	["Right"] = "MultiBarRightButton", ["Left"] = "MultiBarLeftButton" }
local FLASH_FOR = 4
-- the action page each of those bars shows, for putting it on the main bar
local HOVER_PAGES = { MultiBarBottomLeftButton = 6, MultiBarBottomRightButton = 5, MultiBarRightButton = 3,
	MultiBarLeftButton = 4, MultiBar5Button = 13, MultiBar6Button = 14, MultiBar7Button = 15 }

local tool = DanTools:AddTool({
	key = "mouseover",
	name = "Mouseover Cast",
	startOff = true, -- it changes where your spells go, so it's yours to switch on
	options = {
		{ type = "header", label = "At cursor" },
		{ key = "heal", label = "Heals", default = true },
		{ key = "harm", label = "Attacks", default = false },
		{ type = "header", label = "On friend" },
		{ key = "hoverBar", label = "Use bar", type = "choice", choices = HOVER_CHOICES, default = "Off" },
		{ key = "hoverShow", label = "Show on main bar", default = false, needs = "hoverBar" },
	},
})

local pager = CreateFrame("Frame", "DanToolsMouseoverPager", UIParent, "SecureHandlerStateTemplate")
-- Run by the game, fights included, when the main bar's page might have changed. Works the page out
-- the way the game's own bar does, then sets the 12 buttons from the answers for that page's slots.
pager:SetAttribute("_onstate-page", [[
	local page
	if HasVehicleActionBar() then
		page = GetVehicleBarIndex()
	elseif HasOverrideActionBar() then
		page = GetOverrideBarIndex()
	elseif HasTempShapeshiftActionBar() then
		page = GetTempShapeshiftBarIndex()
	elseif HasBonusActionBar() and GetActionBarPage() == 1 then
		page = GetBonusBarIndex()
	else
		page = GetActionBarPage()
	end
	if not page then return end
	self:SetAttribute("page", page)
	if self:GetAttribute("hovering") then return end -- the hover bar is on the buttons just now
	for i = 1, 12 do
		local button = self:GetFrameRef("b" .. i)
		if button then
			button:SetAttribute("checkmouseovercast", self:GetAttribute("ok" .. (i + (page - 1) * 12)) ~= false)
		end
	end
]])

-- Run by the game when a friend comes under the cursor or leaves it (it looks about five times a
-- second): moves the main bar's keys onto the hover bar's buttons, or hands them back.
local hover = CreateFrame("Frame", "DanToolsMouseoverHover", UIParent, "SecureHandlerStateTemplate")
hover:SetAttribute("_onstate-hover", [[
	self:ClearBindings()
	local prefix, page, pager = self:GetAttribute("bar"), self:GetAttribute("page"), self:GetFrameRef("pager")
	local on = newstate == "friend" and prefix
	local show = on and page and self:GetAttribute("show")
	if self:GetAttribute("shown") and not show then -- the main bar gets its own page back
		self:SetAttribute("shown", nil)
		for i = 1, 12 do
			local button = self:GetFrameRef("b" .. i)
			if button then button:SetAttribute("actionpage", nil) end
		end
		pager:SetAttribute("hovering", nil)
		pager:RunAttribute("_onstate-page")
	end
	if show then -- "Show on main bar": the main bar's buttons turn to the hover bar's page
		self:SetAttribute("shown", true)
		pager:SetAttribute("hovering", true)
		for i = 1, 12 do
			local button = self:GetFrameRef("b" .. i)
			if button then
				button:SetAttribute("checkmouseovercast", pager:GetAttribute("ok" .. (i + (page - 1) * 12)) ~= false)
				button:SetAttribute("actionpage", page)
			end
		end
	elseif on then -- else the main bar's keys press the hover bar's buttons where they are
		for i = 1, 12 do
			local first, second = GetBindingKey("ACTIONBUTTON" .. i)
			if first then self:SetBindingClick(true, first, prefix .. i, "LeftButton") end
			if second then self:SetBindingClick(true, second, prefix .. i, "LeftButton") end
		end
	end
]])
hover:SetFrameRef("pager", pager)
local hoverSent -- the bar the secure frame was last given

local managed = {} -- the buttons that follow the cursor as the game ships them: the only ones touched
local sent = {}    -- slot -> the answer the secure frame was last given
local ready, queued

local function call(fn, ...)
	if not fn then return nil end
	local ok, result = pcall(fn, ...)
	if ok then return plain(result) end
end

-- Whether what's in an action slot goes on friends, and whether on enemies: what the game itself
-- asks before it sends a press at the cursor.
local function slotKind(slot)
	local bar = C_ActionBar or {}
	local help, harm = call(bar.IsHelpfulAction, slot, false), call(bar.IsHarmfulAction, slot, false)
	if help or harm then return help, harm end
	-- no answer for a macro: go by the spell it would cast now
	local ok, kind, id, sub = pcall(GetActionInfo, slot)
	if not ok or plain(kind) ~= "macro" then return end
	id, sub = plain(id), plain(sub)
	local spell = id and (sub == "spell" and id or call(GetMacroSpell, id))
	if spell and C_Spell then return call(C_Spell.IsSpellHelpful, spell), call(C_Spell.IsSpellHarmful, spell) end
end

-- Whether what's in this action slot may follow the cursor.
local function allowed(slot)
	local db = tool.db
	if not db.enabled then return true end
	local help, harm = slotKind(slot)
	if help and not harm then return db.heal end
	if harm and not help then return db.harm end
	return db.heal or db.harm -- both kinds, or neither (nothing that takes a target)
end

-- The action slot a button shows now, its bar's page counted in.
local function slotOf(button)
	local slot = plain(button.action)
	if type(slot) == "number" and slot > 0 then return slot end
end

-- Brings the secure frame's answers, and every button, in line with what's on the bars now.
local function apply()
	queued = false
	if not ready or InCombatLockdown() then return end -- the end of the fight comes back to it
	for slot = 1, SLOTS do
		local ok = allowed(slot)
		if sent[slot] ~= ok then
			sent[slot] = ok
			pager:SetAttribute("ok" .. slot, ok)
		end
	end
	local bar = tool.db.enabled and HOVER_BARS[tool.db.hoverBar] or nil
	local hoverNow = tostring(bar) .. tostring(tool.db.hoverShow)
	if hoverNow ~= hoverSent then
		hoverSent = hoverNow
		hover:SetAttribute("bar", bar)
		hover:SetAttribute("page", bar and HOVER_PAGES[bar])
		hover:SetAttribute("show", tool.db.hoverShow)
		hover:SetAttribute("state-hover", "none") -- undoes the old setup; the next look at the cursor makes the new
	end
	for _, button in ipairs(managed) do
		local slot = slotOf(button)
		local ok = not slot or sent[slot] ~= false
		if (button:GetAttribute(SWITCH) and true or false) ~= ok then button:SetAttribute(SWITCH, ok) end
	end
	-- a check on the secure frame's page, kept in the saved file in case this ever misbehaves
	local page, slot = pager:GetAttribute("page"), ActionButton1 and slotOf(ActionButton1)
	if page and slot and not hover:GetAttribute("shown") and slot ~= (page - 1) * PER_BAR + 1 then
		DanTools.account.mouseover.mismatch = ("page %s, slot %d"):format(tostring(page), slot)
	end
end

local function refresh()
	if queued then return end
	queued = true
	C_Timer.After(0.1, apply) -- once the game has finished updating its bars
end

-- Finds the buttons and starts following the main bar's page. Waits out a fight.
local function setup()
	if ready or InCombatLockdown() then return end
	for _, prefix in ipairs(BARS) do
		for i = 1, PER_BAR do
			local button = _G[prefix .. i]
			if button and button.GetAttribute and button:GetAttribute(SWITCH) then
				managed[#managed + 1] = button
				if prefix == "ActionButton" then
					pager:SetFrameRef("b" .. i, button)
					hover:SetFrameRef("b" .. i, button)
				end
			end
		end
	end
	ready = true
	DanTools.account.mouseover = { buttons = #managed }
	apply() -- the answers first, so the secure frame finds them there on its first run
	RegisterStateDriver(pager, "page", PAGE_CHANGES)
	RegisterStateDriver(hover, "hover", "[@mouseover,help] friend; none")
	if #managed == 0 then print("|cffffd100DanTools|r Mouseover Cast: no buttons") end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function()
	if not tool.db then return end
	if tool.db.enabled then setup() end
	refresh()
end)
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_ENABLED", "ACTIONBAR_SLOT_CHANGED",
	"ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR", "UPDATE_SHAPESHIFT_FORM", "UPDATE_VEHICLE_ACTIONBAR",
	"UPDATE_OVERRIDE_ACTIONBAR", "SPELLS_CHANGED", "UPDATE_MACROS" }) do
	pcall(events.RegisterEvent, events, event) -- not every version of the game has every one
end

-- "/dantools mouseover": whether the game's own setting is on, how many buttons this runs, and how
-- many of those don't follow the cursor right now.
function DanTools:PrintMouseover()
	local getCVar = C_CVar and C_CVar.GetCVar or GetCVar
	local off = 0
	for _, button in ipairs(managed) do
		if not button:GetAttribute(SWITCH) then off = off + 1 end
	end
	print(("|cffffd100DanTools|r mouseover: %s, game setting %s, %d buttons, %d off"):format(
		tool.db.enabled and "on" or "off", tostring(call(getCVar, "enableMouseoverCast")), #managed, off))
end

-- Lights up the buttons of the hover bar just picked, so you can see which bar that is.
local flash = CreateFrame("Frame", nil, UIParent)
flash:SetFrameStrata("TOOLTIP")
flash:Hide()
flash.marks = {}
flash:SetScript("OnUpdate", function(self, dt)
	self.left = self.left - dt
	if self.left <= 0 then self:Hide() end
end)

local function showBar(prefix)
	flash:Hide()
	if not prefix then return end
	for i = 1, PER_BAR do
		local mark = flash.marks[i] or flash:CreateTexture(nil, "OVERLAY")
		flash.marks[i] = mark
		local button = _G[prefix .. i]
		mark:SetShown(button ~= nil)
		if button then
			mark:SetColorTexture(0.2, 1, 0.2, 0.55)
			mark:ClearAllPoints()
			mark:SetAllPoints(button)
		end
	end
	flash.left = FLASH_FOR
	flash:Show()
end

function tool:OnOption(key, value)
	if key == "hoverBar" then showBar(HOVER_BARS[value]) end
	refresh()
end

function tool:OnEnable()
	setup()
	refresh()
end

function tool:OnDisable()
	refresh() -- with the tool off every slot may follow the cursor, which puts the buttons back
end

function tool:OnPreview(key, value) -- the mouse is over a choice in the settings window
	if key == "hoverBar" then showBar(HOVER_BARS[value]) end
end

---------------------------------------------------------------------------------------------------
-- The picture on the settings page: the main bar's keys across the top, and under each what it casts,
-- normally and (with a bar picked) with a friend under the cursor. A small cursor on an icon means
-- that one goes to whoever you point at.

local ICON, GAP, LABEL_W = 26, 2, 76
local CURSOR = [[Interface\CURSOR\Point]]

local function keyText(i)
	local key = GetBindingKey("ACTIONBUTTON" .. i)
	if not key then return "" end
	key = key:gsub("SHIFT%-", "s"):gsub("CTRL%-", "c"):gsub("ALT%-", "a"):gsub("MOUSEWHEEL", "W"):gsub("BUTTON", "M")
		:gsub("NUMPAD", "N")
	return key:sub(1, 4)
end

function tool:BuildPreview(parent)
	local frame = CreateFrame("Frame", nil, parent)
	local step = ICON + GAP
	frame:SetSize(LABEL_W + PER_BAR * step, 18 + 2 * step + 4)
	local keys, rows = {}, {}
	for i = 1, PER_BAR do
		local key = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		key:SetPoint("TOP", frame, "TOPLEFT", LABEL_W + (i - 1) * step + ICON / 2, -4)
		keys[i] = key
	end
	for r, name in ipairs({ "Normal", "On friend" }) do
		local row = CreateFrame("Frame", nil, frame)
		row:SetAllPoints()
		row.cells = {}
		local top = -18 - (r - 1) * step
		local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		label:SetPoint("LEFT", frame, "TOPLEFT", 4, top - ICON / 2)
		label:SetText(name)
		for i = 1, PER_BAR do
			local icon = row:CreateTexture(nil, "ARTWORK")
			icon:SetSize(ICON, ICON)
			icon:SetPoint("TOPLEFT", LABEL_W + (i - 1) * step, top)
			local mark = row:CreateTexture(nil, "OVERLAY")
			mark:SetSize(16, 16)
			mark:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 5, -5)
			mark:SetTexture(CURSOR)
			row.cells[i] = { icon = icon, mark = mark }
		end
		rows[r] = row
	end

	-- friend: this row is what the keys do with a friend under the cursor, so only heals follow it
	local function fill(row, slotAt, friend)
		for i, cell in ipairs(row.cells) do
			local slot = slotAt(i)
			local texture = slot and call(GetActionTexture, slot)
			local follows = false
			if texture then
				cell.icon:SetTexture(texture)
				cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
				local help, harm = slotKind(slot)
				follows = (help or (harm and not friend)) and allowed(slot) and true or false
			else
				cell.icon:SetColorTexture(0, 0, 0, 0.4)
			end
			cell.mark:SetShown(follows)
		end
	end
	local function redraw()
		local bar = tool.db.enabled and HOVER_BARS[tool.db.hoverBar]
		local page = bar and HOVER_PAGES[bar]
		for i = 1, PER_BAR do keys[i]:SetText(keyText(i)) end
		fill(rows[1], function(i)
			local button = _G["ActionButton" .. i]
			return button and slotOf(button)
		end)
		rows[2]:SetShown(page ~= nil)
		if page then fill(rows[2], function(i) return (page - 1) * PER_BAR + i end, true) end
	end
	local wait = 0
	frame:SetScript("OnUpdate", function(_, dt) -- the bars can change while the window is open
		wait = wait + dt
		if wait < 0.5 then return end
		wait = 0
		redraw()
	end)
	return frame, frame:GetHeight(), redraw
end
