-- Grudge List: remembers enemy-faction players who kill you. Their nameplates turn magenta, their
-- tooltip lists each death (your level, theirs, where, when), and /grudge opens the list.
-- Forever gives addons no combat log, so the killer comes from Blizzard's Death Recap, which only
-- has a name. A name you saw on an enemy player is confirmed right away; any other name (that you
-- never saw as a mob) is kept unconfirmed until you next see it: on an enemy player it's confirmed,
-- on a mob or a same-faction player it's dropped.
-- Players are known by their full name ("First Surname", DanTools.FullName), as the Death Recap gives it.

local _, DanTools = ...
local plain, isEnemyPlayer = DanTools.plain, DanTools.IsEnemyPlayer

local COLOR = { r = 1, g = 0, b = 1 } -- nameplate health bar color for players on your list
local SEEN_FOR = 30 * 60              -- seconds a seen enemy player still counts as a possible killer
local SHOWN_DEATHS = 5                -- most recent deaths listed per player

local tool = DanTools:AddTool({
	key = "grudge",
	name = "Grudge List",
})

local db           -- DanTools.account.grudge: { killers = { name -> entry }, lastDeath = report }
local seen = {}    -- name -> what we last saw of that enemy player
local npcs = {}    -- names seen on mobs and pets this session
local friends = {} -- names seen on same-faction players this session
local window
local refreshWindow -- defined with the window, below

-- The Grudge entry for a player name, for other tools (nil while this tool is off).
function DanTools.GrudgeEntry(name)
	return tool.db.enabled and db.killers[name] or nil
end

-- A name from the Death Recap, or nil if it's hidden or blank. Forever has no realms, so it's whole.
local function recapName(name)
	name = plain(name)
	return type(name) == "string" and name ~= "" and name or nil
end

-- "You 24, them 34 (+10)". 5+ levels above you is red; -1 is the game's skull level (10+ above you);
-- "~" marks a level filled in when you first saw them after the death.
local function levels(d)
	local them = "?"
	if d.theirLevel == -1 then
		them = "|cffff2020?? (10+ above)|r"
	elseif d.theirLevel then
		local gap = d.theirLevel - d.myLevel
		them = (d.theirLevelApprox and "~" or "") .. d.theirLevel
		if gap ~= 0 then them = ("%s (%+d)"):format(them, gap) end
		if gap >= 5 then them = "|cffff2020" .. them .. "|r" end
	end
	return ("You %d, them %s"):format(d.myLevel, them)
end

local function deathLine(d, me)
	return ("%s - %s%s - %s%s"):format(levels(d), d.subzone and (d.subzone .. ", ") or "", d.zone,
		date("%b %d", d.time), d.char ~= me and (" (" .. d.char .. ")") or "")
end

local function note(unit)
	if not plain(UnitExists(unit)) then return end
	local name = DanTools.FullName(unit)
	local isPlayer = UnitIsPlayer(unit)
	if not name or (issecretvalue and issecretvalue(isPlayer)) then return end
	-- a player whose faction is hidden could be on either side: nothing to learn from them
	if isPlayer and plain(UnitFactionGroup(unit)) == nil then return end
	local entry = db.killers[name]
	if not isPlayer or not isEnemyPlayer(unit) then
		if isPlayer then friends[name] = true else npcs[name] = true end
		if entry and not entry.confirmed then -- wasn't an enemy player after all
			db.killers[name] = nil
			refreshWindow()
		end
		return
	end
	local _, class = UnitClass(unit)
	local info = {
		class = plain(class),
		race = plain(UnitRace(unit)),
		level = plain(UnitLevel(unit)),
		guild = plain(GetGuildInfo(unit)),
		time = GetTime(),
	}
	seen[name] = info
	if entry and not entry.confirmed then
		entry.confirmed = true
		entry.class, entry.race = info.class, info.race
		entry.guild = info.guild or entry.guild
		for _, d in ipairs(entry.deaths) do
			if not d.theirLevel and info.level then d.theirLevel, d.theirLevelApprox = info.level, true end
		end
		print(("|cffff00ffGrudge:|r spotted %s (%s %s)."):format(name, info.race or "",
			(info.class or "player"):lower()))
		refreshWindow()
	end
end

local function colorPlate(frame)
	if not tool.db.enabled then return end
	local unit = plain(frame.unit)
	if type(unit) ~= "string" or not unit:match("^nameplate") or not frame.healthBar then return end
	local name = DanTools.FullName(unit)
	if name and db.killers[name] and isEnemyPlayer(unit) then
		frame.healthBar:SetStatusBarColor(COLOR.r, COLOR.g, COLOR.b)
	end
end

local function colorAllPlates()
	for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
		if plate.UnitFrame then colorPlate(plate.UnitFrame) end
	end
end

-- Puts a player on the list by hand, or takes them off. Returns whether they're on it now.
function DanTools.GrudgeToggle(name)
	if not tool.db.enabled then return false end
	if db.killers[name] then
		db.killers[name] = nil
	else
		local info = seen[name] or {}
		db.killers[name] = { deaths = {}, confirmed = true, class = info.class, race = info.race, guild = info.guild }
	end
	colorAllPlates()
	refreshWindow()
	return db.killers[name] ~= nil
end

-- Returns killer, spell, confirmed. Hit 1 of the recap is the killing blow. A source seen as an enemy
-- player wins (killing blow first, else whoever hit hardest); otherwise the killing blow, or the hardest
-- hitter, that was never seen as a mob or a same-faction player, unconfirmed.
local function findKiller()
	local events = C_DeathRecap.GetRecapEvents()
	if not events or #events == 0 then return end
	local damage, order = {}, {}
	for _, e in ipairs(events) do
		local who = recapName(e.sourceName)
		if who then
			if not damage[who] then
				damage[who] = 0
				order[#order + 1] = who
			end
			damage[who] = damage[who] + (plain(e.amount) or 0)
		end
	end
	local now = GetTime()
	local me, myFirst = DanTools.FullName("player")
	local function sawEnemy(who) return seen[who] and now - seen[who].time < SEEN_FOR end
	local function maybeEnemy(who) return who ~= me and who ~= myFirst and not npcs[who] and not friends[who] end
	local function hardestHitter(ok)
		local pick
		for _, who in ipairs(order) do
			if ok(who) and (not pick or damage[who] > damage[pick]) then pick = who end
		end
		return pick
	end
	local blow, blowSpell = recapName(events[1].sourceName), plain(events[1].spellName)
	if blow and sawEnemy(blow) then return blow, blowSpell, true end
	local who = hardestHitter(sawEnemy)
	if who then return who, nil, true end
	if blow and maybeEnemy(blow) then return blow, blowSpell, false end
	return hardestHitter(maybeEnemy), nil, false
end

local function record(who, spell, death, confirmed)
	local info = seen[who] or {}
	local entry = db.killers[who] or { deaths = {} }
	entry.confirmed = entry.confirmed or confirmed
	entry.class, entry.race = info.class or entry.class, info.race or entry.race
	entry.guild = info.guild or entry.guild
	death.theirLevel, death.spell = info.level, spell
	table.insert(entry.deaths, death)
	db.killers[who] = entry
	local n = #entry.deaths
	local desc = entry.class and (" (%s %s)"):format(entry.race or "", entry.class:lower()) or ""
	print(("|cffff00ffGrudge:|r %s%s killed you%s. %s%s."):format(who, desc,
		spell and (" with " .. spell) or "", levels(death), n > 1 and (". Kill " .. n) or ""))
	colorAllPlates()
	refreshWindow()
end

local function describe(v)
	if v == nil then return "nil" end
	if issecretvalue and issecretvalue(v) then return "<hidden>" end
	return tostring(v)
end

-- What the game told us about the last death, for /grudge debug (also saved as db.lastDeath).
local function recapReport()
	local report = { hasRecap = describe(C_DeathRecap.HasRecapEvents()), events = {}, seen = {} }
	local ok, events = pcall(C_DeathRecap.GetRecapEvents)
	if not ok then
		report.recapError = tostring(events)
	else
		report.eventCount = events and #events or 0
		for i, e in ipairs(events or {}) do
			if i > 8 then break end
			report.events[i] = ("%s | %s | %s | %s"):format(describe(e.sourceName), describe(e.spellName),
				describe(e.amount), describe(e.event))
		end
	end
	local now = GetTime()
	for name, info in pairs(seen) do
		report.seen[#report.seen + 1] = ("%s (%ds ago)"):format(name, now - info.time)
	end
	return report
end

local function printReport(title, report)
	print("|cffff00ffGrudge:|r " .. title)
	if report.recapError then print("  recap error: " .. report.recapError) end
	print(("  recap has events: %s, count: %s"):format(report.hasRecap, tostring(report.eventCount)))
	for i, line in ipairs(report.events) do print(("  hit %d: %s"):format(i, line)) end
	print("  enemy players seen: " .. (#report.seen > 0 and table.concat(report.seen, ", ") or "none"))
	if report.error then print("  error: " .. report.error) end
end

local function deathHere()
	local zone, subzone = GetRealZoneText(), GetSubZoneText()
	return {
		myLevel = UnitLevel("player"), char = UnitName("player"), time = time(),
		zone = zone, subzone = subzone ~= "" and subzone ~= zone and subzone or nil,
	}
end

local function onDeath(death, retried)
	if not C_DeathRecap.HasRecapEvents() and not retried then
		C_Timer.After(2, function() onDeath(death, true) end)
		return
	end
	local report = recapReport()
	report.when = date("%b %d %H:%M", death.time)
	local ok, who, spell, confirmed = pcall(findKiller)
	if not ok then report.error = tostring(who) end
	db.lastDeath = report
	if ok and who then
		record(who, spell, death, confirmed)
		return
	end
	for _, info in pairs(seen) do
		if GetTime() - info.time < 60 then -- an enemy player was around, so this may have been a gank
			print("|cffff00ffGrudge:|r killer unknown.")
			return
		end
	end
end

local function addTooltip(tooltip)
	if not tool.db.enabled or not tooltip.GetUnit then return end
	local _, unit = tooltip:GetUnit()
	unit = plain(unit)
	if not unit or not isEnemyPlayer(unit) then return end
	local name = DanTools.FullName(unit)
	local entry = name and db.killers[name]
	if not entry then return end
	local deaths, me = entry.deaths, UnitName("player")
	if #deaths == 0 then -- added by hand
		tooltip:AddLine("Grudge", 1, 0, 1)
	else
		tooltip:AddLine(("Killed you %d time%s:"):format(#deaths, #deaths == 1 and "" or "s"), 1, 0, 1)
	end
	for i = #deaths, math.max(1, #deaths - SHOWN_DEATHS + 1), -1 do
		tooltip:AddLine("  " .. deathLine(deaths[i], me), 1, 1, 1)
	end
	tooltip:Show()
end

---------------------------------------------------------------------------------------------------
-- The list window (/grudge, or the button on the tool's settings page)

local function newRow(i)
	local row = CreateFrame("Frame", nil, window.content)
	row:SetWidth(410)
	row.text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.text:SetPoint("TOPLEFT", 4, -6)
	row.text:SetWidth(330)
	row.text:SetJustifyH("LEFT")
	row.text:SetJustifyV("TOP")
	row.text:SetSpacing(2)
	local forget = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	forget:SetSize(64, 20)
	forget:SetPoint("TOPRIGHT", -4, -4)
	forget:SetText("Forget")
	forget:SetScript("OnClick", function()
		db.killers[row.name] = nil
		refreshWindow()
	end)
	local rule = row:CreateTexture(nil, "BACKGROUND")
	rule:SetColorTexture(1, 1, 1, 0.08)
	rule:SetHeight(1)
	rule:SetPoint("BOTTOMLEFT")
	rule:SetPoint("BOTTOMRIGHT")
	window.rows[i] = row
	return row
end

local function lastKill(name)
	local deaths = db.killers[name].deaths
	return deaths[#deaths] and deaths[#deaths].time or 0
end

function refreshWindow()
	if not window or not window:IsShown() then return end
	local names = {}
	for name in pairs(db.killers) do names[#names + 1] = name end
	table.sort(names, function(a, b) return lastKill(a) > lastKill(b) end) -- most recent kill first
	local me, y = UnitName("player"), 0
	for i, name in ipairs(names) do
		local row = window.rows[i] or newRow(i)
		local e = db.killers[name]
		local lines = { ("|cffff66ff%s|r  |cffaaaaaa%s|r  %d kill%s"):format(name,
			e.class and ((e.race or "") .. " " .. e.class:lower()) or "unseen",
			#e.deaths, #e.deaths == 1 and "" or "s") }
		for j = #e.deaths, math.max(1, #e.deaths - SHOWN_DEATHS + 1), -1 do
			lines[#lines + 1] = "    " .. deathLine(e.deaths[j], me)
		end
		row.name = name
		row.text:SetText(table.concat(lines, "\n"))
		row:SetHeight(math.max(row.text:GetStringHeight() + 12, 30))
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", window.content, "TOPLEFT", 0, -y)
		row:Show()
		y = y + row:GetHeight()
	end
	for i = #names + 1, #window.rows do window.rows[i]:Hide() end
	window.content:SetHeight(math.max(y, 10))
	window.empty:SetShown(#names == 0)
end

local function buildWindow()
	window = CreateFrame("Frame", "DanToolsGrudgeList", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	window:Hide()
	window:SetSize(470, 400)
	window:SetPoint("CENTER", 0, 40)
	window:SetFrameStrata("HIGH")
	window:SetToplevel(true)
	window:SetClampedToScreen(true)
	window:EnableMouse(true)
	window:SetMovable(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", window.StopMovingOrSizing)
	DanTools.Skin(window)
	table.insert(UISpecialFrames, "DanToolsGrudgeList") -- Escape closes it

	local title = window:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 14, -12)
	title:SetText("Grudge List")
	local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -2, -2)

	local scroll = DanTools.ScrollFrame(window, "DanToolsGrudgeScroll")
	scroll:SetPoint("TOPLEFT", 12, -38)
	scroll:SetPoint("BOTTOMRIGHT", -32, 12)
	window.content = CreateFrame("Frame", nil, scroll)
	window.content:SetSize(410, 10)
	scroll:SetScrollChild(window.content)
	window.rows = {}
	window.empty = window:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	window.empty:SetPoint("TOP", 0, -70)
	window.empty:SetText("None")
	window:SetScript("OnShow", refreshWindow)
end

local function toggleWindow()
	if not window then buildWindow() end
	window:SetShown(not window:IsShown())
end

tool.buttons = { { text = "Open list", onClick = toggleWindow } }

---------------------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, unit)
	if event == "NAME_PLATE_UNIT_ADDED" then
		unit = plain(unit)
		if not unit then return end
		note(unit)
		local plate = C_NamePlate.GetNamePlateForUnit(unit)
		if plate and plate.UnitFrame then colorPlate(plate.UnitFrame) end
	elseif event == "PLAYER_TARGET_CHANGED" then
		note("target")
	elseif event == "UPDATE_MOUSEOVER_UNIT" then
		note("mouseover")
	elseif event == "PLAYER_DEAD" then
		-- whoever is still standing around you counts as seen; where you died is taken now, before you release
		for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
			local plateUnit = plate.UnitFrame and plain(plate.UnitFrame.unit)
			if plateUnit then note(plateUnit) end
		end
		note("target")
		local death = deathHere()
		C_Timer.After(1, function() onDeath(death) end)
	end
end)

function tool:OnLoad()
	local account = DanTools.account
	account.grudge = account.grudge or { killers = {} }
	db = account.grudge
	DanTools:ImportOld("Grudge", "GrudgeDB", function(old)
		for name, entry in pairs(old.killers or {}) do
			if not db.killers[name] then db.killers[name] = CopyTable(entry) end
		end
		db.lastDeath = db.lastDeath or old.lastDeath
	end)
	if CompactUnitFrame_UpdateHealthColor then
		hooksecurefunc("CompactUnitFrame_UpdateHealthColor", colorPlate)
	end
	if TooltipDataProcessor and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, addTooltip)
	else
		GameTooltip:HookScript("OnTooltipSetUnit", addTooltip)
	end
end

function tool:OnEnable()
	for _, e in ipairs({ "NAME_PLATE_UNIT_ADDED", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "PLAYER_DEAD" }) do
		events:RegisterEvent(e)
	end
	colorAllPlates()
end

function tool:OnDisable()
	events:UnregisterAllEvents()
end

SLASH_GRUDGE1 = "/grudge"
SlashCmdList.GRUDGE = function(msg)
	local cmd = msg:lower():match("^%s*(%S*)")
	if cmd == "debug" then
		if db.lastDeath then printReport("last death (" .. db.lastDeath.when .. "):", db.lastDeath) end
		printReport("recap now (who | spell | damage | type):", recapReport())
	elseif cmd == "add" then -- record your latest death from the Death Recap, placed where you stand now
		local ok, who, spell, confirmed = pcall(findKiller)
		if ok and who then
			record(who, spell, deathHere(), confirmed)
		else
			print("|cffff00ffGrudge:|r no killer in recap.")
		end
	elseif cmd == "forget" then
		local forget = msg:match("^%s*%S+%s+(.-)%s*$")
		for name in pairs(db.killers) do
			if forget and name:lower() == forget:lower() then
				db.killers[name] = nil
				refreshWindow()
				print("|cffff00ffGrudge:|r forgot " .. name .. ".")
				return
			end
		end
		print("|cffff00ffGrudge:|r " .. (forget or "?") .. " not listed.")
	else
		toggleWindow()
	end
end
