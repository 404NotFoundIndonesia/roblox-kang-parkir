local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit      = require(ReplicatedStorage.Shared.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Enums     = require(ReplicatedStorage.Shared.Enums)
local Remotes   = require(ReplicatedStorage.Shared.Remotes)

local SessionService = Knit.CreateService({ Name = "SessionService" })

local _currentPhase: string  = Enums.SessionPhase.Lobby
local _phaseEndTime: number  = 0      -- os.clock() timestamp when current phase ends
local _sessionActive: boolean = false  -- guard against duplicate StartSession calls

-- ── Initialisation ────────────────────────────────────────────────────────────

function SessionService:KnitStart()
	-- Broadcast remaining seconds every 1 s while a shift is running.
	-- Does nothing during Lobby or PostSession.
	task.spawn(function()
		while true do
			task.wait(1)
			if _currentPhase ~= Enums.SessionPhase.Lobby
				and _currentPhase ~= Enums.SessionPhase.PostSession
			then
				local remaining = math.max(0, math.floor(_phaseEndTime - os.clock()))
				Remotes.SessionPhaseChanged:FireAllClients(_currentPhase, remaining)
			end
		end
	end)
end

-- ── Public API ────────────────────────────────────────────────────────────────

function SessionService:GetPhase(): string
	return _currentPhase
end

-- Drives the full shift timeline: WarmUp → PeakShift → RushHour → ShiftEnd → PostSession.
-- Ignores duplicate calls while a session is already running.
function SessionService:StartSession()
	if _sessionActive then return end
	_sessionActive = true

	self:_EnterPhase(Enums.SessionPhase.WarmUp, Constants.SessionWarmUpDuration)

	task.delay(Constants.SessionWarmUpDuration, function()
		self:_EnterPhase(Enums.SessionPhase.PeakShift, Constants.SessionPeakDuration)

		task.delay(Constants.SessionPeakDuration, function()
			self:_EnterPhase(Enums.SessionPhase.RushHour, Constants.SessionRushHourDuration)

			task.delay(Constants.SessionRushHourDuration, function()
				self:_EnterPhase(Enums.SessionPhase.ShiftEnd, Constants.SessionShiftEndBuffer)

				-- Auto-bank all players' unbanked earnings when the shift closes.
				-- EconomyService is fetched lazily here so there is no circular require.
				local ok, EconomyService = pcall(Knit.GetService, Knit, "EconomyService")
				if ok and EconomyService then
					EconomyService:AutoBankAll()
				end

				task.delay(Constants.SessionShiftEndBuffer, function()
					self:_EnterPhase(Enums.SessionPhase.PostSession, 0)
					_sessionActive = false
				end)
			end)
		end)
	end)
end

-- ── Private ───────────────────────────────────────────────────────────────────

function SessionService:_EnterPhase(phase: string, duration: number)
	_currentPhase = phase
	_phaseEndTime = os.clock() + duration
	-- Fire both phase name and initial duration so clients can initialise their
	-- timers immediately, before the 1-second broadcast loop fires.
	Remotes.SessionPhaseChanged:FireAllClients(phase, duration)
end

return SessionService
