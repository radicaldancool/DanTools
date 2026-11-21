-- Speed: your current movement speed as a percent of normal run speed.
-- Forever can hide your speed from addons (likely in combat); then the last readable value stays, dimmed.

local _, DanTools = ...

local BASE = BASE_MOVEMENT_SPEED or 7

local tool = DanTools:AddTool({
	key = "speed",
	name = "Speed",
	display = { width = 90, lines = 1, pos = { "CENTER", "CENTER", 0, -180 } },
})

local elapsed = 0
tool.frame:SetScript("OnUpdate", function(_, dt)
	elapsed = elapsed + dt
	if elapsed < 0.1 then return end
	elapsed = 0
	local speed = GetUnitSpeed("player")
	if issecretvalue and issecretvalue(speed) then
		tool.lines[1]:SetAlpha(0.5)
		return
	end
	tool.lines[1]:SetAlpha(1)
	DanTools:SetLines(tool, ("|cffffd100Speed|r %d%%"):format(math.floor(speed / BASE * 100 + 0.5)))
end)

function tool:OnEnable()
	DanTools:SetLines(self, "|cffffd100Speed|r --")
end
