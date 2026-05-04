-- PhysicsService centralises server-side physics ownership and anchor state for vehicles.
--
-- All vehicle BaseParts must be server-owned (SetNetworkOwner(nil)) so the server drives
-- authoritative physics — never pass a Player to SetNetworkOwner for vehicles.
--
-- Call sites:
--   TrafficService._SpawnLoop  → AssignServerOwnership + AnchorModel immediately after spawn,
--                                before VehicleService:RegisterVehicle (which unanchors for traffic).
--   DragService._HandleDragStart  → UnanchorModel so the drag constraints can simulate.
--   DragService._HandleDragConfirm → AnchorModel after VehicleService:SetParked.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit = require(ReplicatedStorage.Shared.Knit)

local PhysicsService = Knit.CreateService({ Name = "PhysicsService" })

-- ── Public API ────────────────────────────────────────────────────────────────

-- Force server ownership on every unanchored BasePart in the model.
-- Must be called before physics simulate (i.e. before the model is unanchored).
function PhysicsService:AssignServerOwnership(model: Model)
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			pcall((desc :: BasePart).SetNetworkOwner, desc :: BasePart, nil)
		end
	end
end

-- Anchor every BasePart in the model so it cannot move via physics.
-- Used at vehicle spawn (safe initial state) and after a vehicle is parked.
function PhysicsService:AnchorModel(model: Model)
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			(desc :: BasePart).Anchored = true
		end
	end
end

-- Unanchor every BasePart so physics constraints (AlignPosition/Orientation)
-- can drive the model during drag.
function PhysicsService:UnanchorModel(model: Model)
	for _, desc in model:GetDescendants() do
		if desc:IsA("BasePart") then
			(desc :: BasePart).Anchored = false
		end
	end
end

function PhysicsService:KnitStart() end

return PhysicsService
