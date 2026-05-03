-- ZoneService owns parking zone boundaries and per-player zone assignments.
-- It also enforces the trespassing rule: vehicles that stay in a foreign zone
-- for longer than Constants.TrespasEjectDelay seconds are returned to traffic.
--
-- Dependency note: the trespassing loop calls VehicleService:GetAllVehicles().
-- VehicleService must expose that method (implemented in §4).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Players           = game:GetService("Players")

local Knit      = require(ReplicatedStorage.Shared.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Enums     = require(ReplicatedStorage.Shared.Enums)

local ZoneService = Knit.CreateService({ Name = "ZoneService" })

local _zones: { Part }                  = {}  -- ordered list of all ParkingZone parts
local _zoneOwners: { [Part]: Player }   = {}  -- zone → owner player
local _foreignDurations: { [string]: number } = {}  -- vehicleId → seconds spent in foreign zone

-- ── Initialisation ────────────────────────────────────────────────────────────

function ZoneService:KnitStart()
	-- Collect all tagged ParkingZone parts that exist now.
	-- Tags are applied either at map load or by a startup script per STUDIO_SETUP §6.
	for _, part in CollectionService:GetTagged("ParkingZone") do
		if part:IsA("BasePart") then
			table.insert(_zones, part)
		end
	end

	-- Also pick up any zones tagged after this service boots (e.g. lazy map load).
	CollectionService:GetInstanceAddedSignal("ParkingZone"):Connect(function(part)
		if part:IsA("BasePart") then
			table.insert(_zones, part)
		end
	end)

	CollectionService:GetInstanceRemovedSignal("ParkingZone"):Connect(function(part)
		local idx = table.find(_zones, part)
		if idx then
			table.remove(_zones, idx)
		end
		_zoneOwners[part] = nil
	end)

	-- Release zone ownership when a player leaves.
	Players.PlayerRemoving:Connect(function(player)
		for zone, owner in _zoneOwners do
			if owner == player then
				_zoneOwners[zone] = nil
				-- Do not reassign; v1.0 design locks zones for the duration of a session.
				break
			end
		end
	end)

	-- Trespassing enforcement loop.
	task.spawn(function()
		self:_TrespassLoop()
	end)
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Assigns the first unoccupied zone to player. Returns nil if all zones are taken.
function ZoneService:AssignZone(player: Player): Part?
	for _, zone in _zones do
		if _zoneOwners[zone] == nil then
			_zoneOwners[zone] = player
			return zone
		end
	end
	return nil
end

-- Returns the zone owned by player, or nil if they have no zone.
function ZoneService:GetPlayerZone(player: Player): Part?
	for zone, owner in _zoneOwners do
		if owner == player then
			return zone
		end
	end
	return nil
end

-- Returns the owner of the given zone, or nil if unassigned.
function ZoneService:GetZoneOwner(zone: Part): Player?
	return _zoneOwners[zone]
end

-- AABB containment check in the zone part's local space.
-- Treats the zone Part as a box regardless of its world rotation.
function ZoneService:IsInZone(zone: Part, worldPosition: Vector3): boolean
	local localPos = zone.CFrame:PointToObjectSpace(worldPosition)
	local half     = zone.Size * 0.5
	return math.abs(localPos.X) <= half.X
		and math.abs(localPos.Y) <= half.Y
		and math.abs(localPos.Z) <= half.Z
end

-- ── Private ───────────────────────────────────────────────────────────────────

-- Every second, check whether any parked vehicle has drifted into a zone whose
-- owner is not the vehicle's aggroed player. Accumulate time; eject on threshold.
function ZoneService:_TrespassLoop()
	-- Get VehicleService once it is available (after Knit.Start resolves).
	local VehicleService = nil

	while true do
		task.wait(1)

		-- Lazy-initialise VehicleService reference.
		if not VehicleService then
			local ok, svc = pcall(Knit.GetService, Knit, "VehicleService")
			if ok and svc then
				VehicleService = svc
			else
				continue
			end
		end

		-- GetAllVehicles() returns { [vehicleId]: vehicleEntry } where each entry
		-- has fields: model, vehicleType, state, ownerPlayer, aggroPlayer.
		-- This method is exposed by VehicleService (implemented in §4).
		local allVehicles = VehicleService:GetAllVehicles()
		if not allVehicles then continue end

		for vehicleId, vehicleData in allVehicles do
			-- Only parked vehicles need trespass enforcement.
			-- Vehicles in other states are handled by their own services.
			if vehicleData.state ~= Enums.VehicleState.Parked then
				_foreignDurations[vehicleId] = nil
				continue
			end

			local aggroPlayer = vehicleData.aggroPlayer
			if not aggroPlayer then
				_foreignDurations[vehicleId] = nil
				continue
			end

			local ownerZone = self:GetPlayerZone(aggroPlayer)
			if not ownerZone then
				_foreignDurations[vehicleId] = nil
				continue
			end

			local primaryPart = vehicleData.model and vehicleData.model.PrimaryPart
			if not primaryPart then
				_foreignDurations[vehicleId] = nil
				continue
			end

			if not self:IsInZone(ownerZone, primaryPart.Position) then
				-- Vehicle is physically outside its aggro player's zone.
				local elapsed = (_foreignDurations[vehicleId] or 0) + 1
				_foreignDurations[vehicleId] = elapsed

				if elapsed >= Constants.TrespasEjectDelay then
					_foreignDurations[vehicleId] = nil
					VehicleService:ReturnToTraffic(vehicleId)
				end
			else
				-- Vehicle is back in the correct zone; reset the counter.
				_foreignDurations[vehicleId] = nil
			end
		end
	end
end

return ZoneService
