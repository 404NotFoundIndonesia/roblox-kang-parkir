-- ShopController opens ShopGui when the player activates the ShopVendor ProximityPrompt.
-- Populates 3 item cards (SpikeStrip, EnergyDrink, BribeMoney) from Constants.ShopPrices.
-- Fires ShopPurchase to server on card click.
-- Listens to ShopPurchaseResult: updates count labels on success, flashes red border on fail.
-- Closes on TriggerEnded or when player walks > 8 studs from the vendor.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit      = require(ReplicatedStorage.Shared.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes   = require(ReplicatedStorage.Shared.Remotes)

local ShopController = Knit.CreateController({ Name = "ShopController" })

local CLOSE_DISTANCE = 8  -- studs
local SHOP_ITEMS     = { "SpikeStrip", "EnergyDrink", "BribeMoney" }

local _shopGui:    ScreenGui?
local _vendorPos:  Vector3?
local _distConn:   RBXScriptConnection?

local _countLabels: { [string]: TextLabel } = {}
local _cardFrames:  { [string]: Frame }     = {}

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function flashBorderRed(card: Frame)
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if not stroke then return end
	local original = stroke.Color
	stroke.Color = Color3.fromRGB(200, 60, 60)
	task.delay(0.5, function()
		stroke.Color = original
	end)
end

local function closeShop()
	if _distConn then
		_distConn:Disconnect()
		_distConn = nil
	end
	if _shopGui then
		_shopGui.Enabled = false
	end
end

local function openShop()
	if not _shopGui then return end
	_shopGui.Enabled = true

	-- Start distance watcher to auto-close when player walks away.
	if _distConn then _distConn:Disconnect() end
	_distConn = RunService.Heartbeat:Connect(function()
		local char = Players.LocalPlayer.Character
		local hrp  = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp and _vendorPos then
			if (hrp.Position - _vendorPos).Magnitude > CLOSE_DISTANCE then
				closeShop()
			end
		end
	end)
end

-- ── KnitStart ─────────────────────────────────────────────────────────────────

function ShopController:KnitStart()
	local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local shopGui   = PlayerGui:WaitForChild("ShopGui", 20) :: ScreenGui?
	if not shopGui then
		warn("[ShopController] ShopGui not found in PlayerGui")
		return
	end
	_shopGui = shopGui
	shopGui.Enabled = false

	-- Wire item cards. Expected structure: ShopGui.ItemList.<ItemName>
	local itemList = shopGui:FindFirstChild("ItemList")
	if itemList then
		for _, itemName in ipairs(SHOP_ITEMS) do
			local card = itemList:FindFirstChild(itemName) :: Frame?
			if not card then continue end
			_cardFrames[itemName] = card

			-- Populate price label.
			local priceLabel = card:FindFirstChild("PriceLabel") :: TextLabel?
			if priceLabel then
				local price = Constants.ShopPrices[itemName]
				priceLabel.Text = price and (tostring(price) .. " koin") or "?"
			end

			-- Count label shows current inventory count.
			local countLabel = card:FindFirstChild("CountLabel") :: TextLabel?
			if countLabel then
				_countLabels[itemName] = countLabel
				countLabel.Text = "x0"
			end

			-- Buy button fires ShopPurchase to server.
			local buyBtn = card:FindFirstChild("BuyButton") :: GuiButton?
			if buyBtn then
				buyBtn.Activated:Connect(function()
					Remotes.ShopPurchase:FireServer(itemName)
				end)
			end
		end
	end

	-- ShopPurchaseResult (S→C): update count or flash red.
	Remotes.ShopPurchaseResult:Connect(function(
		itemName:     string,
		success:      boolean,
		_reason:      string?,
		newInventory: { [string]: number }?
	)
		if success then
			if newInventory then
				for name, count in pairs(newInventory) do
					local lbl = _countLabels[name]
					if lbl then
						lbl.Text = "x" .. tostring(count)
					end
				end
			end
		else
			local card = _cardFrames[itemName]
			if card then
				flashBorderRed(card)
			end
		end
	end)

	-- Find ShopVendor and wire ProximityPrompt.
	task.spawn(function()
		local vendor = workspace:WaitForChild("ShopVendor", 30)
		if not vendor then
			warn("[ShopController] ShopVendor not found in workspace")
			return
		end

		local part = vendor:IsA("BasePart") and vendor
			or vendor:FindFirstChildOfClass("BasePart")
		if part then
			_vendorPos = (part :: BasePart).Position
		end

		local prompt = vendor:FindFirstChildOfClass("ProximityPrompt")
			or vendor:FindFirstChildWhichIsA("ProximityPrompt", true)
		if not prompt then
			warn("[ShopController] ProximityPrompt not found on ShopVendor")
			return
		end

		prompt.Triggered:Connect(openShop)
		prompt.TriggerEnded:Connect(closeShop)
	end)
end

return ShopController
