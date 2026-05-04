-- WhistleService processes whistle activations from clients.
--
-- On WhistleStart:
--   1. Rate-limit gate: WhistleRateLimit seconds since last activation.
--   2. Cooldown gate: post-TugOfWar loss cooldown not expired.
--   3. Stamina gate: player has > 0 stamina.
--   4. Spatial query: GetPartBoundsInRadius with VehicleHitbox filter.
--   5. SetAggro on each Traffic/Aggroed vehicle in range.
--   6. Begin stamina drain.
--
-- On WhistleStop: end drain.
--
-- Radius = WhistleBaseRadius + (WhistleLevel × WhistleStatScale), capped at WhistleMaxRadius.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Knit      = require(ReplicatedStorage.Shared.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Enums     = require(ReplicatedStorage.Shared.Enums)
local Remotes   = require(ReplicatedStorage.Shared.Remotes)

local WhistleService = Knit.CreateService({ Name = "WhistleService" })

-- { [userId]: number }  — os.clock() of last WhistleStart activation
local _lastWhistleTime: { [number]: number } = {}
-- { [userId]: number }  — os.clock() before which the player cannot whistle (TugOfWar loss)
local _whistleCooldownUntil: { [number]: number } = {}
-- { [userId]: boolean }  — currently whistling
local _isWhistling: { [number]: boolean } = {}

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function getWhistleRadius(player: Player): number
	local ok, DataService = pcall(Knit.GetService, Knit, "DataService")
	if not ok or not DataService then return Constants.WhistleBaseRadius end

	local profile = DataService:GetProfile(player)
	local level   = profile and profile.Data.SkillTree.WhistleLevel or 0
	local radius  = Constants.WhistleBaseRadius + level * Constants.WhistleStatScale

	-- VIPWhistle gamepass: +20% radius before the hard cap.
	local okM, MonetizationService = pcall(Knit.GetService, Knit, "MonetizationService")
	if okM and MonetizationService and MonetizationService:OwnsPass(player, "VIPWhistle") then
		radius = radius * 1.2
	end

	return math.min(radius, Constants.WhistleMaxRadius)
end

local function getHitboxOverlapParams(): OverlapParams
	local params = OverlapParams.new()
	params.FilterType               = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = CollectionService:GetTagged("VehicleHitbox")
	return params
end

-- ── Initialisation ────────────────────────────────────────────────────────────

function WhistleService:KnitStart()
	Remotes.WhistleStart:Connect(function(player: Player)
		self:HandleWhistleStart(player)
	end)

	Remotes.WhistleStop:Connect(function(player: Player)
		self:HandleWhistleStop(player)
	end)
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Called by TugOfWarService when this player loses a battle.
function WhistleService:SetAggro(vehicleId: string, player: Player)
	-- Delegate to VehicleService — this method name mirrors the state machine.
	local ok, VehicleService = pcall(Knit.GetService, Knit, "VehicleService")
	if ok and VehicleService then
		VehicleService:SetAggro(vehicleId, player)
	end
end

-- Applied by TugOfWarService after a loss.
function WhistleService:ApplyLossCooldown(player: Player)
	_whistleCooldownUntil[player.UserId] = os.clock() + Constants.WhistleCooldownOnLoss
	-- Force-stop any active whistle.
	self:HandleWhistleStop(player)
end

-- ── Handlers ─────────────────────────────────────────────────────────────────

function WhistleService:HandleWhistleStart(player: Player)
	local uid  = player.UserId
	local now  = os.clock()

	-- Stun gate (PoliceService catch stun).
	local okC, CombatService = pcall(Knit.GetService, Knit, "CombatService")
	if okC and CombatService and CombatService:IsStunned(player) then return end

	-- Rate limit.
	local lastTime = _lastWhistleTime[uid] or 0
	if (now - lastTime) < Constants.WhistleRateLimit then return end

	-- Post-loss cooldown.
	local cooldownUntil = _whistleCooldownUntil[uid] or 0
	if now < cooldownUntil then return end

	-- Stamina gate.
	local ok, StaminaService = pcall(Knit.GetService, Knit, "StaminaService")
	if not ok or not StaminaService then return end
	if StaminaService:GetStamina(player) <= 0 then return end

	_lastWhistleTime[uid] = now
	_isWhistling[uid]     = true

	StaminaService:BeginDrain(player, "whistle")

	-- Spatial query for VehicleHitbox parts.
	local character = player.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return end

	local radius = getWhistleRadius(player)
	local parts  = workspace:GetPartBoundsInRadius(
		rootPart.Position,
		radius,
		getHitboxOverlapParams()
	)

	-- Collect unique vehicleIds from hit hitbox parts.
	local seen: { [string]: boolean } = {}
	for _, part in ipairs(parts) do
		local vehicleId = part:GetAttribute("VehicleId") :: string?
		if not vehicleId or seen[vehicleId] then continue end
		seen[vehicleId] = true

		-- Only aggro vehicles that are still on the road.
		local okV, VehicleService = pcall(Knit.GetService, Knit, "VehicleService")
		if not okV or not VehicleService then continue end

		local state = VehicleService:GetState(vehicleId)
		if state == Enums.VehicleState.Traffic or state == Enums.VehicleState.Aggroed then
			VehicleService:SetAggro(vehicleId, player)
		end
	end
end

function WhistleService:HandleWhistleStop(player: Player)
	local uid = player.UserId
	if not _isWhistling[uid] then return end
	_isWhistling[uid] = false

	local ok, StaminaService = pcall(Knit.GetService, Knit, "StaminaService")
	if ok and StaminaService then
		StaminaService:EndDrain(player, "whistle")
	end
end

-- Public alias used by CombatService (strike interrupts an active whistle).
function WhistleService:ForceStop(player: Player)
	self:HandleWhistleStop(player)
end

return WhistleService
