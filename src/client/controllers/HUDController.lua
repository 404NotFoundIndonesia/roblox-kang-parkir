-- HUDController owns the Shift Tracker, stamina bar, and floating payout/penalty labels.
-- Listens to:
--   SessionPhaseChanged  → update time label
--   PayoutReceived       → update unbanked total, show "+N" floating label
--   PenaltyApplied       → update unbanked total, show "-N" floating label (red)
--   StaminaUpdated       → update stamina bar width and color

local TweenService      = game:GetService("TweenService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit      = require(ReplicatedStorage.Shared.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes   = require(ReplicatedStorage.Shared.Remotes)

local HUDController = Knit.CreateController({ Name = "HUDController" })

local _maxStamina: number = Constants.StaminaMax

local _timeLabel:     TextLabel?
local _unbankedLabel: TextLabel?
local _bankedLabel:   TextLabel?
local _staminaFill:   Frame?
local _hudGui:        ScreenGui?

local STAMINA_GREEN  = Color3.fromRGB(85, 200,  85)
local STAMINA_YELLOW = Color3.fromRGB(230, 190,  50)
local STAMINA_RED    = Color3.fromRGB(200,  60,  60)

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function formatTime(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("%02d:%02d", math.floor(s / 60), s % 60)
end

-- Spawns a TextLabel that floats upward and fades out over 1.5 s.
local function showFloatingDelta(parent: Instance, text: string, color: Color3)
	local label      = Instance.new("TextLabel")
	label.Name       = "FloatingDelta"
	label.Text       = text
	label.TextColor3 = color
	label.Font       = Enum.Font.GothamBold
	label.TextScaled = true
	label.BackgroundTransparency = 1
	label.Size     = UDim2.new(0, 140, 0, 40)
	label.Position = UDim2.new(0.5, -70, 0.38, 0)
	label.ZIndex   = 20
	label.Parent   = parent

	TweenService:Create(label,
		TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, -70, 0.26, 0), TextTransparency = 1 }
	):Play()

	task.delay(1.5, function()
		label:Destroy()
	end)
end

-- ── KnitStart ─────────────────────────────────────────────────────────────────

function HUDController:KnitStart()
	local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local HUD       = PlayerGui:WaitForChild("HUD", 20) :: ScreenGui?

	if not HUD then
		warn("[HUDController] HUD ScreenGui not found in PlayerGui")
		return
	end
	_hudGui = HUD

	local shiftTracker = HUD:WaitForChild("ShiftTracker", 10) :: Frame?
	if shiftTracker then
		_timeLabel     = shiftTracker:FindFirstChild("TimeLabel")    :: TextLabel?
		_unbankedLabel = shiftTracker:FindFirstChild("UnbankedLabel") :: TextLabel?
		_bankedLabel   = shiftTracker:FindFirstChild("BankedLabel")   :: TextLabel?
	end

	local staminaBar = HUD:WaitForChild("StaminaBar", 10) :: Frame?
	if staminaBar then
		_staminaFill = staminaBar:FindFirstChild("Fill") :: Frame?
	end

	-- ── Session timer ─────────────────────────────────────────────────────────

	Remotes.SessionPhaseChanged:Connect(function(_phase: string, remainingSeconds: number?)
		if _timeLabel and remainingSeconds then
			_timeLabel.Text = formatTime(remainingSeconds)
		end
	end)

	-- ── Economy ───────────────────────────────────────────────────────────────

	Remotes.PayoutReceived:Connect(function(delta: number, newUnbanked: number)
		if _unbankedLabel then
			_unbankedLabel.Text = tostring(math.floor(newUnbanked))
		end
		if delta > 0 and _hudGui then
			showFloatingDelta(_hudGui, "+" .. tostring(math.floor(delta)), STAMINA_GREEN)
		end
	end)

	Remotes.PenaltyApplied:Connect(function(delta: number, newUnbanked: number)
		if _unbankedLabel then
			_unbankedLabel.Text = tostring(math.floor(newUnbanked))
		end
		if delta > 0 and _hudGui then
			showFloatingDelta(_hudGui, "-" .. tostring(math.floor(delta)), STAMINA_RED)
		end
	end)

	-- ── Stamina bar (high-frequency UnreliableRemoteEvent) ───────────────────

	Remotes.StaminaUpdated:Connect(function(current: number, maxStam: number?)
		if maxStam then
			_maxStamina = maxStam
		end
		local pct = math.clamp(current / _maxStamina, 0, 1)
		if _staminaFill then
			_staminaFill.Size = UDim2.new(pct, 0, 1, 0)
			if pct > 0.6 then
				_staminaFill.BackgroundColor3 = STAMINA_GREEN
			elseif pct > 0.3 then
				_staminaFill.BackgroundColor3 = STAMINA_YELLOW
			else
				_staminaFill.BackgroundColor3 = STAMINA_RED
			end
		end
	end)
end

return HUDController
