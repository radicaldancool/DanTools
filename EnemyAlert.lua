-- Enemy Alert: lists enemy-faction players as soon as you can see them (their nameplate appears, or you
-- target or mouse over them) with level and class, and flags the ones on your Grudge list.
-- A player stays listed while their nameplate is up, and for a few seconds after.
--
-- Left-clicking a listed player targets them. Only the game's own "secure" buttons may target, and
-- those can't be changed, shown, hidden or moved during combat. So an invisible secure button sits
-- over each line. Out of combat it exists only while its line is filled, and targets that player by
-- name. For the length of a fight all of them are up and target the nearest enemy player instead
-- (click again for the next one), because the list changes mid-fight and the buttons can't follow it.

local _, DanTools = ...
local plain, isEnemyPlayer = DanTools.plain, DanTools.IsEnemyPlayer

local SHOW_FOR = 12  -- seconds a player stays listed after you last saw them
local REALERT = 60   -- seconds before the same player can sound the alert again
local SOUND_GAP = 2  -- at most one sound in this many seconds
local SOUND = SOUNDKIT and SOUNDKIT.MAP_PING or 3175
local GRUDGE_SOUND = SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959
local PAD = DanTools.PAD

local tool = DanTools:AddTool({
	key = "enemy",
	name = "Enemy Alert",
	display = { width = 250, lines = 3, pos = { "CENTER", "CENTER", 0, 160 }, hideIdle = true },
	options = {
		{ key = "sound", label = "Sound", default = true },
		{ key = "grudgeOnly", label = "Grudge only", default = false },
		{ key = "click", label = "Click to target", default = true },
	},
})

local entries = {} -- oldest first: { name, target, text, seenAt }
local alerted = {} -- name -> when the alert last sounded for them
local lastSound = 0

local rows = {}    -- the secure click-to-target button over each line
local rowsState    -- what the rows were last set up for, so they're only touched when that changes
for i = 1, #tool.lines do
	local row = CreateFrame("Button", "DanToolsEnemyRow" .. i, UIParent, "SecureActionButtonTemplate")
	row:SetFrameLevel(tool.frame:GetFrameLevel() + 5)
	row:RegisterForClicks("AnyUp")
	row:SetAttribute("useOnKeyDown", false)
	row:SetAttribute("type1", "macro")
	row:Hide()
	rows[i] = row
end

-- Puts row i over line i of the display. Returns false if the display has no position yet.
local function placeRow(row, i)
	local frame = tool.frame
	local x, top = frame:GetCenter(), frame:GetTop()
	if not x or not top then return false end
	local size = tool.db.look.size or 12
	row:SetSize(frame:GetWidth(), size + 2)
	row:ClearAllPoints()
	row:SetPoint("TOP", UIParent, "BOTTOMLEFT", x, top - PAD - (i - 1) * (size + 2))
	return true
end

-- Out of combat: a row for each listed player (newest on top, like the lines), targeting them by name.
local function syncRows()
	if InCombatLockdown() then return end
	local frame = tool.frame
	local on = tool.db.enabled and tool.db.click
	local state = { tostring(on), tostring((frame:GetCenter())), tostring(frame:GetTop()), frame:GetWidth(),
		tool.db.look.size or 12 }
	for i = #entries, 1, -1 do state[#state + 1] = entries[i].target end
	state = table.concat(state, "|")
	if state == rowsState then return end
	rowsState = state
	for i, row in ipairs(rows) do
		local entry = on and entries[#entries - i + 1]
		if entry and placeRow(row, i) then
			row:SetAttribute("macrotext1", "/targetexact " .. entry.target)
			row:Show()
		else
			row:Hide()
		end
	end
end

-- Entering combat: every row up, each targeting the nearest enemy player.
local function armRows()
	if not (tool.db.enabled and tool.db.click) then return end
	rowsState = nil
	for i, row in ipairs(rows) do
		if placeRow(row, i) then
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

local function describe(unit, name, grudge)
	local _, class = UnitClass(unit)
	class = plain(class)
	local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
	local level, levelText = plain(UnitLevel(unit)), "??"
	if level and level > 0 then
		local gap = level - UnitLevel("player")
		levelText = gap == 0 and tostring(level) or ("%d (%+d)"):format(level, gap)
		if gap >= 5 then levelText = "|cffff2020" .. levelText .. "|r" end
	elseif level == -1 then
		levelText = "|cffff2020?? (10+ above)|r"
	end
	local text = ("%s  %s %s"):format(color and color.colorStr and ("|c" .. color.colorStr .. name .. "|r") or name,
		levelText, plain((UnitClass(unit))) or "")
	if grudge then text = ("%s  |cffff2020Grudge x%d|r"):format(text, #grudge.deaths) end
	return text
end

local function redraw()
	if #entries == 0 then
		DanTools:SetLines(tool, "|cffffd100Enemies|r --")
		DanTools:SetIdle(tool, true)
	else
		local lines = {}
		for i = #entries, 1, -1 do lines[#lines + 1] = entries[i].text end -- newest on top
		DanTools:SetLines(tool, lines[1], lines[2], lines[3])
		DanTools:SetIdle(tool, false)
	end
	syncRows()
end

local function note(unit)
	if not plain(UnitExists(unit)) or not isEnemyPlayer(unit) or plain(UnitIsDead(unit)) then return end
	local name, realm = UnitName(unit)
	name, realm = plain(name), plain(realm)
	if not name then return end
	local grudge = DanTools.GrudgeEntry and DanTools.GrudgeEntry(name)
	if tool.db.grudgeOnly and not grudge then return end
	local now = GetTime()
	local entry
	for _, e in ipairs(entries) do
		if e.name == name then entry = e end
	end
	if not entry then
		entry = { name = name, target = (realm and realm ~= "") and (name .. "-" .. realm) or name }
		entries[#entries + 1] = entry
		if #entries > #tool.lines then table.remove(entries, 1) end
	end
	entry.text, entry.seenAt = describe(unit, name, grudge), now
	if not alerted[name] or now - alerted[name] > REALERT then
		alerted[name] = now
		if tool.db.sound and now - lastSound > SOUND_GAP then
			lastSound = now
			PlaySound(grudge and GRUDGE_SOUND or SOUND, "Master")
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
	end
	local now = GetTime()
	for i = #entries, 1, -1 do
		if now - entries[i].seenAt > SHOW_FOR then table.remove(entries, i) end
	end
	redraw() -- also keeps the rows over the lines after the display is moved or resized
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

function tool:OnOption()
	syncRows()
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
	syncRows()
end
