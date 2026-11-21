-- Quest Sound: plays Sounds\QuestAccept.ogg when you accept a quest. A short cooldown keeps several
-- quests accepted in a burst from talking over each other.

local _, DanTools = ...

local tool = DanTools:AddTool({
	key = "quest",
	name = "Quest Sound",
	options = {
		{ key = "gap", label = "Cooldown (s)", type = "number", default = 3, min = 0, max = 60, step = 1 },
	},
})

local lastPlayed

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function()
	local now = GetTime()
	if lastPlayed and now - lastPlayed < tool.db.gap then return end
	lastPlayed = now
	DanTools.PlayOwnSound("QuestAccept")
end)

function tool:OnEnable()
	frame:RegisterEvent("QUEST_ACCEPTED")
end

function tool:OnDisable()
	frame:UnregisterEvent("QUEST_ACCEPTED")
end
