-- WhistleController wires up the whistle input on the client.
--
-- Input: F key (keyboard) OR WhistleBtn GuiButton (touch/mobile).
-- While held: fires WhistleStart once, plays looping SFX with pitch cycling,
--             emits ParticleEmitter at MouthAttachment for 0.3s each cycle.
-- On release: fires WhistleStop, stops SFX.
--
-- Pitch cycles across 8 steps: 0.75 + (step-1) × 0.0357 ≈ 0.75 → 1.0.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local RunService        = game:GetService("RunService")

local Knit    = require(ReplicatedStorage.Shared.Knit)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local WhistleController = Knit.CreateController({ Name = "WhistleController" })

local LocalPlayer = Players.LocalPlayer

-- SFX asset id — placeholder; swap for real whistle sound id before publish.
local WHISTLE_SOUND_ID = "rbxassetid://0"
local PITCH_STEPS      = 8
local PITCH_BASE       = 0.75
local PITCH_INCREMENT  = 0.0357
local PARTICLE_BURST_DURATION = 0.3

local _isWhistling    = false
local _pitchIndex     = 1
local _whistleSound: Sound?   = nil
local _particleConn: RBXScriptConnection? = nil

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function getOrCreateSound(): Sound
	if _whistleSound and _whistleSound.Parent then
		return _whistleSound
	end
	local character = LocalPlayer.Character
	local rootPart  = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		-- Create in workspace temporarily; will be re-created on next call with character.
		local s = Instance.new("Sound")
		s.SoundId = WHISTLE_SOUND_ID
		s.Looped  = false
		s.Volume  = 0.8
		s.Parent  = workspace
		_whistleSound = s
		return s
	end
	local s = Instance.new("Sound")
	s.SoundId = WHISTLE_SOUND_ID
	s.Looped  = false
	s.Volume  = 0.8
	s.Parent  = rootPart
	_whistleSound = s
	return s
end

local function playWhistleTone()
	local sound = getOrCreateSound()
	local pitch  = PITCH_BASE + (_pitchIndex - 1) * PITCH_INCREMENT
	sound.PlaybackSpeed = pitch
	sound:Play()

	-- Advance pitch index cyclically.
	_pitchIndex = (_pitchIndex % PITCH_STEPS) + 1

	-- Emit particles at MouthAttachment if it exists.
	local character     = LocalPlayer.Character
	local head          = character and character:FindFirstChild("Head")
	local mouthAttach   = head and head:FindFirstChild("MouthAttachment") :: Attachment?
	if mouthAttach then
		local emitter = mouthAttach:FindFirstChildOfClass("ParticleEmitter")
		if emitter then
			emitter:Emit(10)
		end
	end
end

local function beginWhistle()
	if _isWhistling then return end
	_isWhistling = true
	_pitchIndex  = 1

	Remotes.WhistleStart:FireServer()

	-- Play tones on a loop while held.
	task.spawn(function()
		while _isWhistling do
			playWhistleTone()
			task.wait(PARTICLE_BURST_DURATION)
		end
	end)
end

local function endWhistle()
	if not _isWhistling then return end
	_isWhistling = false

	if _whistleSound then
		_whistleSound:Stop()
	end

	Remotes.WhistleStop:FireServer()
end

-- ── Initialisation ────────────────────────────────────────────────────────────

function WhistleController:KnitStart()
	-- Keyboard: hold F.
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.F then
			beginWhistle()
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.F then
			endWhistle()
		end
	end)

	-- Mobile GUI button (optional; wired up when ScreenGui is available).
	-- The HUD controller is responsible for creating WhistleBtn; we connect here
	-- after a short wait in case it loads after this controller.
	task.spawn(function()
		self:_TryWireWhistleBtn()
	end)

	-- TugOfWar input: tap action while a battle is active.
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.F or input.UserInputType == Enum.UserInputType.Touch then
			-- Forward to TugOfWarController if battle is active; handled separately.
			-- WhistleController is not responsible for TugOfWar tap routing.
		end
	end)

	-- Listen for TugOfWarResult to clear any whistling state.
	Remotes.TugOfWarResult:Connect(function(_vehicleId: string, _winnerId: number)
		endWhistle()
	end)
end

function WhistleController:_TryWireWhistleBtn()
	local playerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
	if not playerGui then return end

	-- Wait up to 5 seconds for the HUD ScreenGui; skip if not present.
	local hud = playerGui:FindFirstChild("HUD")
	if not hud then
		task.delay(5, function()
			self:_TryWireWhistleBtn()
		end)
		return
	end

	local btn = hud:FindFirstChild("WhistleBtn", true)
	if not btn or not btn:IsA("GuiButton") then return end

	;(btn :: GuiButton).MouseButton1Down:Connect(function()
		beginWhistle()
	end)
	;(btn :: GuiButton).MouseButton1Up:Connect(function()
		endWhistle()
	end)
end

return WhistleController
