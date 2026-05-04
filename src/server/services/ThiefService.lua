-- ThiefService manages Helmet Thief NPCs that target parked Sport Bikes.
--
-- State machine (per thief, runs in its own task.spawn thread):
--   Navigate  → walk to target Sport Bike via PathfindingService
--   Interact  → play Rummage animation, wait ThiefInteractDuration
--   Flee      → weld helmet to hand, walk to ThiefDespawnNode, fire penalty
--   Roam      → wander randomly; retarget after ThiefRetargetCooldown expires
--
-- Interrupt() sets entry.interrupted = true. The running thread detects it
-- at every task.wait(0.1) checkpoint, exits its current operation, and waits
-- while Interrupt() handles ragdoll + Roam transition.
--
-- Spawn manager loop (every 5 s): spawns a new thief when count < ThiefMaxAlive
-- and global _respawnCooldown has expired.

local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
local CollectionService  = game:GetService("CollectionService")
local HttpService        = game:GetService("HttpService")
local RunService         = game:GetService("RunService")
local Players            = game:GetService("Players")

local Knit      = require(ReplicatedStorage.Shared.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Enums     = require(ReplicatedStorage.Shared.Enums)
local Remotes   = require(ReplicatedStorage.Shared.Remotes)

local ThiefService = Knit.CreateService({ Name = "ThiefService" })

type ThiefEntry = {
	model                 : Model,
	state                 : string,
	targetVehicleId       : string?,
	heldHelmet            : BasePart?,
	interrupted           : boolean,
	retargetCooldownUntil : number,
}

local _activeThieves: { [string]: ThiefEntry } = {}
local _respawnCooldown: number = 0  -- global; set after a successful theft

-- ── Map node finders ──────────────────────────────────────────────────────────

local function getThiefDespawnPos(): Vector3?
	local map   = workspace:FindFirstChild("Map")
	local nodes = map and map:FindFirstChild("Nodes")
	local node  = nodes and nodes:FindFirstChild("ThiefDespawnNode") :: BasePart?
	return node and node.Position or nil
end

local function getThiefSpawnPos(): Vector3?
	-- Spawn at the same node the thief ultimately flees to (map edge).
	return getThiefDespawnPos()
end

-- ── Asset helpers ─────────────────────────────────────────────────────────────

local function getThiefTemplate(): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local npcs   = assets and assets:FindFirstChild("NPCs")
	local tmpl   = npcs and npcs:FindFirstChild("HelmetThief")
	return tmpl and tmpl:IsA("Model") and tmpl or nil
end

-- ── Navigation ────────────────────────────────────────────────────────────────

-- Walk the NPC toward targetPos waypoint-by-waypoint.
-- Returns true on arrival, false if the thief entry disappeared or was interrupted.
function ThiefService:_NavigateThief(thiefId: string, targetPos: Vector3): boolean
	local entry = _activeThieves[thiefId]
	if not entry then return false end

	local humanoid   = entry.model:FindFirstChildOfClass("Humanoid")
	local primaryPart = entry.model.PrimaryPart :: BasePart?
	if not humanoid or not primaryPart then return false end

	local path = PathfindingService:CreatePath({
		AgentRadius   = 1.5,
		AgentHeight   = 5,
		AgentCanJump  = false,
		AgentCanClimb = false,
	})

	local ok = pcall(path.ComputeAsync, path, primaryPart.Position, targetPos)
	if not ok or path.Status ~= Enum.PathStatus.Success then
		return false
	end

	for _, waypoint in ipairs(path:GetWaypoints()) do
		local e = _activeThieves[thiefId]
		if not e or e.interrupted then return false end

		humanoid:MoveTo(waypoint.Position)

		-- Poll until within 2 studs of waypoint or interrupted.
		while true do
			task.wait(0.1)
			local e2 = _activeThieves[thiefId]
			if not e2 or e2.interrupted then return false end
			if (primaryPart.Position - waypoint.Position).Magnitude < 2 then break end
		end
	end

	return _activeThieves[thiefId] ~= nil and not _activeThieves[thiefId].interrupted
end

-- Wait for `duration` seconds, checking for interruption every 0.1 s.
-- Returns true if the full duration elapsed without interruption.
function ThiefService:_WaitInterruptible(thiefId: string, duration: number): boolean
	local elapsed = 0
	while elapsed < duration do
		task.wait(0.1)
		elapsed += 0.1
		local e = _activeThieves[thiefId]
		if not e or e.interrupted then return false end
	end
	return true
end

-- ── Helmet helpers ────────────────────────────────────────────────────────────

local function findHelmet(vehicleModel: Model): BasePart?
	return vehicleModel:FindFirstChild("Helmet") :: BasePart?
end

local function removeHelmetWelds(helmet: BasePart, vehicleModel: Model)
	-- Remove welds directly on the helmet.
	for _, child in helmet:GetChildren() do
		if child:IsA("WeldConstraint") then
			child:Destroy()
		end
	end
	-- Remove welds elsewhere in the model that reference the helmet.
	for _, desc in vehicleModel:GetDescendants() do
		if desc:IsA("WeldConstraint") then
			local w = desc :: WeldConstraint
			if w.Part0 == helmet or w.Part1 == helmet then
				desc:Destroy()
			end
		end
	end
end

function ThiefService:_WeldHelmetToHand(thiefId: string, helmet: BasePart)
	local entry = _activeThieves[thiefId]
	if not entry then return end

	-- R15: "RightHand"; R6: "Right Arm".
	local rightHand = (entry.model:FindFirstChild("RightHand")
		or entry.model:FindFirstChild("Right Arm")) :: BasePart?
	if not rightHand then return end

	helmet.CFrame = rightHand.CFrame
	local weld = Instance.new("WeldConstraint")
	weld.Part0  = rightHand
	weld.Part1  = helmet
	weld.Parent = helmet
end

-- ── Target finder ─────────────────────────────────────────────────────────────

-- Find a parked Sport Bike with an intact helmet.
-- Excludes the thief's own current retarget cooldown window.
function ThiefService:_FindTargetSportBike(): string?
	local okV, VehicleService = pcall(Knit.GetService, Knit, "VehicleService")
	if not okV or not VehicleService then return nil end

	local allVehicles = VehicleService:GetAllVehicles()
	local candidates: { string } = {}

	for vid, data in allVehicles do
		if data.vehicleType ~= "SportBike" then continue end
		if data.state ~= Enums.VehicleState.Parked then continue end
		if not data.model then continue end
		local helmet = findHelmet(data.model)
		if not helmet or helmet:GetAttribute("Stolen") then continue end
		table.insert(candidates, vid)
	end

	if #candidates == 0 then return nil end
	return candidates[math.random(#candidates)]
end

-- ── Behavior tree ─────────────────────────────────────────────────────────────

function ThiefService:_StartBehaviorTree(thiefId: string, targetVehicleId: string)
	_activeThieves[thiefId].targetVehicleId = targetVehicleId
	_activeThieves[thiefId].state           = Enums.NPCState.Navigate

	task.spawn(function()
		while true do
			local entry = _activeThieves[thiefId]
			if not entry then break end

			-- Pause while Interrupt() is managing the transition.
			if entry.interrupted then
				task.wait(0.1)
				continue
			end

			local state = entry.state

			-- ── Navigate ───────────────────────────────────────────────────────
			if state == Enums.NPCState.Navigate then
				local vid = entry.targetVehicleId
				if not vid then
					entry.state = Enums.NPCState.Roam
					continue
				end

				local okV, VehicleService = pcall(Knit.GetService, Knit, "VehicleService")
				local allVehicles = okV and VehicleService and VehicleService:GetAllVehicles()
				local vehicleData = allVehicles and allVehicles[vid]
				local targetPos   = vehicleData and vehicleData.model
					and vehicleData.model.PrimaryPart
					and vehicleData.model.PrimaryPart.Position

				if not targetPos then
					entry.state = Enums.NPCState.Roam
					continue
				end

				local arrived = self:_NavigateThief(thiefId, targetPos)
				if arrived then
					entry.state = Enums.NPCState.Interact
				end
				-- If not arrived (interrupted / failed), loop continues.
				-- Interrupt() will have set state to Roam after ragdoll.

			-- ── Interact ───────────────────────────────────────────────────────
			elseif state == Enums.NPCState.Interact then
				-- Play Rummage animation if available.
				local humanoid = entry.model:FindFirstChildOfClass("Humanoid")
				local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
				local rummageAnim = entry.model:FindFirstChild("Rummage", true)
				local animTrack: AnimationTrack?
				if animator and rummageAnim and rummageAnim:IsA("Animation") then
					animTrack = animator:LoadAnimation(rummageAnim :: Animation)
					animTrack:Play()
				end

				local success = self:_WaitInterruptible(thiefId, Constants.ThiefInteractDuration)

				if animTrack then
					pcall(function() animTrack:Stop() end)
				end

				if not success then
					continue  -- interrupted; Interrupt() sets Roam state
				end

				-- Steal the helmet.
				local okV, VehicleService = pcall(Knit.GetService, Knit, "VehicleService")
				local allVehicles = okV and VehicleService and VehicleService:GetAllVehicles()
				local vehicleData = allVehicles and allVehicles[entry.targetVehicleId or ""]
				local helmet      = vehicleData and vehicleData.model and findHelmet(vehicleData.model)

				if not helmet then
					entry.state = Enums.NPCState.Roam
					continue
				end

				removeHelmetWelds(helmet, vehicleData.model)
				helmet:SetAttribute("Stolen", true)
				helmet.Anchored = false
				helmet.Parent   = workspace
				entry.heldHelmet = helmet

				self:_WeldHelmetToHand(thiefId, helmet)
				entry.state = Enums.NPCState.Flee

			-- ── Flee ───────────────────────────────────────────────────────────
			elseif state == Enums.NPCState.Flee then
				local despawnPos = getThiefDespawnPos()
				if despawnPos then
					self:_NavigateThief(thiefId, despawnPos)
				end

				-- Whether we were interrupted mid-flee or arrived cleanly, treat as stolen.
				local stolenVehicleId = entry.targetVehicleId
				if stolenVehicleId then
					self:_OnHelmetStolen(stolenVehicleId)
				end

				-- Destroy thief and helmet.
				if entry.heldHelmet and entry.heldHelmet.Parent then
					entry.heldHelmet:Destroy()
				end
				if entry.model and entry.model.Parent then
					entry.model:Destroy()
				end
				_activeThieves[thiefId] = nil
				_respawnCooldown = tick()
					+ math.random(Constants.ThiefRespawnDelayMin, Constants.ThiefRespawnDelayMax)
				break

			-- ── Roam ───────────────────────────────────────────────────────────
			elseif state == Enums.NPCState.Roam then
				-- After retarget cooldown, try to find a new Sport Bike.
				if tick() >= entry.retargetCooldownUntil then
					local newTarget = self:_FindTargetSportBike()
					if newTarget then
						entry.targetVehicleId = newTarget
						entry.state           = Enums.NPCState.Navigate
						continue
					end
				end

				-- No target or still in cooldown — wander to a random nearby point.
				local pp = entry.model.PrimaryPart :: BasePart?
				if pp then
					local offset = Vector3.new(
						math.random(-15, 15),
						0,
						math.random(-15, 15)
					)
					self:_NavigateThief(thiefId, pp.Position + offset)
				end
			end
		end
	end)
end

-- ── Helmet stolen callback ────────────────────────────────────────────────────

function ThiefService:_OnHelmetStolen(vehicleId: string)
	local okV, VehicleService = pcall(Knit.GetService, Knit, "VehicleService")
	if not okV or not VehicleService then return end

	local allVehicles = VehicleService:GetAllVehicles()
	local vehicleData = allVehicles and allVehicles[vehicleId]
	if not vehicleData then return end

	local ownerPlayer = vehicleData.ownerPlayer
	if not ownerPlayer then return end

	local basePayout = Constants.VehicleBasePayouts["SportBike"] or 15
	local penalty    = math.floor(basePayout * 0.4)

	local okE, EconomyService = pcall(Knit.GetService, Knit, "EconomyService")
	if okE and EconomyService then
		EconomyService:ApplyPenalty(ownerPlayer, penalty)
	end

	Remotes.HelmetStolen:FireClient(ownerPlayer)
end

-- ── Initialisation ────────────────────────────────────────────────────────────

function ThiefService:KnitStart()
	-- Spawn manager: check every 5 seconds.
	task.spawn(function()
		while true do
			task.wait(5)

			-- Count alive thieves.
			local aliveCount = 0
			for _ in _activeThieves do
				aliveCount += 1
			end

			if aliveCount >= Constants.ThiefMaxAlive then continue end
			if tick() < _respawnCooldown then continue end

			-- Find a Sport Bike target.
			local targetVehicleId = self:_FindTargetSportBike()
			if not targetVehicleId then continue end

			-- Get spawn position.
			local spawnPos = getThiefSpawnPos()
			if not spawnPos then continue end

			-- Clone template.
			local template = getThiefTemplate()
			if not template then continue end

			local model = template:Clone()
			model:PivotTo(CFrame.new(spawnPos))
			model.Parent = workspace

			-- Tag for CombatService strike detection.
			CollectionService:AddTag(model, "ThiefNPC")

			local thiefId = "T_" .. HttpService:GenerateGUID(false)
			model:SetAttribute("ThiefId", thiefId)

			_activeThieves[thiefId] = {
				model                 = model,
				state                 = Enums.NPCState.Navigate,
				targetVehicleId       = nil,
				heldHelmet            = nil,
				interrupted           = false,
				retargetCooldownUntil = 0,
			}

			self:_StartBehaviorTree(thiefId, targetVehicleId)
		end
	end)

	-- P2: ThreatInZone — notify zone owners when a thief enters their zone.
	RunService.Heartbeat:Connect(function()
		self:_CheckThreatInZone()
	end)
end

function ThiefService:_CheckThreatInZone()
	local okZ, ZoneService = pcall(Knit.GetService, Knit, "ZoneService")
	if not okZ or not ZoneService then return end

	for thiefId, entry in _activeThieves do
		if entry.state ~= Enums.NPCState.Navigate
			and entry.state ~= Enums.NPCState.Interact
			and entry.state ~= Enums.NPCState.Flee
		then
			continue
		end

		local pp = entry.model and entry.model.PrimaryPart :: BasePart?
		if not pp then continue end

		for _, player in Players:GetPlayers() do
			local zone = ZoneService:GetPlayerZone(player)
			if zone and ZoneService:IsInZone(zone, pp.Position) then
				Remotes.ThreatInZone:FireClient(player, thiefId, pp.Position)
			end
		end
	end
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Called by CombatService:StrikeRequest when a ThiefNPC part is hit.
function ThiefService:Interrupt(thiefId: string)
	local entry = _activeThieves[thiefId]
	if not entry or entry.interrupted then return end

	entry.interrupted = true

	-- Drop the helmet at the thief's current position.
	if entry.heldHelmet and entry.heldHelmet.Parent then
		for _, child in entry.heldHelmet:GetChildren() do
			if child:IsA("WeldConstraint") then
				child:Destroy()
			end
		end
		entry.heldHelmet.Anchored = false
		entry.heldHelmet = nil
	end

	-- Ragdoll.
	local humanoid = entry.model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.PlatformStand = true
	end

	-- After ragdoll duration: restore, set Roam state, clear interrupt.
	task.delay(Constants.ThiefRagdollDuration, function()
		local e = _activeThieves[thiefId]
		if not e then return end

		local h = e.model:FindFirstChildOfClass("Humanoid")
		if h then
			h.PlatformStand = false
		end

		e.targetVehicleId       = nil
		e.state                 = Enums.NPCState.Roam
		e.retargetCooldownUntil = tick() + Constants.ThiefRetargetCooldown
		e.interrupted           = false  -- allow behavior tree to resume
	end)
end

return ThiefService
