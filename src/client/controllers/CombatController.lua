-- CombatController wires up client-side PvP input.
--
-- Q key / DashBtn  → fire DashRequest (direction = HRP.LookVector)
-- E key / StrikeBtn → fire StrikeRequest
--   E is contextual: DragController takes priority when near a vehicle or dragging.
--
-- Stamina is deducted locally on dash input for immediate visual feedback;
-- the server is authoritative and will correct via StaminaUpdated.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")

local Knit    = require(ReplicatedStorage.Shared.Knit)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Constants = require(ReplicatedStorage.Shared.Constants)

local CombatController = Knit.CreateController({ Name = "CombatController" })

local LocalPlayer = Players.LocalPlayer

-- Local stamina mirror — updated by StaminaUpdated, used for visual deduction only.
local _localStamina = Constants.StaminaMax

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function getHRP(): BasePart?
	local char = LocalPlayer.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- Returns true when DragController is actively handling an interaction,
-- so E key should NOT fire strike.
local function dragHasEKey(): boolean
	local ok, DragCtrl = pcall(Knit.GetController, Knit, "DragController")
	if not ok or not DragCtrl then return false end
	return DragCtrl:IsNearVehicle() or DragCtrl:IsDragging()
end

-- ── Actions ───────────────────────────────────────────────────────────────────

local function fireDash()
	local hrp = getHRP()
	if not hrp then return end
	Remotes.DashRequest:FireServer(hrp.CFrame.LookVector)

	-- Local visual deduction (server corrects if stamina was insufficient).
	_localStamina = math.max(0, _localStamina - Constants.DashStaminaCost)
	-- StaminaUpdated from server will sync the bar shortly after.
end

local function fireStrike()
	if dragHasEKey() then return end
	Remotes.StrikeRequest:FireServer()
end

-- ── Initialisation ────────────────────────────────────────────────────────────

function CombatController:KnitStart()
	-- Keyboard bindings.
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.Q then
			fireDash()
		elseif input.KeyCode == Enum.KeyCode.E then
			fireStrike()
		end
	end)

	-- Mobile button bindings.
	task.spawn(function()
		self:_TryWireMobileButtons()
	end)

	-- Keep local stamina mirror in sync.
	Remotes.StaminaUpdated:Connect(function(current: number, _max: number)
		_localStamina = current
	end)
end

function CombatController:_TryWireMobileButtons()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
	if not playerGui then return end

	local hud = playerGui:FindFirstChild("HUD")
	if not hud then
		task.delay(5, function()
			self:_TryWireMobileButtons()
		end)
		return
	end

	local dashBtn   = hud:FindFirstChild("DashBtn", true)
	local strikeBtn = hud:FindFirstChild("StrikeBtn", true)

	if dashBtn and dashBtn:IsA("GuiButton") then
		;(dashBtn :: GuiButton).MouseButton1Down:Connect(fireDash)
	end

	if strikeBtn and strikeBtn:IsA("GuiButton") then
		;(strikeBtn :: GuiButton).MouseButton1Down:Connect(fireStrike)
	end
end

return CombatController
