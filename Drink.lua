-- Drink Timer: while you eat or drink, how full your mana and health are and how long until you can
-- stand up: the time until full (worked out from how fast it's rising) or until the food or drink
-- ends, whichever comes first. Shown as bars with the label on or beside them and the time on them,
-- or as text ("Drinking: 12s").
-- Where Forever hides a value from addons the bar still fills (the game draws it), and the time is
-- just what's left of the food or drink.
-- With "Sound" on, Sounds\Drink.ogg plays when you start drinking, if that file is there.

local _, DanTools = ...
local plain = DanTools.plain

local MANA = DanTools.MANA
local MEASURE_FOR = 2 -- seconds of rising before an estimate is shown
local DRINK = { ["Drink"] = true, ["Refreshment"] = true, ["Food & Drink"] = true }
local FOOD = { ["Food"] = true, ["Refreshment"] = true, ["Food & Drink"] = true }

local tool = DanTools:AddTool({
	key = "drink",
	name = "Drink Timer",
	display = { width = 110, lines = 2, pos = { "CENTER", "CENTER", 0, -360 }, hideIdle = true },
	options = {
		{ key = "label", label = "Label", default = true },
		{ key = "timer", label = "Timer", default = true },
		{ key = "bar", label = "Bar", default = true },
		{ key = "sound", label = "Sound", default = true },
		{ key = "labelAt", label = "Label position", type = "choice", choices = DanTools.LABEL_PLACES, default = "In bar" },
		{ key = "barWidth", label = "Bar width", type = "number", default = 130, min = 40, max = 400, step = 10 },
		{ key = "barHeight", label = "Bar height", type = "number", default = 12, min = 4, max = 40, step = 2 },
		{ key = "manaColor", label = "Mana color", type = "color", default = { 0.3, 0.5, 1, 1 } },
		{ key = "healthColor", label = "Health color", type = "color", default = { 0.25, 0.9, 0.25, 1 } },
	},
})

local manaBar, healthBar = DanTools:NewBar(tool), DanTools:NewBar(tool)
tool.stack = { tool.lines[1], manaBar, tool.lines[2], healthBar } -- the text lines are only used when the bars are off

local mana, health = {}, {} -- { since, from }: when this rise started and the value it started at
local drinking = false

-- When your Drink and Food buffs end (0 if that's hidden), or nil for one you don't have.
local function buffs()
	-- Forever hides auras from addons at times (PvP combat for one) and throws an error if asked
	-- then. You can't eat or drink in a fight anyway.
	if C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() then return end
	local drink, food
	for i = 1, 40 do
		local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
		if not ok or not aura then break end
		local name = plain(aura.name)
		if name and (DRINK[name] or FOOD[name]) then
			local ends = plain(aura.expirationTime) or 0
			if DRINK[name] then drink = ends end
			if FOOD[name] then food = ends end
		end
	end
	return drink, food
end

-- Seconds until full: a number, 0 when full, false while still measuring, nil if the value is hidden.
local function untilFull(track, value, max, now)
	if not value or not max then return nil end
	if value >= max then return 0 end
	if not track.since or value < track.from then track.since, track.from = now, value end
	local took = now - track.since
	if took < MEASURE_FOR or value <= track.from then return false end
	return (max - value) / ((value - track.from) / took)
end

-- "12s": until full or until the food or drink ends, whichever is first. "full" once it is, and
-- "..." while there's nothing to go on yet.
local function status(eta, ends, now)
	if eta == 0 then return "|cff40ff40full|r" end
	local left = ends > 0 and math.max(0, ends - now) or nil
	local time = eta and left and math.min(eta, left) or eta or left
	return time and ("%ds"):format(math.ceil(time)) or "..."
end

-- One of mana or health: sets up its bar and returns its text line. value and max go to the bar as
-- the game gave them, hidden or not; the time is only worked out from readable ones.
local function resource(bar, ends, label, track, value, max, color, now)
	local db = tool.db
	if not ends then
		DanTools:ShowBar(tool, bar, false)
		return ""
	end
	local text = status(untilFull(track, plain(value), plain(max), now), ends, now)
	if not db.bar then
		-- with no bar the time is all there is, so it shows even with "Timer" off
		DanTools:ShowBar(tool, bar, false)
		return db.label and ("|cffffd100%s:|r %s"):format(label, text) or text
	end
	pcall(bar.SetMinMaxValues, bar, 0, max)
	pcall(bar.SetValue, bar, value)
	bar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
	DanTools:SetBarText(tool, bar, db.label and ("|cffffd100" .. label .. "|r") or "", db.timer and text or "",
		db.labelAt)
	DanTools:ShowBar(tool, bar, true, db.barWidth, db.barHeight)
	return ""
end

local function update()
	local db = tool.db
	local drink, food = buffs()
	local now = GetTime()
	if drink and not drinking and db.sound then DanTools.PlayOwnSound("Drink") end
	drinking = drink ~= nil
	if not drink then wipe(mana) end
	if not food then wipe(health) end
	local first = resource(manaBar, drink, "Drinking", mana, UnitPower("player", MANA), UnitPowerMax("player", MANA),
		db.manaColor, now)
	local second = resource(healthBar, food, "Eating", health, UnitHealth("player"), UnitHealthMax("player"),
		db.healthColor, now)
	local idle = not drink and not food
	if idle then first = "|cffffd100Drinking:|r --" end
	DanTools:SetLines(tool, first, second)
	DanTools:SetIdle(tool, idle)
end

local tick = 0
tool.frame:SetScript("OnUpdate", function(_, dt)
	tick = tick + dt
	if tick < 0.25 then return end
	tick = 0
	update()
end)

function tool:OnOption()
	if self.db.enabled then update() end
end

function tool:OnEnable()
	update()
end
