-- Enemy Alert: lists enemy-faction players as soon as you can see them (their nameplate appears, or you
-- target or mouse over them) with a class icon, their name and their level. Players on your Grudge list
-- go to the top, on a red row with a skull.
-- A player stays listed while their nameplate is up, and for "Stay (s)" seconds after.
--
-- Left-clicking a row, icon included, targets that player. Only the game's own "secure" buttons may
-- target, and those can't be changed, shown, hidden or moved during combat. So an invisible secure
-- button sits over each row. Out of combat it exists only while its row is filled, and targets that
-- player by name. If anyone is listed when a fight starts, all of them are up for the length of it
-- and target the nearest enemy player instead (click again for the next one), because the list
-- changes mid-fight and the buttons can't follow it.

local _, DanTools = ...
local plain, isEnemyPlayer = DanTools.plain, DanTools.IsEnemyPlayer

local KEEP = 20      -- most players remembered at once; the display shows the top few
local REALERT = 60   -- seconds out of sight before the same player can sound the alert again
local SOUND_GAP = 2  -- at most one sound in this many seconds
local SOUND = SOUNDKIT and SOUNDKIT.MAP_PING or 3175
local GRUDGE_SOUND = SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959
local PAD = DanTools.PAD
local CLASS_ICONS = [[Interface\GLUES\CHARACTERCREATE\UI-CHARACTERCREATE-CLASSES]]
local NO_CLASS = [[Interface\Icons\INV_Misc_QuestionMark]]
local SKULL = [[|TInterface\TargetingFrame\UI-RaidTargetingIcon_8:0|t]]
local HOVER = [[Interface\QuestFrame\UI-QuestTitleHighlight]]

local tool = DanTools:AddTool({
	key = "enemy",
	name = "Enemy Alert",
	display = { width = 320, lines = 10, icons = true, pos = { "CENTER", "CENTER", 0, 160 }, hideIdle = true },
	options = {
		{ key = "sound", label = "Sound", default = true },
		{ key = "ownSound", label = "Custom sound", default = true }, -- Sounds/EnemyAlert.ogg in place of the ping
		{ key = "grudgeOnly", label = "Grudge only", default = false },
		{ key = "click", label = "Click to target", default = true },
		{ key = "stay", label = "Stay (s)", type = "number", default = 60, min = 10, max = 600, step = 10 },
		{ key = "rows", label = "Rows", type = "number", default = 5, min = 1, max = 10, step = 1 }, -- max = display.lines
	},
})

local entries = {} -- oldest first: { name, first, class, grudge, text, seenAt }
local shown = {}   -- the entries on the rows, top to bottom: Grudge players, then the newest
local alerted = {} -- name -> when the alert last sounded for them
local lastSound = 0

for _, line in ipairs(tool.lines) do line.back:SetColorTexture(0.9, 0, 0, 0.4) end -- shown on Grudge rows

-- Your own sound if it's on and the file is there, else the ping. Grudge players get the raid warning
-- as well.
local function alertSound(grudge)
	local played = tool.db.ownSound and DanTools.PlayOwnSound("EnemyAlert")
	if grudge then
		PlaySound(GRUDGE_SOUND, "Master")
	elseif not played then
		PlaySound(SOUND, "Master")
	end
end

local function setIcon(icon, class)
	local coords = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
	if coords then
		icon:SetTexture(CLASS_ICONS)
		icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
	else
		icon:SetTexture(NO_CLASS)
		icon:SetTexCoord(0, 1, 0, 1)
	end
end

-- Whether this version of the game can act on the press of a click rather than its release (a game
-- setting decides which). Where it can, a button has to hear both; the game only acts on one.
local getCVar = C_CVar and C_CVar.GetCVar or GetCVar
local PRESS_OR_RELEASE = getCVar and getCVar("ActionButtonUseKeyDown") ~= nil

local rows = {}    -- the secure click-to-target button over each row
local rowsState    -- what the buttons were last set up for, so they're only touched when that changes
for i = 1, #tool.lines do
	local row = CreateFrame("Button", "DanToolsEnemyRow" .. i, UIParent, "SecureActionButtonTemplate")
	row:SetFrameLevel(tool.frame:GetFrameLevel() + 5)
	if PRESS_OR_RELEASE then row:RegisterForClicks("AnyUp", "AnyDown") else row:RegisterForClicks("AnyUp") end
	row:SetAttribute("useOnKeyDown", false)
	row:SetAttribute("type1", "macro")
	row:SetHighlightTexture(HOVER, "ADD")
	-- right and middle clicks go to whatever is behind the button
	if row.SetPassThroughButtons then pcall(row.SetPassThroughButtons, row, "RightButton", "MiddleButton") end
	row:Hide()
	rows[i] = row
end

-- Puts button i over row i of the display. Returns false if the display has no position yet.
local function placeRow(row, i)
	local frame = tool.frame
	local x, top = frame:GetCenter(), frame:GetTop()
	if not x or not top then return false end
	local height = DanTools:RowHeight(tool)
	row:SetSize(frame:GetWidth(), height)
	row:ClearAllPoints()
	row:SetPoint("TOP", UIParent, "BOTTOMLEFT", x, top - PAD - (i - 1) * height)
	return true
end

-- Targets a player by name. A line that finds them replaces the one before, so the full name wins,
-- and a name nobody answers to leaves your target alone. The first name on its own, and the two
-- joined the game's way, are tried in case that's what this version of the game goes by.
local JOIN = Constants and Constants.CharacterNameSeparatorConsts
	and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR
local function targetMacro(entry)
	local lines = {}
	if entry.first ~= entry.name then
		lines[1] = "/targetexact " .. entry.first
		if type(JOIN) == "string" and JOIN ~= "" and JOIN ~= " " then
			lines[2] = "/targetexact " .. entry.first .. JOIN .. entry.name:sub(#entry.first + 2)
		end
	end
	lines[#lines + 1] = "/targetexact " .. entry.name
	return table.concat(lines, "\n")
end

-- Out of combat: a button for each listed player, targeting them by name.
local function syncRows()
	if InCombatLockdown() then return end
	local frame = tool.frame
	local on = tool.db.enabled and tool.db.click
	local state = { tostring(on), tostring((frame:GetCenter())), tostring(frame:GetTop()), frame:GetWidth(),
		tool.db.look.size or 12 }
	for _, entry in ipairs(shown) do state[#state + 1] = entry.name end
	state = table.concat(state, "|")
	if state == rowsState then return end
	rowsState = state
	for i, row in ipairs(rows) do
		local entry = on and shown[i]
		if entry and placeRow(row, i) then
			row:SetAttribute("macrotext1", targetMacro(entry))
			row:Show()
		else
			row:Hide()
		end
	end
end

-- Entering combat with someone listed: every button up, each targeting the nearest enemy player.
-- With no one listed they stay away, so the display's patch of screen doesn't swallow clicks.
local function armRows()
	if not (tool.db.enabled and tool.db.click) or #shown == 0 then return end
	rowsState = nil
	for i, row in ipairs(rows) do
		if i <= tool.db.rows and placeRow(row, i) then
			row:SetAttribute("macrotext1", "/targetenemyplayer")
			row:Show()
		end
	end
end

local combat = CreateFrame("Frame")
combat:RegisterEvent("PLAYER_REGEN_DISABLED") -- fires just before the combat lockdown starts
combat:RegisterEvent("PLAYER_REGEN_ENABLED")
combat:SetScript("OnEvent", function(_, event)
	if not tool.db then return end
	if event == "PLAYER_REGEN_DISABLED" then armRows() else syncRows() end
end)

-- "Name  34 (+10)", the name in its class color. Grudge players get a skull in front and
-- "GRUDGE x2" (how often they killed you) behind.
local function describe(unit, name, class, grudge)
	local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	local level, levelText = plain(UnitLevel(unit)), "??"
	if level and level > 0 then
		local gap = level - UnitLevel("player")
		levelText = gap == 0 and tostring(level) or ("%d (%+d)"):format(level, gap)
		if gap >= 5 then levelText = "|cffff2020" .. levelText .. "|r" end
	elseif level == -1 then
		levelText = "|cffff2020?? (10+ above)|r"
	end
	local text = ("%s  %s"):format(color and color.colorStr and ("|c" .. color.colorStr .. name .. "|r") or name,
		levelText)
	if grudge then text = ("%s %s  |cffffd100GRUDGE x%d|r"):format(SKULL, text, #grudge.deaths) end
	return text
end

-- Picks who is on the rows ("Rows" of them at most): Grudge players first, then everyone else,
-- newest on top in both.
local function arrange()
	local limit = math.min(tool.db.rows, #tool.lines)
	wipe(shown)
	for pass = 1, 2 do
		for i = #entries, 1, -1 do
			local entry = entries[i]
			if #shown < limit and entry.grudge == (pass == 1) then shown[#shown + 1] = entry end
		end
	end
end

local function redraw()
	arrange()
	local lines, idle = tool.lines, #shown == 0
	local texts = {}
	for i, line in ipairs(lines) do
		local entry = shown[i]
		texts[i] = entry and entry.text or ""
		line.back:SetShown(entry ~= nil and entry.grudge)
		if entry then setIcon(line.icon, entry.class) end
	end
	if idle then texts[1] = "|cffffd100Enemies|r --" end
	local relayout = (lines[1].noIcon or false) ~= idle
	lines[1].noIcon = idle -- the placeholder is plain text, with no icon
	DanTools:SetLines(tool, unpack(texts, 1, #lines))
	if relayout then DanTools:Layout(tool) end
	DanTools:SetIdle(tool, idle)
	syncRows()
end

local function note(unit)
	if not plain(UnitExists(unit)) or not isEnemyPlayer(unit) then return end
	local name, first = DanTools.FullName(unit)
	if not name then return end
	local at
	for i, e in ipairs(entries) do
		if e.name == name then at = i end
	end
	if plain(UnitIsDead(unit)) then -- a corpse comes off the list
		if at then
			table.remove(entries, at)
			redraw()
		end
		return
	end
	local grudge = DanTools.GrudgeEntry and DanTools.GrudgeEntry(name)
	if tool.db.grudgeOnly and not grudge then return end
	local now = GetTime()
	local entry = at and entries[at]
	-- new to the list, or back after long enough out of sight: the only times the alert may sound
	local arrived = not entry or now - entry.seenAt > REALERT
	if not entry then
		entry = { name = name, first = first }
		entries[#entries + 1] = entry
	end
	local _, class = UnitClass(unit)
	entry.class, entry.grudge = plain(class), grudge and true or false
	entry.text, entry.seenAt = describe(unit, name, entry.class, grudge), now
	if #entries > KEEP then -- full: whoever was seen longest ago goes
		local oldest = 1
		for i, e in ipairs(entries) do
			if e.seenAt < entries[oldest].seenAt then oldest = i end
		end
		table.remove(entries, oldest)
	end
	if arrived and (not alerted[name] or now - alerted[name] > REALERT) then
		alerted[name] = now
		if tool.db.sound and now - lastSound > SOUND_GAP then
			lastSound = now
			alertSound(grudge)
		end
	end
	redraw()
end

local function inBattleground()
	local _, kind = IsInInstance()
	return kind == "pvp" or kind == "arena"
end

local tick = 0
tool.frame:SetScript("OnUpdate", function(_, dt)
	tick = tick + dt
	if tick < 1 then return end
	tick = 0
	if not inBattleground() then
		for _, plate in ipairs(C_NamePlate.GetNamePlates()) do -- whoever is still in view stays listed
			local unit = plate.UnitFrame and plain(plate.UnitFrame.unit)
			if unit then note(unit) end
		end
		note("target") -- stays listed while targeted, and comes off if it dies
	end
	local now = GetTime()
	for i = #entries, 1, -1 do
		if now - entries[i].seenAt > tool.db.stay then table.remove(entries, i) end
	end
	redraw() -- also keeps the buttons over the rows after the display is moved or resized
end)
tool.frame:SetScript("OnEvent", function(_, event, unit)
	if inBattleground() then return end
	if event == "NAME_PLATE_UNIT_ADDED" then
		unit = plain(unit)
		if unit then note(unit) end
	elseif event == "PLAYER_TARGET_CHANGED" then
		note("target")
	else
		note("mouseover")
	end
end)

function tool:OnOption(key, value)
	if key == "grudgeOnly" and value then -- the others come off now, not when their time runs out
		for i = #entries, 1, -1 do
			if not entries[i].grudge then table.remove(entries, i) end
		end
	end
	if self.db.enabled then redraw() else syncRows() end
end

function tool:OnEnable()
	self.frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
	self.frame:RegisterEvent("PLAYER_TARGET_CHANGED")
	self.frame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
	redraw()
end

function tool:OnDisable()
	self.frame:UnregisterAllEvents()
	wipe(entries)
	wipe(shown)
	syncRows()
end
