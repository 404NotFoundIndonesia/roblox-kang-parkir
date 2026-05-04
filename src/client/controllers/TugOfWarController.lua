-- TugOfWarController shows an in-world BillboardGui bar during a Tug-of-War battle.
--
-- TugOfWarStart  → parent TugOfWarGui (BillboardGui) to local HRP; wire inputs.
-- InputBegan     → fire TugOfWarInput to server; cosmetically increment local fill.
-- TugOfWarResult → flash bar green/red; hide after 0.5 s.
--
-- The fill bar animation is cosmetic only — server is authoritative on score.

local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit    = require(ReplicatedStorage.Shared.Knit)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local TugOfWarController = Knit.CreateController({ Name = "TugOfWarController" })

local COLOR_NEUTRAL = Color3.fromRGB(255, 200,  50)
local COLOR_WIN     = Color3.fromRGB( 60, 200,  60)
local COLOR_LOSE    = Color3.fromRGB(200,  60,  60)
local FILL_STEP     = 0.05   -- cosmetic increment per input press

local _activeVehicleId: string?           = nil
local _barGui:          BillboardGui?     = nil
local _fillFrame:       Frame?            = nil
local _localFill:       number            = 0.5
local _inputConn:       RBXScriptConnection? = nil

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function hideBar()
	if _inputConn then
		_inputConn:Disconnect()
		_inputConn = nil
	end
	_activeVehicleId = nil
	_localFill       = 0.5

	local bar = _barGui
	if bar then
		bar.Enabled = false
		-- Return to PlayerGui so it isn't GC'd with the character.
		local playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
		if playerGui then
			bar.Parent = playerGui
		end
	end
end

-- ── KnitStart ─────────────────────────────────────────────────────────────────

function TugOfWarController:KnitStart()
	local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	-- TugOfWarGui may be either a BillboardGui directly, or a container holding one.
	local tugContainer = PlayerGui:WaitForChild("TugOfWarGui", 20)
	if not tugContainer then
		warn("[TugOfWarController] TugOfWarGui not found in PlayerGui")
		return
	end

	-- Support both layouts: container.Bar is a BillboardGui, or container IS one.
	local bar: BillboardGui?
	if tugContainer:IsA("BillboardGui") then
		bar = tugContainer :: BillboardGui
	else
		bar = tugContainer:FindFirstChildWhichIsA("BillboardGui") :: BillboardGui?
	end

	if not bar then
		warn("[TugOfWarController] No BillboardGui found in TugOfWarGui")
		return
	end
	_barGui = bar
	bar.Enabled = false

	-- The fill frame is one level inside; look recursively.
	_fillFrame = bar:FindFirstChild("Fill", true) :: Frame?

	-- ── TugOfWar starts ───────────────────────────────────────────────────────

	Remotes.TugOfWarStart:Connect(function(vehicleId: string)
		if _activeVehicleId then return end
		_activeVehicleId = vehicleId
		_localFill       = 0.5

		local char = Players.LocalPlayer.Character
			or Players.LocalPlayer.CharacterAdded:Wait()
		local hrp  = char:WaitForChild("HumanoidRootPart") :: BasePart

		bar.Parent       = hrp
		bar.StudsOffset  = Vector3.new(0, 3, 0)
		bar.Enabled      = true

		if _fillFrame then
			_fillFrame.BackgroundColor3 = COLOR_NEUTRAL
			_fillFrame.Size = UDim2.new(0.5, 0, 1, 0)
		end

		-- Any key or tap increments local fill and fires input to server.
		_inputConn = UserInputService.InputBegan:Connect(function(_input: InputObject, _processed: boolean)
			if not _activeVehicleId then return end

			Remotes.TugOfWarInput:FireServer(_activeVehicleId)

			_localFill = math.min(_localFill + FILL_STEP, 1)
			if _fillFrame then
				_fillFrame.Size = UDim2.new(_localFill, 0, 1, 0)
			end
		end)
	end)

	-- ── TugOfWar result ───────────────────────────────────────────────────────

	Remotes.TugOfWarResult:Connect(function(vehicleId: string, won: boolean)
		if _activeVehicleId ~= vehicleId then return end

		if _fillFrame then
			_fillFrame.BackgroundColor3 = if won then COLOR_WIN else COLOR_LOSE
			TweenService:Create(_fillFrame,
				TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = UDim2.new(1, 0, 1, 0) }
			):Play()
		end

		task.delay(0.5, hideBar)
	end)
end

return TugOfWarController
