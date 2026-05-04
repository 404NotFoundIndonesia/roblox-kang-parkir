-- EventService schedules and drives timed world events during PeakShift.
--
-- Scheduling loop (starts at PeakShift, stops at PostSession):
--   1. Wait random(EventCooldownMin, EventCooldownMax) seconds.
--   2. Pick a random EventType (equal weight).
--   3. _StartEvent → dispatch handler → task.delay(duration, _EndEvent).
--   4. _EndEvent → dispatch cleanup → _ScheduleNext().
--
-- Durations: MonsoonRain = 90 s | SatpolRaid = 120 s | FlashMob = FlashMobDuration + 60 s.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit      = require(ReplicatedStorage.Shared.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Enums     = require(ReplicatedStorage.Shared.Enums)
local Remotes   = require(ReplicatedStorage.Shared.Remotes)

local EventService = Knit.CreateService({ Name = "EventService" })

local _activeEvent: string? = nil

-- Monsoon state: store original physical properties and walk speeds so we can restore them.
local _originalProps:     { [BasePart]: PhysicalProperties } = {}
local _originalWalkSpeed: { [number]: number }               = {}

local EVENT_DURATION: { [string]: number } = {
	MonsoonRain = 90,
	SatpolRaid  = 120,
	FlashMob    = Constants.FlashMobDuration + 60,
}

local EVENT_TYPES = { "MonsoonRain", "SatpolRaid", "FlashMob" }

-- ── Session guard ─────────────────────────────────────────────────────────────

local function isShiftActive(): boolean
	local ok, SessionService = pcall(Knit.GetService, Knit, "SessionService")
	if not ok or not SessionService then return false end
	local phase = SessionService:GetPhase()
	return phase == Enums.SessionPhase.PeakShift
		or phase == Enums.SessionPhase.RushHour
		or phase == Enums.SessionPhase.ShiftEnd
end

-- ── Monsoon ───────────────────────────────────────────────────────────────────

local function startMonsoon()
	local map = workspace:FindFirstChild("Map")
	if map then
		for _, descendant in map:GetDescendants() do
			if descendant:IsA("BasePart") and descendant.Material ~= Enum.Material.Air then
				local curr = descendant.CurrentPhysicalProperties
				_originalProps[descendant] = descendant.CustomPhysicalProperties
				descendant.CustomPhysicalProperties = PhysicalProperties.new(
					curr.Density,
					Constants.MonsoonFriction,
					curr.Elasticity,
					curr.FrictionWeight,
					curr.ElasticityWeight
				)
			end
		end
	end

	for _, player in Players:GetPlayers() do
		local char     = player.Character
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		if humanoid then
			_originalWalkSpeed[player.UserId] = humanoid.WalkSpeed
			humanoid.WalkSpeed = humanoid.WalkSpeed * Constants.MonsoonSpeedMultiplier
		end
	end

	Remotes.RainToggle:FireAllClients(true)
end

local function endMonsoon()
	for part, props in _originalProps do
		if part and part.Parent then
			part.CustomPhysicalProperties = props
		end
	end
	table.clear(_originalProps)

	for _, player in Players:GetPlayers() do
		local char     = player.Character
		local humanoid = char and char:FindFirstChildOfClass("Humanoid")
		local original = _originalWalkSpeed[player.UserId]
		if humanoid and original then
			humanoid.WalkSpeed = original
		end
	end
	table.clear(_originalWalkSpeed)

	Remotes.RainToggle:FireAllClients(false)
end

-- ── Raid ──────────────────────────────────────────────────────────────────────

local function startRaid()
	local ok, PoliceService = pcall(Knit.GetService, Knit, "PoliceService")
	if ok and PoliceService then
		PoliceService:StartRaid()
	end
end

local function endRaid()
	local ok, PoliceService = pcall(Knit.GetService, Knit, "PoliceService")
	if ok and PoliceService then
		PoliceService:EndRaid()
	end
end

-- ── Flash Mob ─────────────────────────────────────────────────────────────────

local function startFlashMob()
	local okT, TrafficService = pcall(Knit.GetService, Knit, "TrafficService")
	if okT and TrafficService then
		TrafficService:FlashMobBurst()
	end

	local okE, EconomyService = pcall(Knit.GetService, Knit, "EconomyService")
	if okE and EconomyService then
		EconomyService:SetEventMultiplier(Constants.FlashMobEventMultiplier)
	end
end

local function endFlashMob()
	local okE, EconomyService = pcall(Knit.GetService, Knit, "EconomyService")
	if okE and EconomyService then
		EconomyService:SetEventMultiplier(0)
	end

	-- RestoreWeights is a no-op if FlashMobBurst already reverted; safe to call again.
	local okT, TrafficService = pcall(Knit.GetService, Knit, "TrafficService")
	if okT and TrafficService then
		TrafficService:RestoreWeights()
	end
end

-- ── Dispatch table ────────────────────────────────────────────────────────────

local HANDLERS: { [string]: { start: () -> (), stop: () -> () } } = {
	MonsoonRain = { start = startMonsoon,  stop = endMonsoon  },
	SatpolRaid  = { start = startRaid,     stop = endRaid     },
	FlashMob    = { start = startFlashMob, stop = endFlashMob },
}

-- ── Core loop ─────────────────────────────────────────────────────────────────

function EventService:_EndEvent(eventType: string)
	_activeEvent = nil
	Remotes.EventEnd:FireAllClients(eventType)

	local handler = HANDLERS[eventType]
	if handler then
		handler.stop()
	end

	self:_ScheduleNext()
end

function EventService:_StartEvent(eventType: string)
	if _activeEvent then return end
	_activeEvent = eventType

	Remotes.EventStart:FireAllClients(eventType)

	local handler = HANDLERS[eventType]
	if handler then
		handler.start()
	end

	local duration = EVENT_DURATION[eventType] or 60
	task.delay(duration, function()
		-- Only end if this event is still active (guard against EndRaid clearing early etc.).
		if _activeEvent == eventType then
			self:_EndEvent(eventType)
		end
	end)
end

function EventService:_ScheduleNext()
	task.spawn(function()
		task.wait(math.random(Constants.EventCooldownMin, Constants.EventCooldownMax))

		if not isShiftActive() then return end
		if _activeEvent then return end

		local eventType = EVENT_TYPES[math.random(1, #EVENT_TYPES)]
		self:_StartEvent(eventType)
	end)
end

-- ── Initialisation ────────────────────────────────────────────────────────────

function EventService:KnitStart()
	task.spawn(function()
		-- Poll until SessionService is available and PeakShift has begun.
		local SessionService
		repeat
			task.wait(1)
			local ok, svc = pcall(Knit.GetService, Knit, "SessionService")
			if ok then SessionService = svc end
		until SessionService ~= nil

		repeat task.wait(1) until SessionService:GetPhase() == Enums.SessionPhase.PeakShift

		self:_ScheduleNext()
	end)
end

-- ── Public API ────────────────────────────────────────────────────────────────

function EventService:GetActiveEvent(): string?
	return _activeEvent
end

return EventService
