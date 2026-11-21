-- Gold Rate: money earned since the last reset, as gold per hour. Spending isn't subtracted from the
-- rate (a repair bill shouldn't sink a farming run); the tooltip shows earned, spent and net.
-- Like XP Rate, the count survives /reload and quick relogs.

local _, DanTools = ...

local RESUME_WITHIN = 5 * 60

local tool = DanTools:AddTool({
	key = "gold",
	name = "Gold Rate",
	display = { width = 140, lines = 1, pos = { "CENTER", "CENTER", 0, -300 } },
	bindings = {
		{ key = "toggle", label = "Per hour / total", default = "LeftButton" },
		{ key = "reset", label = "Reset", default = "SHIFT-LeftButton" },
	},
})

local lastMoney

local function elapsed()
	return math.max(time() - tool.db.start, 1)
end

local function reset()
	local db = tool.db
	db.start, db.earned, db.spent = time(), 0, 0
end

local function redraw()
	local db = tool.db
	if db.total then
		DanTools:SetLines(tool, "|cffffd100Earned|r " .. DanTools.Money(db.earned))
	else
		DanTools:SetLines(tool, "|cffffd100Gold/hr|r " .. DanTools.Money(db.earned / elapsed() * 3600))
	end
end

local function onMoney()
	local money = GetMoney()
	if lastMoney then
		local change = money - lastMoney
		if change > 0 then
			tool.db.earned = tool.db.earned + change
		else
			tool.db.spent = tool.db.spent - change
		end
	end
	lastMoney = money
	redraw()
end

function tool:OnClick(mouseButton)
	if DanTools:IsBinding(self, "reset", mouseButton) then
		reset()
	elseif DanTools:IsBinding(self, "toggle", mouseButton) then
		self.db.total = not self.db.total
	end
	redraw()
end

function tool:OnTooltip(tooltip)
	local db = self.db
	tooltip:AddLine(DanTools.Duration(elapsed()), 1, 1, 1)
	tooltip:AddDoubleLine("Earned", DanTools.Money(db.earned), 1, 1, 1, 1, 1, 1)
	tooltip:AddDoubleLine("Spent", DanTools.Money(db.spent), 1, 1, 1, 1, 1, 1)
	tooltip:AddDoubleLine("Net", DanTools.Money(db.earned - db.spent), 1, 1, 1, 1, 1, 1)
end

local tick = 0
tool.frame:SetScript("OnUpdate", function(_, dt) -- the rate drifts down while you aren't earning
	tick = tick + dt
	if tick < 1 then return end
	tick = 0
	redraw()
end)
tool.frame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_MONEY" then
		onMoney()
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
	lastMoney = nil
	onMoney()
	self.frame:RegisterEvent("PLAYER_MONEY")
end

function tool:OnDisable() -- money isn't counted while off, so the next start is a fresh count
	self.frame:UnregisterEvent("PLAYER_MONEY")
	self.db.start = nil
end
