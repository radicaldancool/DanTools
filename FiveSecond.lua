-- Five-Second Rule: counts down the 5 seconds after you spend mana, while Spirit mana regen is paused.
-- Shown as a bar with the label on or beside it and the number on it, or as text ("FSR 3.4"); the
-- label, the number and the bar are each optional.

local _, DanTools = ...

local RULE = 5

local tool = DanTools:AddTool({
	key = "fsr",
	name = "Five-Second Rule",
	display = { width = 70, lines = 1, pos = { "CENTER", "CENTER", 0, -330 }, hideIdle = true },
	options = {
		{ type = "header", label = "Show" },
		{ key = "label", label = "Label", default = true },
		{ key = "timer", label = "Timer", default = true },
		{ key = "bar", label = "Bar", default = true },
		{ type = "header", label = "Bar" },
		{ key = "labelAt", label = "Label position", type = "choice", choices = DanTools.LABEL_PLACES, default = "In bar",
			needs = "bar" },
		{ key = "fill", label = "Fill up", default = false, needs = "bar" },
		{ key = "barWidth", label = "Width", type = "number", default = 110, min = 40, max = 400, step = 10, needs = "bar" },
		{ key = "barHeight", label = "Height", type = "number", default = 12, min = 4, max = 40, step = 2, needs = "bar" },
		{ key = "barColor", label = "Color", type = "color", default = { 0.3, 0.6, 1, 1 }, needs = "bar" },
		{ key = "regenColor", label = "Regen color", type = "color", default = { 0.25, 1, 0.25, 1 }, needs = "bar" }, -- once regen is back
	},
})

local bar = DanTools:NewBar(tool)
bar:SetMinMaxValues(0, RULE)
tool.stack = { tool.lines[1], bar } -- the text line is only used when the bar is off

local endsAt

local function redraw()
	local db = tool.db
	local left = endsAt and endsAt - GetTime()
	local active = left ~= nil and left > 0
	if not active then endsAt = nil end
	local label = db.label and "|cffffd100FSR|r" or ""
	local number = active and ("%.1f"):format(left) or "|cff40ff40regen|r"
	if db.bar then
		DanTools:SetLines(tool, "")
		DanTools:SetBarText(tool, bar, label, db.timer and active and number or "", db.labelAt)
		bar:SetValue(active and (db.fill and RULE - left or left) or RULE)
		local color = active and db.barColor or db.regenColor
		bar:SetStatusBarColor(color[1], color[2], color[3], color[4] or 1)
	else
		-- with no bar the number is all there is, so it shows even with "Timer" off
		DanTools:SetLines(tool, label == "" and number or (label .. " " .. number))
	end
	DanTools:ShowBar(tool, bar, db.bar, db.barWidth, db.barHeight)
	DanTools:SetIdle(tool, not active)
end

DanTools:OnManaSpent(function()
	if not tool.db.enabled then return end
	endsAt = GetTime() + RULE
	redraw()
end)

local tick = 0
tool.frame:SetScript("OnUpdate", function(_, dt)
	tick = tick + dt
	if tick < 0.03 then return end
	tick = 0
	if endsAt then redraw() end
end)

function tool:OnOption()
	if self.db.enabled then redraw() end
end

function tool:OnEnable()
	redraw()
end

function tool:OnDisable()
	endsAt = nil
end
