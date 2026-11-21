-- Time to Kill: how long you've been fighting your target, a guess at how long until it dies, and
-- the mana the kill cost you.
-- Forever hides health from addons, so the guess comes from how long the same mob took you to kill
-- the last few times (per character), not from its health bar. Before a pull it shows the averages.
-- After a kill it shows mana efficiency: the mob's full health per mana spent (which assumes you did
-- all the damage, and needs the mob's maximum health to be readable), and how that kill's mana
-- compares with your earlier kills of the same mob.
--
-- A kill is seen as your target being dead, but the target is often gone the moment it dies. So the
-- fight stays on screen for a moment after you lose the target, and still counts as a kill if the
-- game reports the kill (PARTY_KILL, or the XP message) or you drop out of combat in that time.

local _, DanTools = ...
local plain = DanTools.plain

local KEEP = 3          -- kills remembered per mob name
local SHOW_KILL_FOR = 6 -- seconds the kill summary stays up
local PRE_PULL = 4      -- mana spent on your target this long before the fight starts counts (the opening cast)
local STICKY = 3        -- seconds a fight stays up, and can still become a kill, after you lose its target

local tool = DanTools:AddTool({
	key = "ttk",
	name = "Time to Kill",
	display = { width = 120, lines = 3, pos = { "CENTER", "CENTER", 0, -220 }, hideIdle = false },
	options = { { key = "showMana", label = "Mana", default = true } },
})

-- target GUID -> this combat's fight with it: { start, spent, health, name, isMob, tapDenied }
-- (spent is the mana so far, or false once an amount was hidden; health is its maximum, once readable)
local fights = {}
local fighting -- GUID of the fight on screen: your target's, or the one whose target you just lost
local lost     -- { guid, at }: the fight whose target you just lost
local prePull  -- { guid, { time, amount }, ... }: mana spent on your target before its fight began
local killed   -- { at, took, mana, perMana, vsPast }: the last kill, for the summary
local targetSerial = 0 -- bumped on every target change; stands in for the GUID where Forever hides it (instances)

local function clock(sec)
	sec = math.floor(sec + 0.5)
	if sec < 60 then return sec .. "s" end
	return ("%d:%02d"):format(math.floor(sec / 60), sec % 60)
end

local function average(values)
	local sum = 0
	for _, v in ipairs(values) do sum = sum + v end
	return sum / #values
end

local function remember(lists, name, value)
	local list = lists[name] or {}
	table.insert(list, value)
	if #list > KEEP then table.remove(list, 1) end
	lists[name] = list
end

local function targetKey()
	if not plain(UnitExists("target")) then return end
	return plain(UnitGUID("target")) or ("target" .. targetSerial)
end

-- "Mana 235", "Mana ?" when the amount was hidden, or "" when there's nothing to show
local function manaText(label, amount)
	if amount == false then return ("|cffffd100%s|r ?"):format(label) end
	if not amount then return "" end
	return ("|cffffd100%s|r %s"):format(label, DanTools.Number(amount))
end

-- "Dmg/mana 4.6 +12%", or "Efficiency +12%" without the mob's health, or "" with neither
local function efficiencyText(perMana, vsPast)
	if not perMana and not vsPast then return "" end
	local text = perMana and ("|cffffd100Dmg/mana|r %.1f"):format(perMana) or "|cffffd100Efficiency|r"
	if vsPast then
		text = ("%s |cff%s%+d%%|r"):format(text, vsPast >= 0 and "40ff40" or "ff4040", math.floor(vsPast * 100 + 0.5))
	end
	return text
end

-- Ends the fight with guid as a kill that happened at `when`.
local function finishKill(guid, when)
	local fight = fights[guid]
	if not fight then return end
	fights[guid] = nil
	if lost and lost.guid == guid then lost = nil end
	local took, mana = when - fight.start, fight.spent
	local name = fight.isMob and fight.name
	killed = { at = GetTime(), took = took, mana = mana }
	if mana and mana > 0 then
		if fight.health and fight.health > 0 then killed.perMana = fight.health / mana end
		local past = name and tool.db.mana[name]
		if past and #past > 0 then killed.vsPast = average(past) / mana - 1 end
	end
	if name and not fight.tapDenied then
		remember(tool.db.kills, name, took)
		if mana then remember(tool.db.mana, name, mana) end
	end
end

DanTools:OnManaSpent(function(amount)
	if not tool.db.enabled then return end
	local fight = fighting and fights[fighting]
	if fight then
		if fight.spent ~= false then fight.spent = amount and fight.spent + amount or false end
		return
	end
	local guid = targetKey()
	if not guid or UnitIsDead("target") or not UnitCanAttack("player", "target") then return end
	local now = GetTime()
	if not prePull or prePull.guid ~= guid then prePull = { guid = guid } end
	while prePull[1] and now - prePull[1].time > PRE_PULL do table.remove(prePull, 1) end
	prePull[#prePull + 1] = { time = now, amount = amount or false }
end)

local function update()
	local kills, manas = tool.db.kills, tool.db.mana
	local now = GetTime()
	local guid = targetKey()
	local name, isMob, dead
	if guid then
		name = plain(UnitName("target"))
		isMob = not plain(UnitIsPlayer("target"))
		dead = UnitIsDead("target")
	end
	-- no mana lines for a character without mana (an unreadable maximum doesn't count as none)
	local showMana = tool.db.showMana and plain(UnitPowerMax("player", DanTools.MANA)) ~= 0

	local fight = guid and fights[guid]
	if guid and not dead and not fight and UnitCanAttack("player", "target")
		and UnitAffectingCombat("player") and UnitAffectingCombat("target") then
		fight = { start = now, spent = 0 }
		for _, spend in ipairs(prePull and prePull.guid == guid and prePull or {}) do
			if now - spend.time <= PRE_PULL and fight.spent ~= false then
				fight.spent = spend.amount and fight.spent + spend.amount or false
			end
		end
		prePull = nil
		fights[guid] = fight
	end
	if fight then
		if lost and lost.guid == guid then lost = nil end -- you have its target again
		fight.name, fight.isMob = fight.name or name, isMob
		fight.health = fight.health or plain(UnitHealthMax("target"))
		fight.tapDenied = UnitIsTapDenied and UnitIsTapDenied("target") or false
		if dead then finishKill(guid, now) end
	end
	if lost and (now - lost.at > STICKY or not fights[lost.guid]) then lost = nil end
	fighting = guid and fights[guid] and guid or not guid and lost and lost.guid or nil
	fight = fighting and fights[fighting]

	local idle = false
	if fight then
		local elapsed = now - fight.start
		local known = fight.isMob and fight.name
		local list = known and kills[known]
		local dies
		if list and #list > 0 then
			local left = average(list) - elapsed
			dies = left > 0 and ("~" .. clock(left)) or "any moment"
		else
			dies = "|cff999999" .. (known and "first kill" or "--") .. "|r"
		end
		DanTools:SetLines(tool, "|cffffd100Fight|r " .. clock(elapsed), "|cffffd100Dies in|r " .. dies,
			showMana and fight.spent ~= 0 and manaText("Mana", fight.spent) or "")
	elseif killed and now - killed.at < SHOW_KILL_FOR then
		DanTools:SetLines(tool, "|cffffd100Killed in|r " .. clock(killed.took),
			showMana and manaText("Mana", killed.mana) or "",
			showMana and efficiencyText(killed.perMana, killed.vsPast) or "")
	elseif name and isMob and not dead and kills[name] and UnitCanAttack("player", "target") then
		local list, manaList = kills[name], manas[name]
		DanTools:SetLines(tool, "|cffffd100Avg kill|r ~" .. clock(average(list)),
			showMana and manaList and #manaList > 0 and manaText("Avg mana", average(manaList)) or "",
			("|cff999999last %d kill%s|r"):format(#list, #list == 1 and "" or "s"))
	else
		DanTools:SetLines(tool, "|cffffd100Fight|r --")
		idle = true
	end
	DanTools:SetIdle(tool, idle)
end

local tick = 0
tool.frame:SetScript("OnUpdate", function(_, dt)
	tick = tick + dt
	if tick < 0.1 then return end
	tick = 0
	update()
end)
tool.frame:SetScript("OnEvent", function(_, event, arg1, arg2)
	if event == "PLAYER_TARGET_CHANGED" then
		if fighting and fights[fighting] and not targetKey() then lost = { guid = fighting, at = GetTime() } end
		targetSerial = targetSerial + 1
	elseif event == "PARTY_KILL" then -- attacker GUID and victim GUID; only a victim can match a fight
		local one, other = plain(arg1), plain(arg2)
		if one then finishKill(one, GetTime()) end
		if other then finishKill(other, GetTime()) end
		if not one and not other and lost then -- GUIDs are hidden (instances): count it for the target you just lost
			finishKill(lost.guid, lost.at)
		end
	elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then -- "Plains Creeper dies, you gain 120 experience."
		local text = plain(arg1)
		local who = text and text:match("^(.-) dies, you gain")
		for guid, fight in pairs(who and fights or {}) do
			if fight.name == who then
				finishKill(guid, lost and lost.guid == guid and lost.at or GetTime())
				break
			end
		end
	else -- combat ended: a target you just lost counts as killed; then forget this combat's fights
		if lost then finishKill(lost.guid, lost.at) end
		update()
		wipe(fights)
		fighting, lost = nil, nil
	end
end)

function tool:OnLoad()
	self.db.kills = self.db.kills or {}
	self.db.mana = self.db.mana or {}
end

function tool:OnEnable()
	self.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
	self.frame:RegisterEvent("PLAYER_TARGET_CHANGED")
	self.frame:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
	pcall(self.frame.RegisterEvent, self.frame, "PARTY_KILL") -- not in every client
	update()
end

function tool:OnDisable()
	self.frame:UnregisterAllEvents()
	wipe(fights)
	fighting, lost, prePull = nil, nil, nil
end

tool.buttons = { { text = "Forget kills", onClick = function()
	wipe(tool.db.kills)
	wipe(tool.db.mana)
	print("DanTools: kills forgotten.")
end } }
