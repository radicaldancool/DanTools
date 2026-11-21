-- Item Level: shows the item level on weapons and armor, in the item's quality color, on bag icons
-- and on the equipment slots of your character screen.

local _, DanTools = ...

local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local GetItemInfoInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
local GetDetailedItemLevelInfo = C_Item and C_Item.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo
local GetItemQualityColor = C_Item and C_Item.GetItemQualityColor or GetItemQualityColor

-- equip locations that aren't gear with a meaningful level
local SKIP = {
	[""] = true, INVTYPE_NON_EQUIP_IGNORE = true, INVTYPE_BODY = true, INVTYPE_TABARD = true,
	INVTYPE_BAG = true, INVTYPE_QUIVER = true, INVTYPE_AMMO = true,
}
local SLOTS = {
	"Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands", "Waist", "Legs", "Feet",
	"Finger0", "Finger1", "Trinket0", "Trinket1", "MainHand", "SecondaryHand", "Ranged",
}

local tool = DanTools:AddTool({
	key = "ilvl",
	name = "Item Level",
})

local function itemLevel(link)
	if not link then return end
	local _, _, _, equipLoc = GetItemInfoInstant(link)
	if not equipLoc or SKIP[equipLoc] then return end
	local level = GetDetailedItemLevelInfo and GetDetailedItemLevelInfo(link)
	if not level then
		level = select(4, GetItemInfo(link))
		if not level then DanTools.bagWaiting = true end
	end
	return level
end

local function show(button, link, quality)
	local data = DanTools.ButtonData(button)
	local level = tool.db.enabled and itemLevel(link)
	if not level then
		if data.ilvl then data.ilvl:SetText("") end
		return
	end
	if not data.ilvl then
		data.ilvl = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
		data.ilvl:SetPoint("BOTTOMRIGHT", -2, 2)
	end
	local r, g, b = 1, 1, 1
	if quality and GetItemQualityColor then r, g, b = GetItemQualityColor(quality) end
	data.ilvl:SetText(level)
	data.ilvl:SetTextColor(r, g, b)
end

DanTools:AddBagDecorator({ button = function(button)
	local info = C_Container.GetContainerItemInfo(DanTools.BagSlot(button))
	show(button, info and info.hyperlink, info and info.quality)
end })

local function updateSlot(button)
	local slot = button:GetID()
	show(button, GetInventoryItemLink("player", slot), GetInventoryItemQuality("player", slot))
end

local function updateAllSlots()
	for _, name in ipairs(SLOTS) do
		local button = _G["Character" .. name .. "Slot"]
		if button then updateSlot(button) end
	end
end

function tool:OnLoad()
	if PaperDollItemSlotButton_Update then -- the game calls this whenever an equipment slot redraws
		hooksecurefunc("PaperDollItemSlotButton_Update", updateSlot)
	end
end

function tool:OnEnable()
	DanTools:RefreshBags()
	updateAllSlots()
end

function tool:OnDisable()
	DanTools:RefreshBags()
	updateAllSlots()
end
