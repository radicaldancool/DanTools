-- XP Rate: your XP per minute or per hour since the last reset, and how long until you level at that rate.
-- The count survives /reload and quick relogs; after more than 5 minutes logged out it starts fresh.

local _, DanTools = ...
local plain = DanTools.plain

local RESUME_WITHIN = 5 * 60

local tool = DanTools:AddTool({
	key = "xp",
	name = "XP Rate",
	display = { width = 130, lines = 2, pos = { "CENTER", "CENTER", 0, -260 } },
	options = { { key = "levelTime", label = "Time to level", default = true } },
	bindings = {
		{ key = "toggle", label = "Per min / hour", default = "LeftButton" },
		{ key = "reset", label = "Reset", default = "SHIFT-LeftButton" },
	},
})

local lastXP, lastMax

local function elapsed()
	return math.max(time() - tool.db.start, 1)
end

local function reset()
	tool.db.start, tool.db.gained = time(), 0
end

local function redraw()
	local db = tool.db
	if IsPlayerAtEffectiveMaxLevel and IsPlayerAtEffectiveMaxLevel() then
		DanTools:SetLines(tool, "|cffffd100XP|r max level")
		return
	end
	local perSec = db.gained / elapsed()
	local rate = db.perHour and ("|cffffd100XP/hr|r " .. DanTools.Number(perSec * 3600))
		or ("|cffffd100XP/min|r " .. DanTools.Number(perSec * 60))
	local level = ""
	if db.levelTime and perSec > 0 and lastXP then
		level = "|cffffd100Level in|r ~" .. DanTools.Duration((lastMax - lastXP) / perSec)
	end
	DanTools:SetLines(tool, rate, level)
end

local function onXP()
	local xp, max = plain(UnitXP("player")), plain(UnitXPMax("player"))
	if not xp or not max then return end
	if lastXP then
		if xp >= lastXP then
			tool.db.gained = tool.db.gained + xp - lastXP
		else -- leveled up: the rest of the old level, plus what's into the new one
			tool.db.gained = tool.db.gained + lastMax - lastXP + xp
		end
	end
	lastXP, lastMax = xp, max
	redraw()
end

function tool:OnClick(mouseButton)
	if DanTools:IsBinding(self, "reset", mouseButton) then
		reset()
	elseif DanTools:IsBinding(self, "toggle", mouseButton) then
		self.db.perHour = not self.db.perHour
	end
	redraw()
end

function tool:OnTooltip(tooltip)
	tooltip:AddLine(("%s XP in %s"):format(DanTools.Number(self.db.gained), DanTools.Duration(elapsed())), 1, 1, 1)
	local rested = GetXPExhaustion and plain(GetXPExhaustion())
	if rested and rested > 0 then
		tooltip:AddLine(("Rested: %s XP"):format(DanTools.Number(rested)), 0.3, 0.6, 1)
	end
end

function tool:OnOption()
	if self.db.enabled then redraw() end
end

local tick = 0
tool.frame:SetScript("OnUpdate", function(_, dt) -- the rate drifts down while you aren't earning XP
	tick = tick + dt
	if tick < 1 then return end
	tick = 0
	redraw()
end)
tool.frame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_XP_UPDATE" then
		onXP()
	else -- PLAYER_LOGOUT, also fires on /reload
		tool.db.lastSeen = time()
	end
end)

function tool:OnLoad()
	local db = self.db
	if db.start and (not db.lastSeen or time() - db.lastSeen > RESUME_WITHIN) then db.start = nil end
	self.frame:RegisterEvent("PLAYER_LOGOUT")
end

function tool:OnEnable()
	if not self.db.start then reset() end
	lastXP = nil
	onXP()
	self.frame:RegisterEvent("PLAYER_XP_UPDATE")
end

function tool:OnDisable() -- XP isn't counted while off, so the next start is a fresh count
	self.frame:UnregisterEvent("PLAYER_XP_UPDATE")
	self.db.start = nil
end
