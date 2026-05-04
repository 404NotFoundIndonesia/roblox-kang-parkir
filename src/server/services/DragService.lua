-- DragService manages the server-side vehicle drag mechanic (Street Tetris).
--
-- Flow per vehicle:
--   DragStart  → validate state/ownership → create AlignPosition + AlignOrientation
--                constraints between vehicle PrimaryPart and an invisible drag-handle Part.
--   DragPositionUpdate (unreliable) → move drag handle to client's desired CFrame.
--   DragConfirm → validate zone bounds → destroy constraints → anchor vehicle → payout.
--   Heartbeat   → tip-over detection → ReturnToTraffic + penalty + domino chain.
--
-- ForceRelease(player) is exposed for CombatService (ragdoll interrupts active drags).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService        = game:GetService("RunService")

local Knit      = require(ReplicatedStorage.Shared.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Enums     = require(ReplicatedStorage.Shared.Enums)
local Remotes   = require(ReplicatedStorage.Shared.Remotes)

local DragService = Knit.CreateService({ Name = "DragService" })

type DragEntry = {
	player        : Player,
	handle        : Part,
	alignPos      : AlignPosition,
	alignOri      : AlignOrientation,
	vehicleAttach : Attachment,
	handleAttach  : Attachment,
	vehicleType   : string,
	startTime     : number,
}

local _activeDrags: { [string]: DragEntry } = {}
local _pendingQTE:  { [string]: { player: Player, sequence: { number } } } = {}

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function getVehicleService()
	local ok, svc = pcall(Knit.GetService, Knit, "VehicleService")
	return ok and svc or nil
end

local function getZoneService()
	local ok, svc = pcall(Knit.GetService, Knit, "ZoneService")
	return ok and svc or nil
end

local function getEconomyService()
	local ok, svc = pcall(Knit.GetService, Knit, "EconomyService")
	return ok and svc or nil
end

-- Destroy constraints + handle; does NOT change vehicle state.
function DragService:_TeardownDrag(vehicleId: string)
	local drag = _activeDrags[vehicleId]
	if not drag then return end

	pcall(function()
		drag.alignPos:Destroy()
		drag.alignOri:Destroy()
		drag.vehicleAttach:Destroy()
		drag.handleAttach:Destroy()
		drag.handle:Destroy()
	end)

	_activeDrags[vehicleId] = nil
end

-- Build an anchored invisible part used as the AlignPosition/Orientation target.
local function createHandle(cf: CFrame): Part
	local p = Instance.new("Part")
	p.Name        = "DragHandle"
	p.Size        = Vector3.new(0.1, 0.1, 0.1)
	p.Anchored    = true
	p.CanCollide  = false
	p.Transparency = 1
	p.CastShadow  = false
	p.CFrame      = cf
	p.Parent      = workspace
	return p
end

-- Build both constraints; returns them plus the two attachments.
local function createConstraints(primaryPart: BasePart, handle: Part)
	local vAttach = Instance.new("Attachment")
	vAttach.Name   = "DragVehicleAttach"
	vAttach.Parent = primaryPart

	local hAttach = Instance.new("Attachment")
	hAttach.Name   = "DragHandleAttach"
	hAttach.Parent = handle

	local alignPos = Instance.new("AlignPosition") :: AlignPosition
	alignPos.Name            = "DragAlignPos"
	alignPos.Attachment0     = vAttach
	alignPos.Attachment1     = hAttach
	alignPos.MaxForce        = 10000
	alignPos.Responsiveness  = 50
	alignPos.RigidityEnabled = false
	alignPos.Parent          = primaryPart

	local alignOri = Instance.new("AlignOrientation") :: AlignOrientation
	alignOri.Name            = "DragAlignOri"
	alignOri.Attachment0     = vAttach
	alignOri.Attachment1     = hAttach
	alignOri.MaxTorque       = 10000
	alignOri.Responsiveness  = 25
	alignOri.RigidityEnabled = false
	alignOri.Parent          = primaryPart

	return alignPos, alignOri, vAttach, hAttach
end

-- Unanchor all BaseParts in a model.
local function unanchorModel(model: Model)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			(part :: BasePart).Anchored = false
		end
	end
end

-- Set collision group on all descendant BaseParts.
local function setCollisionGroup(model: Model, groupName: string)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			(part :: BasePart).CollisionGroup = groupName
		end
	end
end

-- ── Initialisation ────────────────────────────────────────────────────────────

function DragService:KnitStart()
	-- DragStart: client requests to begin dragging a vehicle.
	Remotes.DragStart:Connect(function(player: Player, vehicleId: string)
		self:_HandleDragStart(player, vehicleId)
	end)

	-- DragPositionUpdate: unreliable high-freq position updates from dragging client.
	Remotes.DragPositionUpdate:Connect(function(player: Player, vehicleId: string, desiredCFrame: CFrame)
		self:_HandleDragPositionUpdate(player, vehicleId, desiredCFrame)
	end)

	-- DragConfirm: client finalizes placement.
	Remotes.DragConfirm:Connect(function(player: Player, vehicleId: string, desiredCFrame: CFrame)
		self:_HandleDragConfirm(player, vehicleId, desiredCFrame)
	end)

	-- QTEResult: Supercar quality bonus (P2).
	Remotes.QTEResult:Connect(function(player: Player, vehicleId: string, success: boolean)
		self:_HandleQTEResult(player, vehicleId, success)
	end)

	-- Heartbeat tip-over detection.
	RunService.Heartbeat:Connect(function()
		self:_CheckTipOvers()
	end)
end

-- ── Handlers ─────────────────────────────────────────────────────────────────

function DragService:_HandleDragStart(player: Player, vehicleId: string)
	local VehicleService = getVehicleService()
	if not VehicleService then return end

	-- 1. State must be AtEntrance.
	local state = VehicleService:GetState(vehicleId)
	if state ~= Enums.VehicleState.AtEntrance then
		Remotes.DragStartResult:FireClient(player, vehicleId, false, "NOT_AT_ENTRANCE")
		return
	end

	-- 2. Player must own the zone that this vehicle arrived at.
	local ZoneService = getZoneService()
	if ZoneService then
		local zone = ZoneService:GetPlayerZone(player)
		if not zone then
			Remotes.DragStartResult:FireClient(player, vehicleId, false, "NOT_OWNER")
			return
		end
		-- Confirm the vehicle is at the entrance of THIS player's zone.
		local allVehicles = VehicleService:GetAllVehicles()
		local vehicleData = allVehicles[vehicleId]
		if vehicleData and vehicleData.aggroPlayer ~= player then
			Remotes.DragStartResult:FireClient(player, vehicleId, false, "NOT_OWNER")
			return
		end
	end

	-- 3. No concurrent drag on the same vehicle.
	if _activeDrags[vehicleId] then
		Remotes.DragStartResult:FireClient(player, vehicleId, false, "ALREADY_DRAGGED")
		return
	end

	-- 4. Retrieve vehicle data.
	local allVehicles = VehicleService:GetAllVehicles()
	local vehicleData = allVehicles[vehicleId]
	if not vehicleData or not vehicleData.model or not vehicleData.model.PrimaryPart then
		Remotes.DragStartResult:FireClient(player, vehicleId, false, "INVALID_VEHICLE")
		return
	end

	local model       = vehicleData.model
	local primaryPart = model.PrimaryPart :: BasePart

	-- 5. Transition state, unanchor, apply collision group.
	VehicleService:SetDragging(vehicleId, player)
	unanchorModel(model)
	setCollisionGroup(model, "DraggedVehicles")

	-- 6. Create drag handle + constraints.
	local handle                              = createHandle(primaryPart.CFrame)
	local alignPos, alignOri, vAttach, hAttach = createConstraints(primaryPart, handle)

	_activeDrags[vehicleId] = {
		player        = player,
		handle        = handle,
		alignPos      = alignPos,
		alignOri      = alignOri,
		vehicleAttach = vAttach,
		handleAttach  = hAttach,
		vehicleType   = vehicleData.vehicleType,
		startTime     = os.clock(),
	}

	Remotes.DragStartResult:FireClient(player, vehicleId, true)
end

function DragService:_HandleDragPositionUpdate(player: Player, vehicleId: string, desiredCFrame: CFrame)
	local drag = _activeDrags[vehicleId]
	if not drag or drag.player ~= player then return end

	-- Sanity-clamp: reject absurd positions (> 2000 studs from origin).
	if desiredCFrame.Position.Magnitude > 2000 then return end

	drag.handle.CFrame = desiredCFrame
end

function DragService:_HandleDragConfirm(player: Player, vehicleId: string, desiredCFrame: CFrame)
	local drag = _activeDrags[vehicleId]
	if not drag or drag.player ~= player then return end

	-- Validate position is inside the player's zone.
	local ZoneService = getZoneService()
	if ZoneService then
		local zone = ZoneService:GetPlayerZone(player)
		if zone and not ZoneService:IsInZone(zone, desiredCFrame.Position) then
			Remotes.DragStartResult:FireClient(player, vehicleId, false, "OUT_OF_BOUNDS")
			-- Drag continues — player tries again from current position.
			return
		end
	end

	local VehicleService = getVehicleService()
	if not VehicleService then return end

	-- Tear down physics setup BEFORE anchoring.
	local vehicleType = drag.vehicleType
	self:_TeardownDrag(vehicleId)

	-- Park the vehicle.
	VehicleService:SetParked(vehicleId, player, desiredCFrame)

	local allVehicles = VehicleService:GetAllVehicles()
	local vehicleData = allVehicles[vehicleId]
	if vehicleData then
		setCollisionGroup(vehicleData.model, "ParkedVehicles")
	end

	-- Alignment bonus.
	local alignBonus = self:_ComputeAlignmentBonus(vehicleId, desiredCFrame, VehicleService)

	-- Payout via EconomyService — skip if vehicle was penalized (e.g. spike-stripped mid-drag).
	if not VehicleService:IsPenalized(vehicleId) then
		local EconomyService = getEconomyService()
		if EconomyService then
			local multiplier = 0
			if EconomyService.GetEventMultiplier then
				multiplier = EconomyService:GetEventMultiplier()
			end
			local payout = EconomyService:CalculatePayout(vehicleType, alignBonus, multiplier, 0)
			EconomyService:AddPayout(player, payout)
		end
	end

	-- Fire QTE prompt for Supercar (P2).
	if vehicleType == "Supercar" then
		local sequence = { math.random(1, 3), math.random(1, 3), math.random(1, 3) }
		-- Store expected sequence so QTEResult can validate.
		-- _pendingQTE is set only if EconomyService is available (payout is finalized there).
		_pendingQTE[vehicleId] = { player = player, sequence = sequence }
		Remotes.QTEPrompt:FireClient(player, vehicleId, sequence)
	end
end

function DragService:_HandleQTEResult(player: Player, vehicleId: string, success: boolean)
	local entry = _pendingQTE[vehicleId]
	if not entry or entry.player ~= player then return end
	_pendingQTE[vehicleId] = nil

	if not success then
		-- Halve the last payout for this player (apply penalty).
		local EconomyService = getEconomyService()
		if EconomyService then
			local base = Constants.VehicleBasePayouts["Supercar"] or 100
			EconomyService:ApplyPenalty(player, math.floor(base * 0.5))
		end
	end
end

-- ── Tip-Over Detection ────────────────────────────────────────────────────────

function DragService:_CheckTipOvers()
	local VehicleService = getVehicleService()
	if not VehicleService then return end

	for vehicleId, drag in _activeDrags do
		local allVehicles = VehicleService:GetAllVehicles()
		local vehicleData = allVehicles and allVehicles[vehicleId]
		if not vehicleData or not vehicleData.model or not vehicleData.model.PrimaryPart then
			continue
		end

		local primaryPart = vehicleData.model.PrimaryPart :: BasePart
		local angVelMag   = primaryPart.AssemblyAngularVelocity.Magnitude

		if angVelMag > Constants.TipOverThreshold then
			local player    = drag.player
			local vehicleType = drag.vehicleType

			-- Tear down constraints — vehicle physics simulate freely.
			self:_TeardownDrag(vehicleId)
			VehicleService:ReturnToTraffic(vehicleId)

			-- Penalty.
			local EconomyService = getEconomyService()
			if EconomyService then
				local basePayout = Constants.VehicleBasePayouts[vehicleType] or 10
				local penalty    = math.floor(basePayout * Constants.TipOverPenaltyPct)
				EconomyService:ApplyPenalty(player, penalty)
				Remotes.PenaltyApplied:FireClient(player, penalty, EconomyService:GetUnbanked(player))
			end

			-- Domino check: dislodge nearby parked vehicles.
			self:_DominoCheck(primaryPart.Position, VehicleService)
		end
	end
end

function DragService:_DominoCheck(origin: Vector3, VehicleService: any)
	local params = OverlapParams.new()
	params.FilterType               = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = CollectionService:GetTagged("VehicleHitbox")

	local parts = workspace:GetPartBoundsInRadius(origin, Constants.TipOverDominoRadius, params)
	for _, part in ipairs(parts) do
		local hitVehicleId = part:GetAttribute("VehicleId") :: string?
		if not hitVehicleId then continue end
		local allVehicles = VehicleService:GetAllVehicles()
		local data = allVehicles and allVehicles[hitVehicleId]
		if not data or data.state ~= Enums.VehicleState.Parked then continue end
		local pp = data.model and data.model.PrimaryPart :: BasePart?
		if pp then
			pp:ApplyImpulse(Vector3.new(0, 200, 0))
		end
	end
end

-- ── Alignment Bonus ───────────────────────────────────────────────────────────

function DragService:_ComputeAlignmentBonus(vehicleId: string, cf: CFrame, VehicleService: any): number
	local allVehicles = VehicleService:GetAllVehicles()
	local vehicleData = allVehicles and allVehicles[vehicleId]
	if not vehicleData or not vehicleData.model or not vehicleData.model.PrimaryPart then
		return 0
	end

	local thisLook = cf.LookVector
	local size     = (vehicleData.model.PrimaryPart :: BasePart).Size

	local params = OverlapParams.new()
	params.FilterType               = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = CollectionService:GetTagged("VehicleHitbox")

	local parts = workspace:GetPartBoundsInBox(cf, size * 1.2, params)
	local aligned = 0
	for _, part in ipairs(parts) do
		local otherId = part:GetAttribute("VehicleId") :: string?
		if not otherId or otherId == vehicleId then continue end
		local otherData = allVehicles[otherId]
		if not otherData or otherData.state ~= Enums.VehicleState.Parked then continue end
		local otherPP = otherData.model and otherData.model.PrimaryPart :: BasePart?
		if not otherPP then continue end
		local dot = thisLook:Dot(otherPP.CFrame.LookVector)
		if dot >= Constants.AlignmentDotThreshold then
			aligned += 1
		end
	end
	return math.min(aligned * 5, Constants.AlignmentBonusMax)
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Cancel an active drag on behalf of a player (called by CombatService on ragdoll).
function DragService:ForceRelease(player: Player)
	for vehicleId, drag in _activeDrags do
		if drag.player == player then
			self:_TeardownDrag(vehicleId)
			local VehicleService = getVehicleService()
			if VehicleService then
				VehicleService:ReturnToTraffic(vehicleId)
			end
			Remotes.DragStartResult:FireClient(player, vehicleId, false, "FORCE_RELEASED")
			return
		end
	end
end

return DragService
