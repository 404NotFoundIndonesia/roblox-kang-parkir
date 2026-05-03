local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService       = game:GetService("HttpService")
local Players           = game:GetService("Players")

local Knit      = require(ReplicatedStorage.Shared.Knit)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Enums     = require(ReplicatedStorage.Shared.Enums)

-- Vehicle types in a fixed order so weighted-random walk is deterministic.
local SPAWN_ORDER = { "Scooter", "SportBike", "FamilyCar", "AggroSUV", "Supercar" }

local TrafficService = Knit.CreateService({ Name = "TrafficService" })

local _templates: { [string]: Model }     = {}
local _aliveCount: number                 = 0
local _maxVehicles: number                = 0
local _currentSpawnWeights: { [string]: number } = {}
local _currentSpawnInterval: number       = 0
local _flashMobActive: boolean            = false

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function pickVehicleType(weights: { [string]: number }): string
	local r = math.random()
	local cumulative = 0
	for _, vehicleType in ipairs(SPAWN_ORDER) do
		cumulative += (weights[vehicleType] or 0)
		if r <= cumulative then
			return vehicleType
		end
	end
	return "Scooter" -- fallback (only reachable if weights don't sum to 1.0)
end

local function getSpawnNode(): BasePart?
	local map   = workspace:FindFirstChild("Map")
	local nodes = map and map:FindFirstChild("Nodes")
	return nodes and nodes:FindFirstChild("TrafficSpawnNode") :: BasePart?
end

local function calcMaxVehicles(): number
	local count = #Players:GetPlayers()
	return math.min(Constants.TrafficVehiclesPerPlayer * count, 40)
end

-- ── Initialisation ────────────────────────────────────────────────────────────

function TrafficService:KnitInit()
	-- Reset spawn weights / interval to defaults.
	_currentSpawnWeights  = Constants.SpawnWeights
	_currentSpawnInterval = Constants.TrafficSpawnInterval
end

function TrafficService:KnitStart()
	-- Load vehicle templates.
	local vehiclesFolder = ReplicatedStorage:FindFirstChild("Assets")
		and ReplicatedStorage.Assets:FindFirstChild("Vehicles")

	if vehiclesFolder then
		for _, vehicleType in ipairs(SPAWN_ORDER) do
			local template = vehiclesFolder:FindFirstChild(vehicleType)
			if template and template:IsA("Model") then
				_templates[vehicleType] = template
			end
		end
	end

	-- Dynamic vehicle cap: recalculate whenever player count changes.
	_maxVehicles = calcMaxVehicles()
	Players.PlayerAdded:Connect(function()
		_maxVehicles = calcMaxVehicles()
	end)
	Players.PlayerRemoving:Connect(function()
		task.defer(function()   -- defer so Players list has updated
			_maxVehicles = calcMaxVehicles()
		end)
	end)

	-- Wait for WarmUp phase, then start the spawn loop.
	task.spawn(function()
		local SessionService = Knit.GetService("SessionService")
		repeat task.wait(0.5) until SessionService:GetPhase() == Enums.SessionPhase.WarmUp

		self:_SpawnLoop()
	end)
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Called by VehicleService when a vehicle is destroyed (touched despawn node).
function TrafficService:OnVehicleDestroyed(_vehicleId: string)
	_aliveCount = math.max(0, _aliveCount - 1)
end

-- Override weights and interval for the FlashMob burst window.
function TrafficService:FlashMobBurst()
	if _flashMobActive then return end
	_flashMobActive = true

	_currentSpawnWeights  = { Scooter = Constants.FlashMobScooterWeight, SportBike = 0.05 }
	_currentSpawnInterval = Constants.TrafficFlashMobInterval

	task.delay(Constants.FlashMobDuration, function()
		self:RestoreWeights()
		_flashMobActive = false
	end)
end

-- Restore normal weights and interval. Called by EventService as a safety net.
function TrafficService:RestoreWeights()
	_currentSpawnWeights  = Constants.SpawnWeights
	_currentSpawnInterval = Constants.TrafficSpawnInterval
end

-- ── Private ───────────────────────────────────────────────────────────────────

function TrafficService:_SpawnLoop()
	local VehicleService = Knit.GetService("VehicleService")

	while true do
		task.wait(_currentSpawnInterval)

		-- Stop spawning once the shift ends.
		local SessionService = Knit.GetService("SessionService")
		local phase = SessionService:GetPhase()
		if phase == Enums.SessionPhase.PostSession then break end

		-- Respect the dynamic vehicle cap.
		if _aliveCount >= _maxVehicles then continue end

		local spawnNode = getSpawnNode()
		if not spawnNode then continue end

		local vehicleType = pickVehicleType(_currentSpawnWeights)
		local template    = _templates[vehicleType]
		if not template then continue end  -- template not yet loaded; skip this tick

		local model = template:Clone()
		model:PivotTo(spawnNode.CFrame)
		model.Parent = workspace

		local vehicleId = "V_" .. HttpService:GenerateGUID(false)
		VehicleService:RegisterVehicle(vehicleId, model, vehicleType)
		_aliveCount += 1
	end
end

return TrafficService
