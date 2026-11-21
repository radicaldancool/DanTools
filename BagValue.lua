-- Bag Value: shows each bag item's vendor value (whole stack) on its icon and outlines the cheapest
-- item in your bags in red, as a hint for what to delete when bags are full.
-- An item you mark as kept (Alt+Right-click unless you changed it) gets a green check and is never
-- marked cheapest. Items vendors won't buy (quest items, Hearthstone) show no price and are never marked.
-- The keep list is shared by all your characters.

local _, DanTools = ...

local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local GetContainerItemInfo = C_Container.GetContainerItemInfo
local GetContainerNumSlots = C_Container.GetContainerNumSlots
local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS -- carried bags are 0 (backpack) to LAST_BAG

local tool = DanTools:AddTool({
	key = "bagvalue",
	name = "Bag Value",
	bindings = { { key = "keep", label = "Keep item", default = "ALT-RightButton" } },
})

local keep     -- DanTools.account.bagKeep: itemID -> true
local cheapest -- lowest stack value in carried bags, kept items excluded

local function slotValue(bag, slot)
	local info = GetContainerItemInfo(bag, slot)
	if not info or not info.itemID then return end
	if info.hasNoValue then return nil, info.itemID end
	local price = select(11, GetItemInfo(info.itemID))
	if price == nil then DanTools.bagWaiting = true end
	if not price or price == 0 then return nil, info.itemID end
	return price * (info.stackCount or 1), info.itemID
end

local function scan()
	cheapest = nil
	for bag = 0, LAST_BAG do
		for slot = 1, GetContainerNumSlots(bag) do
			local value, itemID = slotValue(bag, slot)
			if value and not keep[itemID] and (not cheapest or value < cheapest) then
				cheapest = value
			end
		end
	end
end

local function coins(copper) -- the biggest coin only, to fit on an icon
	if copper >= 100000 then return ("|cffffd100%dg|r"):format(math.floor(copper / 10000)) end
	if copper >= 10000 then return ("|cffffd100%.1fg|r"):format(math.floor(copper / 1000) / 10) end
	if copper >= 100 then return ("|cffd0d0d0%ds|r"):format(math.floor(copper / 100)) end
	return ("|cffeda55f%dc|r"):format(copper)
end

local function overlay(button)
	local data = DanTools.ButtonData(button)
	if data.value then return data.value end
	local o = { edges = {} }
	o.price = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	o.price:SetPoint("TOPRIGHT", -1, -2)
	o.price:SetJustifyH("RIGHT")
	for i, points in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" },
	                          { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
		local edge = button:CreateTexture(nil, "OVERLAY", nil, 7)
		edge:SetColorTexture(1, 0.1, 0.1)
		edge:SetPoint(points[1])
		edge:SetPoint(points[2])
		if i <= 2 then edge:SetHeight(2) else edge:SetWidth(2) end
		o.edges[i] = edge
	end
	o.keep = button:CreateTexture(nil, "OVERLAY", nil, 7)
	o.keep:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
	o.keep:SetSize(14, 14)
	o.keep:SetPoint("BOTTOMLEFT", 1, 1)
	data.value = o
	return o
end

local function decorate(button)
	if not tool.db.enabled then
		local o = DanTools.ButtonData(button).value
		if o then
			o.price:SetText("")
			o.keep:Hide()
			for _, edge in ipairs(o.edges) do edge:Hide() end
		end
		return
	end
	local o = overlay(button)
	local bag, slot = DanTools.BagSlot(button)
	local value, itemID = slotValue(bag, slot)
	local kept = itemID and keep[itemID] or false
	o.price:SetText(value and coins(value) or "")
	o.price:SetAlpha(kept and 0.5 or 1)
	o.keep:SetShown(kept)
	local mark = value ~= nil and not kept and value == cheapest and bag >= 0 and bag <= LAST_BAG
	for _, edge in ipairs(o.edges) do edge:SetShown(mark) end
end

DanTools:AddBagDecorator({
	before = function()
		if tool.db.enabled then scan() end
	end,
	button = decorate,
})

DanTools:AddBagClick(function(button, mouseButton)
	if not tool.db.enabled or not DanTools:IsBinding(tool, "keep", mouseButton) then return end
	local info = GetContainerItemInfo(DanTools.BagSlot(button))
	if not info or not info.itemID then return end
	keep[info.itemID] = not keep[info.itemID] or nil
	print((keep[info.itemID] and "Bag Value: kept " or "Bag Value: unkept ") .. (info.hyperlink or info.itemID))
	DanTools:RefreshBags()
end)

function tool:OnLoad()
	local account = DanTools.account
	account.bagKeep = account.bagKeep or {}
	keep = account.bagKeep
	DanTools:ImportOld("BagValue", "BagValueDB", function(old)
		for itemID in pairs(old.keep or {}) do keep[itemID] = true end
	end)
end

function tool:OnEnable()
	DanTools:RefreshBags()
end

function tool:OnDisable()
	DanTools:RefreshBags()
end

tool.buttons = {
	{ text = "Print kept", onClick = function()
		local names = {}
		for itemID in pairs(keep) do
			names[#names + 1] = select(2, GetItemInfo(itemID)) or ("item " .. itemID)
		end
		print("Bag Value kept: " .. (#names > 0 and table.concat(names, ", ") or "none"))
	end },
	{ text = "Clear kept", onClick = function()
		wipe(keep)
		print("Bag Value: cleared.")
		DanTools:RefreshBags()
	end },
}
