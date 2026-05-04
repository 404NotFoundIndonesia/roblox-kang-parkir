-- StaminaService manages each player's stamina pool server-side.
-- Stamina max = Constants.StaminaMax + (StaminaLevel × Constants.StaminaPerSkillLevel).
-- Drains are registered by name so multiple systems can drain simultaneously.
-- Fires Remotes.StaminaUpdated (UnreliableRemoteEvent) on every change.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Players           = game:GetService("Players")

local Knit      = require(ReplicatedStorage.Shared.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes   = require(ReplicatedStorage.Shared.Remotes)

local StaminaService = Knit.CreateService({ Name = "StaminaService" })

-- { [userId]: number }
local _stamina:    { [number]: number } = {}
-- { [userId]: { [drainName]: number } }  — drain rates in units/sec
local _drains:     { [number]: { [string]: number } } = {}
-- { [userId]: number }  — max stamina cache (recomputed on profile load)
local _maxStamina: { [number]: number } = {}

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function getMax(player: Player): number
	return _maxStamina[player.UserId] or Constants.StaminaMax
end

local function fireUpdate(player: Player)
	local current = _stamina[player.UserId] or 0
	local max     = getMax(player)
	Remotes.StaminaUpdated:FireClient(player, current, max)
end

local function totalDrain(userId: number): number
	local drains = _drains[userId]
	if not drains then return 0 end
	local total = 0
	for _, rate in drains do
		total += rate
	end
	return total
end

-- ── Initialisation ────────────────────────────────────────────────────────────

function StaminaService:KnitStart()
	Players.PlayerAdded:Connect(function(player)
		self:_InitPlayer(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self:_CleanupPlayer(player)
	end)
	for _, player in Players:GetPlayers() do
		self:_InitPlayer(player)
	end

	-- Heartbeat tick: apply drain, apply regen, clamp, fire update.
	RunService.Heartbeat:Connect(function(dt: number)
		for _, player in Players:GetPlayers() do
			local uid = player.UserId
			if _stamina[uid] == nil then continue end

			local drain    = totalDrain(uid)
			local netDrain = drain - Constants.StaminaRegenRate
			local prev     = _stamina[uid]

			_stamina[uid] = math.clamp(
				prev - netDrain * dt,
				0,
				getMax(player)
			)

			-- Fire only when value changed meaningfully (>= 0.1 unit).
			if math.abs(_stamina[uid] - prev) >= 0.1 then
				fireUpdate(player)
			end
		end
	end)
end

function StaminaService:_InitPlayer(player: Player)
	local uid = player.UserId
	-- Compute max — DataService may not be ready yet; use base until SetMaxFromProfile.
	_maxStamina[uid] = Constants.StaminaMax
	_stamina[uid]    = Constants.StaminaMax
	_drains[uid]     = {}
end

function StaminaService:_CleanupPlayer(player: Player)
	local uid = player.UserId
	_stamina[uid]    = nil
	_drains[uid]     = nil
	_maxStamina[uid] = nil
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Called by DataService once the profile is loaded and StaminaLevel is known.
function StaminaService:SetMaxFromProfile(player: Player, staminaLevel: number)
	local uid = player.UserId
	if _stamina[uid] == nil then return end
	local newMax = Constants.StaminaMax + staminaLevel * Constants.StaminaPerSkillLevel
	_maxStamina[uid] = newMax
	_stamina[uid]    = math.min(_stamina[uid], newMax)
	fireUpdate(player)
end

-- Register a named drain (e.g. "whistle"). Rate in units/second.
function StaminaService:BeginDrain(player: Player, drainName: string, rate: number?)
	local uid = player.UserId
	if not _drains[uid] then return end
	_drains[uid][drainName] = rate or Constants.WhistleStaminaDrain
end

-- Remove a named drain.
function StaminaService:EndDrain(player: Player, drainName: string)
	local uid = player.UserId
	if not _drains[uid] then return end
	_drains[uid][drainName] = nil
end

-- Returns true if current stamina >= cost and deducts it. Used for one-shot costs.
function StaminaService:Spend(player: Player, amount: number): boolean
	local uid = player.UserId
	if _stamina[uid] == nil then return false end
	if _stamina[uid] < amount then return false end
	_stamina[uid] = _stamina[uid] - amount
	fireUpdate(player)
	return true
end

-- Instantly fill stamina to max (EnergyDrink consumable).
function StaminaService:SetFull(player: Player)
	local uid = player.UserId
	if _stamina[uid] == nil then return end
	_stamina[uid] = getMax(player)
	fireUpdate(player)
end

-- Read current stamina (used by WhistleService gate check).
function StaminaService:GetStamina(player: Player): number
	return _stamina[player.UserId] or 0
end

return StaminaService
