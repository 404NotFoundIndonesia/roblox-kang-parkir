-- EventController reacts to server-driven world events with client-side VFX and UI.
--
-- EventStart(eventType) → show EventBanner + start VFX/audio:
--   MonsoonRain → clone RainEmitter into workspace, Rate = 200
--   SatpolRaid  → clone PoliceSiren into SoundService, looped
--   FlashMob    → (no extra client VFX; banner is sufficient)
--
-- EventEnd(eventType)   → tear down VFX/audio.
-- RainToggle(enabled)   → safety hook (EventService also fires this for server physics).

local SoundService      = game:GetService("SoundService")
local TweenService      = game:GetService("TweenService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit    = require(ReplicatedStorage.Shared.Knit)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local EventController = Knit.CreateController({ Name = "EventController" })

local EVENT_TITLES: { [string]: string } = {
	MonsoonRain = "\u{26C8} HUJAN DERAS!",
	SatpolRaid  = "\u{1F6A8} RAZIA SATPOL PP!",
	FlashMob    = "\u{1F3B6} KONSER DADAKAN!",
}

local _rainInstance: Instance? = nil
local _sirenSound:   Sound?    = nil
local _bannerTask:   thread?   = nil

-- ── Banner ────────────────────────────────────────────────────────────────────

local function showBanner(playerGui: Instance, eventType: string)
	local bannerGui = playerGui:FindFirstChild("EventBanner")
	if not bannerGui then return end
	local frame = bannerGui:FindFirstChildOfClass("Frame") :: Frame?
	if not frame then return end
	local label = frame:FindFirstChild("TitleLabel") :: TextLabel?
	if label then
		label.Text = EVENT_TITLES[eventType] or eventType
	end

	frame.Visible  = true
	frame.Position = UDim2.new(0.5, 0, -0.15, 0)

	TweenService:Create(frame,
		TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0.05, 0) }
	):Play()

	-- Auto-hide after 4 seconds.
	if _bannerTask then task.cancel(_bannerTask) end
	_bannerTask = task.delay(4, function()
		_bannerTask = nil
		TweenService:Create(frame,
			TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Position = UDim2.new(0.5, 0, -0.15, 0) }
		):Play()
		task.delay(0.3, function()
			frame.Visible = false
		end)
	end)
end

-- ── Rain VFX ─────────────────────────────────────────────────────────────────

local function startRain()
	if _rainInstance then return end
	local assets   = ReplicatedStorage:FindFirstChild("Assets")
	local vfx      = assets and assets:FindFirstChild("VFX")
	local template = vfx and vfx:FindFirstChild("RainEmitter")
	if not template then return end

	local clone = template:Clone()
	clone.Parent = workspace
	-- Set rate regardless of whether it's a ParticleEmitter or a Part containing one.
	local pe = if clone:IsA("ParticleEmitter")
		then clone :: ParticleEmitter
		else clone:FindFirstChildOfClass("ParticleEmitter") :: ParticleEmitter?
	if pe then pe.Rate = 200 end
	_rainInstance = clone
end

local function stopRain()
	if _rainInstance then
		_rainInstance:Destroy()
		_rainInstance = nil
	end
end

-- ── Siren audio ──────────────────────────────────────────────────────────────

local function startSiren()
	if _sirenSound then return end
	local assets   = ReplicatedStorage:FindFirstChild("Assets")
	local audio    = assets and assets:FindFirstChild("Audio")
	local template = audio and audio:FindFirstChild("PoliceSiren")
	if not template then return end

	local sound    = template:Clone() :: Sound
	sound.Looped   = true
	sound.Parent   = SoundService
	sound:Play()
	_sirenSound = sound
end

local function stopSiren()
	if _sirenSound then
		_sirenSound:Stop()
		_sirenSound:Destroy()
		_sirenSound = nil
	end
end

-- ── KnitStart ─────────────────────────────────────────────────────────────────

function EventController:KnitStart()
	local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	Remotes.EventStart:Connect(function(eventType: string)
		showBanner(PlayerGui, eventType)
		if eventType == "MonsoonRain" then
			startRain()
		elseif eventType == "SatpolRaid" then
			startSiren()
		end
	end)

	Remotes.EventEnd:Connect(function(eventType: string)
		if eventType == "MonsoonRain" then
			stopRain()
		elseif eventType == "SatpolRaid" then
			stopSiren()
		end
	end)

	-- RainToggle is the authoritative server signal for rain VFX state.
	-- Acts as a safety net alongside EventStart/EventEnd.
	Remotes.RainToggle:Connect(function(enabled: boolean)
		if enabled then
			startRain()
		else
			stopRain()
		end
	end)
end

return EventController
