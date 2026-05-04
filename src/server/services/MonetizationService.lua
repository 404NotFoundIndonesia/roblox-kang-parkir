-- MonetizationService handles Developer Products, Gamepass ownership checks,
-- and per-player shift inventory (SpikeStrip, EnergyDrink, BribeMoney).
--
-- Inventory is shift-scoped (not persisted to DataService) — it resets each session.
-- Gamepass ownership is cached on join (one UserOwnsGamePassAsync call per pass per player).
--
-- ProcessReceipt must ALWAYS return PurchaseGranted or NotProcessedYet.
-- On any internal error the handler returns NotProcessedYet so Roblox retries.
--
-- ShopPurchase  (C→S): spend shift currency → add item → fire ShopPurchaseResult.
-- ConsumeItem   (C→S): deduct item → apply effect (EnergyDrink / BribeMoney).
--                      SpikeStrip is consumed inside CombatService via PlaceStrip.

local MarketplaceService = game:GetService("MarketplaceService")
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local Knit      = require(ReplicatedStorage.Shared.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes   = require(ReplicatedStorage.Shared.Remotes)

local MonetizationService = Knit.CreateService({ Name = "MonetizationService" })

type Inventory = { SpikeStrip: number, EnergyDrink: number, BribeMoney: number }
type PassCache = { VIPWhistle: boolean, Landlord: boolean }

local _inventory:   { [number]: Inventory } = {}
local _ownedPasses: { [number]: PassCache } = {}

local VALID_ITEMS: { [string]: boolean } = {
	SpikeStrip  = true,
	EnergyDrink = true,
	BribeMoney  = true,
}

-- ── Inventory helpers ─────────────────────────────────────────────────────────

local function newInventory(): Inventory
	return { SpikeStrip = 0, EnergyDrink = 0, BribeMoney = 0 }
end

function MonetizationService:_AddInventory(player: Player, itemName: string, count: number)
	local inv = _inventory[player.UserId]
	if not inv then return end
	inv[itemName] = (inv[itemName] or 0) + count
end

-- ── Developer Product grants ──────────────────────────────────────────────────

function MonetizationService:_GrantEnergyDrink(player: Player)
	self:_AddInventory(player, "EnergyDrink", 1)
	Remotes.ItemGranted:FireClient(player, "EnergyDrink")
end

function MonetizationService:_GrantBribeMoney(player: Player)
	self:_AddInventory(player, "BribeMoney", 1)
	Remotes.ItemGranted:FireClient(player, "BribeMoney")
end

-- ── ProcessReceipt ────────────────────────────────────────────────────────────

function MonetizationService:_HandleReceipt(receiptInfo: { PlayerId: number, ProductId: number })
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		-- Player has left; Roblox will retry when they rejoin.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Ensure inventory exists (covers edge-case join timing).
	if not _inventory[player.UserId] then
		_inventory[player.UserId] = newInventory()
	end

	local productId = receiptInfo.ProductId
	if productId == Constants.ProductId_EnergyDrink then
		self:_GrantEnergyDrink(player)
	elseif productId == Constants.ProductId_BribeMoney then
		self:_GrantBribeMoney(player)
	else
		warn("[MonetizationService] Unknown ProductId:", productId, "— granting anyway to prevent retry loop")
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- ── Player lifecycle ──────────────────────────────────────────────────────────

function MonetizationService:_OnPlayerAdded(player: Player)
	_inventory[player.UserId]   = newInventory()
	_ownedPasses[player.UserId] = { VIPWhistle = false, Landlord = false }

	-- Gamepass checks are network calls — wrap in pcall, run in background.
	task.spawn(function()
		local okV, ownsVIP = pcall(
			MarketplaceService.UserOwnsGamePassAsync,
			MarketplaceService,
			player.UserId,
			Constants.GamepassId_VIPWhistle
		)
		local cache = _ownedPasses[player.UserId]
		if cache and okV and ownsVIP then
			cache.VIPWhistle = true
		end

		local okL, ownsLandlord = pcall(
			MarketplaceService.UserOwnsGamePassAsync,
			MarketplaceService,
			player.UserId,
			Constants.GamepassId_Landlord
		)
		if cache and okL and ownsLandlord then
			cache.Landlord = true
		end
	end)
end

-- ── Initialisation ────────────────────────────────────────────────────────────

function MonetizationService:KnitStart()
	-- ProcessReceipt is assigned as a function, not connected as a signal.
	-- Wrap the body in pcall so any internal error returns NotProcessedYet (safe retry).
	MarketplaceService.ProcessReceipt = function(receiptInfo)
		local ok, result = pcall(function()
			return self:_HandleReceipt(receiptInfo)
		end)
		if ok then
			return result
		end
		warn("[MonetizationService] ProcessReceipt error:", result)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- Player lifecycle hooks.
	Players.PlayerAdded:Connect(function(player)
		self:_OnPlayerAdded(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		_inventory[player.UserId]   = nil
		_ownedPasses[player.UserId] = nil
	end)

	-- Init any players already in the server at service start.
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:_OnPlayerAdded(player)
		end)
	end

	-- ShopPurchase: spend shift currency to buy an item for inventory.
	Remotes.ShopPurchase:Connect(function(player: Player, itemName: string)
		if not VALID_ITEMS[itemName] then return end

		local price = Constants.ShopPrices[itemName]
		if not price then return end

		local okE, EconomyService = pcall(Knit.GetService, Knit, "EconomyService")
		if not okE or not EconomyService then return end

		if not EconomyService:SpendShiftCurrency(player, price) then
			Remotes.ShopPurchaseResult:FireClient(player, itemName, false, "INSUFFICIENT_FUNDS", nil)
			return
		end

		self:_AddInventory(player, itemName, 1)
		Remotes.ShopPurchaseResult:FireClient(player, itemName, true, nil, self:GetInventory(player))
	end)

	-- ConsumeItem: apply an item's effect. SpikeStrip is consumed via PlaceStrip instead.
	Remotes.ConsumeItem:Connect(function(player: Player, itemName: string)
		if not VALID_ITEMS[itemName] then return end
		if itemName == "SpikeStrip" then return end

		if not self:ConsumeItem(player, itemName) then return end

		if itemName == "EnergyDrink" then
			local ok, StaminaService = pcall(Knit.GetService, Knit, "StaminaService")
			if ok and StaminaService then
				StaminaService:SetFull(player)
			end
		elseif itemName == "BribeMoney" then
			local ok, PoliceService = pcall(Knit.GetService, Knit, "PoliceService")
			if ok and PoliceService then
				PoliceService:ClearTargeting(player)
			end
		end
	end)
end

-- ── Public API ────────────────────────────────────────────────────────────────

function MonetizationService:GetInventory(player: Player): Inventory
	return _inventory[player.UserId] or newInventory()
end

function MonetizationService:AddItem(player: Player, itemName: string, count: number)
	self:_AddInventory(player, itemName, count)
end

-- Deducts 1 of itemName. Returns false if count is 0. Used by CombatService (SpikeStrip).
function MonetizationService:ConsumeItem(player: Player, itemName: string): boolean
	local inv = _inventory[player.UserId]
	if not inv then return false end
	local current = inv[itemName] or 0
	if current <= 0 then return false end
	inv[itemName] = current - 1
	return true
end

-- Returns true if the player owns the named gamepass ("VIPWhistle" or "Landlord").
function MonetizationService:OwnsPass(player: Player, passName: string): boolean
	local cache = _ownedPasses[player.UserId]
	if not cache then return false end
	return cache[passName] == true
end

return MonetizationService
