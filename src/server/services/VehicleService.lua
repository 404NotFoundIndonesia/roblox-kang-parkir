-- VehicleService owns the authoritative state machine for every vehicle on the server.
--
-- State transitions:
--   Traffic   → Aggroed  (WhistleService:SetAggro)
--   Aggroed   → Traffic  (ClearAggro / ReturnToTraffic)
--   Aggroed   → AtEntrance (arrived at zone entrance)
--   AtEntrance→ Dragging  (DragService:SetDragging, cancels entrance timeout)
--   AtEntrance→ Traffic   (entrance timeout fires)
--   Dragging  → Parked    (DragService:DragConfirm success)
--   Dragging  → Traffic   (DragService tip-over)
--   Parked    → Traffic   (ZoneService trespass eject)
--   Any       → Damaged   (spike strip hit)
--   Any       → destroyed (vehicle touches TrafficDespawnNode)
--
-- GetAllVehicles() is exposed for ZoneService's trespass check (§3).

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local PathfindingService  = game:GetService("PathfindingService")
local RunService          = game:GetService("RunService")

local Knit      = require(ReplicatedStorage.Shared.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Enums     = require(ReplicatedStorage.Shared.Enums)

type VehicleEntry = {
	model                 : Model,
	vehicleType           : string,
	state                 : string,
	ownerPlayer           : Player?,
	aggroPlayer           : Player?,
	entranceTimeoutThread : thread?,
}

local VehicleService = Knit.CreateService({ Name = "VehicleService" })

local _vehicles: { [string]: VehicleEntry }  = {}
local _isPenalized: { [string]: boolean }    = {}
local _navGenerations: { [string]: number }  = {}  -- incremented to cancel old nav coroutines

-- ── Node finders (lazy, map may not exist at startup) ─────────────────────────

local function getDespawnNode(): BasePart?
	local map   = workspace:FindFirstChild("Map")
	local nodes = map and map:FindFirstChild("Nodes")
	return nodes and nodes:FindFirstChild("TrafficDespawnNode") :: BasePart?
end

local function getZoneEntrance(player: Player): Vector3?
	-- Lazily resolve ZoneService to find the player's zone entrance marker.
	local ok, ZoneService = pcall(Knit.GetService, Knit, "ZoneService")
	if not ok or not ZoneService then return nil end

	local zone = ZoneService:GetPlayerZone(player)
	if not zone then return nil end

	-- STUDIO_SETUP §6.2 creates a child Part named "EntranceMarker" on each zone.
	local marker = zone:FindFirstChild("EntranceMarker")
	return marker and (marker :: BasePart).Position or zone.Position
end

-- ── Model helpers ─────────────────────────────────────────────────────────────

local function setNetworkOwnerServer(model: Model)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") and not (part :: BasePart).Anchored then
			pcall((part :: BasePart).SetNetworkOwner, part :: BasePart, nil)
		end
	end
end

local function anchorModel(model: Model)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			(part :: BasePart).Anchored = true
		end
	end
end

local function unanchorModel(model: Model)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			(part :: BasePart).Anchored = false
		end
	end
	setNetworkOwnerServer(model)
end

-- ── Navigation (coroutine-based, generation-guarded) ─────────────────────────

-- Starts a coroutine that navigates the vehicle toward targetPos.
-- Increments the generation counter so any older coroutine for the same
-- vehicle stops itself as soon as it checks.
-- onArrival fires once the final waypoint is reached (if still same gen).
function VehicleService:_NavigateTo(vehicleId: string, targetPos: Vector3, onArrival: (() -> ())?)
	local gen = (_navGenerations[vehicleId] or 0) + 1
	_navGenerations[vehicleId] = gen

	task.spawn(function()
		local vehicleData = _vehicles[vehicleId]
		if not vehicleData then return end

		local model = vehicleData.model
		if not model or not model.PrimaryPart then return end

		local humanoid  = model:FindFirstChildOfClass("Humanoid")
		local primaryPart = model.PrimaryPart :: BasePart

		-- Build the path from current position to target.
		local path = PathfindingService:CreatePath({
			AgentRadius   = 2,
			AgentHeight   = 5,
			AgentCanJump  = false,
			AgentCanClimb = false,
		})

		local ok = pcall(path.ComputeAsync, path, primaryPart.Position, targetPos)
		if not ok or path.Status ~= Enum.PathStatus.Success then
			-- Path failed; fire onArrival so callers don't hang indefinitely,
			-- but only if this gen is still active.
			if _navGenerations[vehicleId] == gen and onArrival then
				onArrival()
			end
			return
		end

		local waypoints = path:GetWaypoints()

		for _, waypoint in ipairs(waypoints) do
			if _navGenerations[vehicleId] ~= gen then return end
			if not _vehicles[vehicleId] then return end

			if humanoid then
				-- Humanoid-based movement (standard for NPC-style vehicle rigs).
				humanoid:MoveTo(waypoint.Position)
				humanoid.MoveToFinished:Wait()
			else
				-- Non-humanoid fallback: lerp PrimaryPart position each Heartbeat.
				repeat
					local delta = (waypoint.Position - primaryPart.Position)
					if delta.Magnitude < 1 then break end
					local step  = math.min(delta.Magnitude, 16 * RunService.Heartbeat:Wait())
					primaryPart.CFrame = CFrame.lookAt(
						primaryPart.Position + delta.Unit * step,
						primaryPart.Position + delta.Unit * step + delta.Unit
					)
					if _navGenerations[vehicleId] ~= gen then return end
				until (waypoint.Position - primaryPart.Position).Magnitude < 1
			end
		end

		if _navGenerations[vehicleId] ~= gen then return end
		if not _vehicles[vehicleId] then return end
		if onArrival then onArrival() end
	end)
end

-- ── Initialisation ────────────────────────────────────────────────────────────

function VehicleService:KnitStart()
	-- Watch for the TrafficDespawnNode to appear and wire up Touched detection
	-- for any vehicles already registered (handles late map load in Studio).
	-- Each vehicle connects Touched in RegisterVehicle; this is a safety net.
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Registers a freshly-spawned vehicle and starts it moving toward DespawnNode.
function VehicleService:RegisterVehicle(vehicleId: string, model: Model, vehicleType: string)
	-- Ensure server owns all physics before physics simulate.
	unanchorModel(model)

	_vehicles[vehicleId] = {
		model                 = model,
		vehicleType           = vehicleType,
		state                 = Enums.VehicleState.Traffic,
		ownerPlayer           = nil,
		aggroPlayer           = nil,
		entranceTimeoutThread = nil,
	}

	-- Tag the VehicleId on the model and its Hitbox part for spatial queries.
	model:SetAttribute("VehicleId", vehicleId)
	local hitbox = model:FindFirstChild("Hitbox")
	if hitbox then
		hitbox:SetAttribute("VehicleId", vehicleId)
	end

	-- Wire Touched on DespawnNode to destroy this vehicle when it exits the map.
	local despawnNode = getDespawnNode()
	if despawnNode and model.PrimaryPart then
		local connection: RBXScriptConnection
		connection = model.PrimaryPart.Touched:Connect(function(hit: BasePart)
			if hit == despawnNode then
				connection:Disconnect()
				self:_DestroyVehicle(vehicleId)
			end
		end)
	end

	-- Start moving toward the despawn node.
	local despawnPos = (getDespawnNode() and (getDespawnNode() :: BasePart).Position)
		or Vector3.new(0, 1, 62)   -- fallback if map not placed yet

	self:_NavigateTo(vehicleId, despawnPos, function()
		-- Arrived at end of road naturally — destroy vehicle.
		if _vehicles[vehicleId] and _vehicles[vehicleId].state == Enums.VehicleState.Traffic then
			self:_DestroyVehicle(vehicleId)
		end
	end)
end

-- Redirect the vehicle toward the given player's zone entrance.
-- If another player already had aggro, delegates to TugOfWarService.
function VehicleService:SetAggro(vehicleId: string, player: Player)
	local vehicleData = _vehicles[vehicleId]
	if not vehicleData then return end

	local prevAggroPlayer = vehicleData.aggroPlayer
	vehicleData.state       = Enums.VehicleState.Aggroed
	vehicleData.aggroPlayer = player

	-- Tug-of-War only fires when a second player claims an already-aggroed vehicle.
	if prevAggroPlayer and prevAggroPlayer ~= player then
		local ok, TugOfWarService = pcall(Knit.GetService, Knit, "TugOfWarService")
		if ok and TugOfWarService then
			TugOfWarService:StartBattle(vehicleId, prevAggroPlayer, player)
		end
	end

	local entrancePos = getZoneEntrance(player)
	if not entrancePos then return end

	self:_NavigateTo(vehicleId, entrancePos, function()
		-- Arrived at zone entrance — transition to AtEntrance.
		if _vehicles[vehicleId] and _vehicles[vehicleId].state == Enums.VehicleState.Aggroed then
			self:SetAtEntrance(vehicleId)
		end
	end)
end

-- Drop aggro: vehicle resumes its original traffic path toward DespawnNode.
function VehicleService:ClearAggro(vehicleId: string)
	local vehicleData = _vehicles[vehicleId]
	if not vehicleData then return end

	vehicleData.state       = Enums.VehicleState.Traffic
	vehicleData.aggroPlayer = nil

	local despawnPos = (getDespawnNode() and (getDespawnNode() :: BasePart).Position)
		or Vector3.new(0, 1, 62)
	self:_NavigateTo(vehicleId, despawnPos, function()
		if _vehicles[vehicleId] and _vehicles[vehicleId].state == Enums.VehicleState.Traffic then
			self:_DestroyVehicle(vehicleId)
		end
	end)
end

-- Vehicle has arrived at the zone entrance; stop movement and arm timeout.
function VehicleService:SetAtEntrance(vehicleId: string)
	local vehicleData = _vehicles[vehicleId]
	if not vehicleData then return end

	vehicleData.state = Enums.VehicleState.AtEntrance

	-- Stop Humanoid movement if present.
	local humanoid = vehicleData.model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid:MoveTo(vehicleData.model.PrimaryPart.Position)
	end

	-- Cancel any running nav coroutine so it doesn't advance to onArrival.
	local gen = (_navGenerations[vehicleId] or 0) + 1
	_navGenerations[vehicleId] = gen

	-- Timeout: if nobody starts dragging within VehicleEntranceTimeout, return to traffic.
	local thread = task.delay(Constants.VehicleEntranceTimeout, function()
		if _vehicles[vehicleId] and _vehicles[vehicleId].state == Enums.VehicleState.AtEntrance then
			self:ReturnToTraffic(vehicleId)
		end
	end)
	vehicleData.entranceTimeoutThread = thread
end

-- DragService has taken ownership; cancel the entrance timeout.
function VehicleService:SetDragging(vehicleId: string, player: Player)
	local vehicleData = _vehicles[vehicleId]
	if not vehicleData then return end

	-- Cancel entrance timeout so vehicle isn't ejected mid-drag.
	if vehicleData.entranceTimeoutThread then
		task.cancel(vehicleData.entranceTimeoutThread)
		vehicleData.entranceTimeoutThread = nil
	end

	vehicleData.state       = Enums.VehicleState.Dragging
	vehicleData.ownerPlayer = player

	-- Restore WalkSpeed so the Humanoid doesn't block drag physics.
	local humanoid = vehicleData.model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 16
	end
end

-- DragService confirmed a valid placement; anchor the vehicle.
function VehicleService:SetParked(vehicleId: string, player: Player, cf: CFrame)
	local vehicleData = _vehicles[vehicleId]
	if not vehicleData then return end

	vehicleData.state       = Enums.VehicleState.Parked
	vehicleData.ownerPlayer = player

	local model = vehicleData.model
	if model.PrimaryPart then
		model:PivotTo(cf)
	end
	anchorModel(model)
end

-- Spike strip or other damage: halt movement and void any future payout.
function VehicleService:SetDamaged(vehicleId: string)
	local vehicleData = _vehicles[vehicleId]
	if not vehicleData then return end

	vehicleData.state = Enums.VehicleState.Damaged
	_isPenalized[vehicleId] = true

	-- Cancel navigation coroutine.
	_navGenerations[vehicleId] = (_navGenerations[vehicleId] or 0) + 1

	-- Stop Humanoid if present, otherwise the vehicle model stays in place.
	local humanoid = vehicleData.model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid:MoveTo(vehicleData.model.PrimaryPart.Position)
	end

	-- Cancel entrance timeout if armed.
	if vehicleData.entranceTimeoutThread then
		task.cancel(vehicleData.entranceTimeoutThread)
		vehicleData.entranceTimeoutThread = nil
	end
end

-- Reset vehicle to Traffic and restart road navigation.
-- Called by ZoneService (trespass), DragService (tip-over), and entrance timeout.
function VehicleService:ReturnToTraffic(vehicleId: string)
	local vehicleData = _vehicles[vehicleId]
	if not vehicleData then return end

	-- Cancel entrance timeout if still running.
	if vehicleData.entranceTimeoutThread then
		task.cancel(vehicleData.entranceTimeoutThread)
		vehicleData.entranceTimeoutThread = nil
	end

	vehicleData.state       = Enums.VehicleState.Traffic
	vehicleData.aggroPlayer = nil
	vehicleData.ownerPlayer = nil

	-- Unanchor so the vehicle can move again.
	unanchorModel(vehicleData.model)

	-- Restore Humanoid WalkSpeed if present.
	local humanoid = vehicleData.model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 16
	end

	local despawnPos = (getDespawnNode() and (getDespawnNode() :: BasePart).Position)
		or Vector3.new(0, 1, 62)
	self:_NavigateTo(vehicleId, despawnPos, function()
		if _vehicles[vehicleId] and _vehicles[vehicleId].state == Enums.VehicleState.Traffic then
			self:_DestroyVehicle(vehicleId)
		end
	end)
end

-- Returns the current state string, or nil if vehicleId is unknown.
function VehicleService:GetState(vehicleId: string): string?
	local vehicleData = _vehicles[vehicleId]
	return vehicleData and vehicleData.state
end

-- Returns the full _vehicles table for ZoneService's trespass loop (§3).
-- Callers must treat the return value as read-only.
function VehicleService:GetAllVehicles(): { [string]: VehicleEntry }
	return _vehicles
end

-- Returns true if the vehicle has a damage penalty flag set.
function VehicleService:IsPenalized(vehicleId: string): boolean
	return _isPenalized[vehicleId] == true
end

-- ── Private ───────────────────────────────────────────────────────────────────

function VehicleService:_DestroyVehicle(vehicleId: string)
	local vehicleData = _vehicles[vehicleId]
	if not vehicleData then return end

	-- Cancel any running nav coroutine.
	_navGenerations[vehicleId] = (_navGenerations[vehicleId] or 0) + 1

	-- Cancel entrance timeout.
	if vehicleData.entranceTimeoutThread then
		task.cancel(vehicleData.entranceTimeoutThread)
	end

	-- Destroy the model.
	if vehicleData.model and vehicleData.model.Parent then
		vehicleData.model:Destroy()
	end

	-- Clean up state.
	_vehicles[vehicleId]    = nil
	_isPenalized[vehicleId] = nil
	_navGenerations[vehicleId] = nil

	-- Notify TrafficService so it can decrement _aliveCount.
	local ok, TrafficService = pcall(Knit.GetService, Knit, "TrafficService")
	if ok and TrafficService then
		TrafficService:OnVehicleDestroyed(vehicleId)
	end
end

return VehicleService
