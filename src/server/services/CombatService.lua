-- CombatService handles server-authoritative PvP mechanics: dash, melee strike,
-- ragdoll, stun, and spike-strip placement.
--
-- State owned here:
--   _dashCooldowns   — uid → tick() expiry timestamp
--   _strikeCooldowns — uid → tick() expiry timestamp (0.5 s hardcoded)
--   _stunned         — uid → boolean (set by PoliceService via SetStunned)
--
-- ForceRagdoll is public so PoliceService and AggroSUV knockback can reuse it.
-- SetStunned / IsStunned are public so PoliceService can gate all actions.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService        = game:GetService("RunService")
local Players           = game:GetService("Players")

local Knit      = require(ReplicatedStorage.Shared.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Remotes   = require(ReplicatedStorage.Shared.Remotes)

local STRIKE_COOLDOWN = 0.5  -- seconds (hardcoded per spec)

local CombatService = Knit.CreateService({ Name = "CombatService" })

local _dashCooldowns:   { [number]: number }  = {}
local _strikeCooldowns: { [number]: number }  = {}
local _stunned:         { [number]: boolean } = {}

-- ── Math helpers ──────────────────────────────────────────────────────────────

-- Clamp dir into the cone defined by lookVec and maxAngleRad.
-- Returns a unit vector.
local function clampDirToCone(dir: Vector3, lookVec: Vector3, maxAngleRad: number): Vector3
	local dot   = math.clamp(dir:Dot(lookVec), -1, 1)
	local angle = math.acos(dot)
	if angle <= maxAngleRad then
		return dir
	end
	-- Decompose: parallel component + perpendicular component.
	local parallel = lookVec * dot
	local perp     = dir - parallel
	local perpMag  = perp.Magnitude
	if perpMag < 1e-6 then
		-- dir is antiparallel to lookVec; clamp to forward.
		return lookVec
	end
	-- Reconstruct at cone boundary.
	return (lookVec * math.cos(maxAngleRad) + perp.Unit * math.sin(maxAngleRad)).Unit
end

-- ── Ragdoll helpers ───────────────────────────────────────────────────────────

function CombatService:_ApplyRagdoll(player: Player, duration: number)
	local char = player.Character
	if not char then return end
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	humanoid.PlatformStand = true

	task.delay(duration, function()
		local charNow = player.Character
		if not charNow then return end
		local h = charNow:FindFirstChildOfClass("Humanoid")
		if h then
			h.PlatformStand = false
		end
	end)
end

-- ── Overlap param builders ────────────────────────────────────────────────────

local function playerCharacterParams(exclude: Player?): OverlapParams
	local targets: { Instance } = {}
	for _, p in Players:GetPlayers() do
		if p ~= exclude and p.Character then
			table.insert(targets, p.Character)
		end
	end
	local params = OverlapParams.new()
	params.FilterType               = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = targets
	return params, targets
end

local function vehicleHitboxParams(): OverlapParams
	local params = OverlapParams.new()
	params.FilterType               = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = CollectionService:GetTagged("VehicleHitbox")
	return params
end

-- ── Initialisation ────────────────────────────────────────────────────────────

function CombatService:KnitStart()
	Remotes.DashRequest:Connect(function(player: Player, directionRaw: Vector3)
		self:_HandleDashRequest(player, directionRaw)
	end)

	Remotes.StrikeRequest:Connect(function(player: Player)
		self:_HandleStrikeRequest(player)
	end)

	-- Spike Strip placement (P2).
	Remotes.PlaceStrip:Connect(function(player: Player, position: Vector3)
		self:_HandlePlaceStrip(player, position)
	end)
end

-- ── Dash ──────────────────────────────────────────────────────────────────────

function CombatService:_HandleDashRequest(player: Player, directionRaw: Vector3)
	local uid = player.UserId

	-- Stun gate.
	if _stunned[uid] then return end

	-- Cooldown gate.
	if tick() < (_dashCooldowns[uid] or 0) then return end

	-- Character / HRP must exist.
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end

	-- Stamina gate (also deducts).
	local okS, StaminaService = pcall(Knit.GetService, Knit, "StaminaService")
	if not okS or not StaminaService then return end
	if not StaminaService:Spend(player, Constants.DashStaminaCost) then return end

	-- Sanitise and clamp direction to allowed cone.
	local dirMag = directionRaw.Magnitude
	if dirMag < 1e-6 then return end
	local dir      = directionRaw / dirMag
	local lookVec  = hrp.CFrame.LookVector
	local maxAngle = math.rad(Constants.DashMaxAngleDeg)
	local clampedDir = clampDirToCone(dir, lookVec, maxAngle)

	-- Apply impulse.
	hrp:ApplyImpulse(clampedDir * 8000)

	-- Record cooldown.
	_dashCooldowns[uid] = tick() + Constants.DashCooldown

	-- Hit detection loop for DashDuration seconds.
	task.spawn(function()
		local startTime = os.clock()
		local hitFired  = false
		local conn: RBXScriptConnection

		conn = RunService.Heartbeat:Connect(function()
			if hitFired or (os.clock() - startTime) > Constants.DashDuration then
				conn:Disconnect()
				return
			end

			local charNow = player.Character
			local hrpNow  = charNow and charNow:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not hrpNow then
				conn:Disconnect()
				return
			end

			local params, targets = playerCharacterParams(player)
			if #targets == 0 then return end

			local parts = workspace:GetPartBoundsInBox(
				hrpNow.CFrame,
				Vector3.new(4, 5, 3),
				params
			)

			for _, part in ipairs(parts) do
				for _, p in Players:GetPlayers() do
					if p ~= player and p.Character == part.Parent then
						hitFired = true
						conn:Disconnect()

						self:_ApplyRagdoll(p, Constants.DashRagdollDuration)

						local okD, DragService = pcall(Knit.GetService, Knit, "DragService")
						if okD and DragService then
							DragService:ForceRelease(p)
						end
						return
					end
				end
			end
		end)
	end)
end

-- ── Strike ────────────────────────────────────────────────────────────────────

function CombatService:_HandleStrikeRequest(player: Player)
	local uid = player.UserId

	-- Stun gate.
	if _stunned[uid] then return end

	-- Cooldown gate.
	if tick() < (_strikeCooldowns[uid] or 0) then return end
	_strikeCooldowns[uid] = tick() + STRIKE_COOLDOWN

	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end

	-- Box: 2 studs in front of player, MeleeWidth × 4 × MeleeRange.
	local boxCFrame = hrp.CFrame * CFrame.new(0, 0, -2)
	local boxSize   = Vector3.new(Constants.MeleeWidth, 4, Constants.MeleeRange)

	-- ── Priority 1: ThiefNPC ──────────────────────────────────────────────────
	do
		local thiefParams = OverlapParams.new()
		thiefParams.FilterType               = Enum.RaycastFilterType.Include
		thiefParams.FilterDescendantsInstances = CollectionService:GetTagged("ThiefNPC")

		local thiefParts = workspace:GetPartBoundsInBox(boxCFrame, boxSize, thiefParams)
		for _, part in ipairs(thiefParts) do
			local model   = part:FindFirstAncestorOfClass("Model")
			local thiefId = model and model:GetAttribute("ThiefId") :: string?
			if thiefId then
				local okT, ThiefService = pcall(Knit.GetService, Knit, "ThiefService")
				if okT and ThiefService then
					ThiefService:Interrupt(thiefId)
				end
				-- ThiefNPC takes full priority — no further checks.
				return
			end
		end
	end

	-- ── Priority 2: Rival player ──────────────────────────────────────────────
	do
		local playerParams, targets = playerCharacterParams(player)
		if #targets > 0 then
			local playerParts = workspace:GetPartBoundsInBox(boxCFrame, boxSize, playerParams)
			for _, part in ipairs(playerParts) do
				for _, rival in Players:GetPlayers() do
					if rival ~= player and rival.Character == part.Parent then
						local rivalHRP = rival.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
						if rivalHRP then
							rivalHRP:ApplyImpulse(hrp.CFrame.LookVector * 3000)
						end

						local okD, DragService = pcall(Knit.GetService, Knit, "DragService")
						if okD and DragService then
							DragService:ForceRelease(rival)
						end

						local okW, WhistleService = pcall(Knit.GetService, Knit, "WhistleService")
						if okW and WhistleService then
							WhistleService:ForceStop(rival)
						end
						-- Strike one rival and stop.
						goto strikeCheckDone
					end
				end
			end
		end
	end

	-- ── Also: SpikeStrip destruction via melee ────────────────────────────────
	do
		local stripParams = OverlapParams.new()
		stripParams.FilterType               = Enum.RaycastFilterType.Include
		stripParams.FilterDescendantsInstances = CollectionService:GetTagged("SpikeStrip")

		local stripParts = workspace:GetPartBoundsInBox(boxCFrame, boxSize, stripParams)
		for _, part in ipairs(stripParts) do
			if CollectionService:HasTag(part, "SpikeStrip") then
				part:Destroy()
				break
			end
		end
	end

	::strikeCheckDone::
end

-- ── Spike Strip Placement (P2) ────────────────────────────────────────────────

function CombatService:_HandlePlaceStrip(player: Player, position: Vector3)
	local char = player.Character
	local hrp  = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then return end

	-- 1. Check proximity.
	if (position - hrp.Position).Magnitude > Constants.SpikeStripPlaceRadius then return end

	-- 2. Ground surface check.
	local rayResult = workspace:Raycast(
		position + Vector3.new(0, 1, 0),
		Vector3.new(0, -2, 0)
	)
	if not rayResult then return end

	-- 3. Check and consume inventory.
	local okM, MonetizationService = pcall(Knit.GetService, Knit, "MonetizationService")
	if not okM or not MonetizationService then return end
	local inventory = MonetizationService:GetInventory(player)
	if not inventory or (inventory.SpikeStrip or 0) < 1 then return end
	if not MonetizationService:ConsumeItem(player, "SpikeStrip") then return end

	-- 4. Create the strip Part.
	local strip = Instance.new("Part")
	strip.Name           = "SpikeStrip"
	strip.Size           = Vector3.new(4, 0.2, 1)
	strip.CollisionGroup = "Environment"
	strip.Anchored       = true
	strip.CFrame         = CFrame.new(position)
	strip:SetAttribute("OwnerId", player.UserId)
	CollectionService:AddTag(strip, "SpikeStrip")
	strip.Parent = workspace

	-- 5. Damage vehicles that roll over it.
	local touchConn: RBXScriptConnection
	touchConn = strip.Touched:Connect(function(hit: BasePart)
		if not CollectionService:HasTag(hit, "VehicleHitbox") then return end
		local vehicleId = hit:GetAttribute("VehicleId") :: string?
		if not vehicleId then return end
		touchConn:Disconnect()

		local okV, VehicleService = pcall(Knit.GetService, Knit, "VehicleService")
		if okV and VehicleService then
			VehicleService:SetDamaged(vehicleId)
		end
		strip:Destroy()
	end)
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Called by PoliceService after a player is caught.
function CombatService:SetStunned(player: Player, duration: number)
	local uid = player.UserId
	_stunned[uid] = true

	Remotes.PlayerStunned:FireClient(player, duration)

	task.delay(duration, function()
		_stunned[uid] = false
	end)
end

function CombatService:IsStunned(player: Player): boolean
	return _stunned[player.UserId] == true
end

-- Public wrapper so PoliceService and VehicleService (AggroSUV) can ragdoll players.
function CombatService:ForceRagdoll(player: Player, duration: number)
	self:_ApplyRagdoll(player, duration)
end

return CombatService
