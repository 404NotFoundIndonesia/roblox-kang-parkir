-- ThreatController displays a directional arrow when a Thief NPC enters the
-- local player's zone.
--
-- Receives ThreatInZone (UnreliableRemoteEvent) → updates _latestThiefPos each frame.
-- A Heartbeat loop:
--   • Computes WorldToViewportPoint to decide if threat is on or off screen.
--   • Rotates ThreatArrow to point toward the threat (math.atan2).
--   • Scales ImageTransparency inversely with distance (5 studs = opaque, 25 = 0.7).
--   • Hides arrow if no event received for 2 seconds.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit    = require(ReplicatedStorage.Shared.Knit)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local ThreatController = Knit.CreateController({ Name = "ThreatController" })

local HIDE_TIMEOUT    = 2    -- seconds without event before hiding arrow
local DIST_NEAR       = 5    -- studs → fully opaque
local DIST_FAR        = 25   -- studs → 0.7 transparency
local MAX_TRANSPARENCY = 0.7

local _threatArrow:    ImageLabel?
local _lastEventTime:  number  = 0
local _latestThiefPos: Vector3? = nil

-- ── KnitStart ─────────────────────────────────────────────────────────────────

function ThreatController:KnitStart()
	local PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	local HUD       = PlayerGui:WaitForChild("HUD", 20) :: ScreenGui?
	if HUD then
		_threatArrow = HUD:FindFirstChild("ThreatArrow") :: ImageLabel?
	end

	if _threatArrow then
		_threatArrow.Visible = false
	end

	-- Cache latest threat position; arrow update happens in Heartbeat.
	Remotes.ThreatInZone:Connect(function(_thiefId: string, thiefWorldPos: Vector3)
		_lastEventTime  = os.clock()
		_latestThiefPos = thiefWorldPos
	end)

	-- ── Per-frame arrow update ────────────────────────────────────────────────

	RunService.Heartbeat:Connect(function()
		local arrow = _threatArrow
		if not arrow then return end

		if os.clock() - _lastEventTime > HIDE_TIMEOUT then
			arrow.Visible = false
			return
		end

		local thiefPos = _latestThiefPos
		if not thiefPos then return end

		-- Transparency based on distance to threat.
		local char = Players.LocalPlayer.Character
		local hrp  = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp then
			local dist = (thiefPos - hrp.Position).Magnitude
			local t    = math.clamp((dist - DIST_NEAR) / (DIST_FAR - DIST_NEAR), 0, 1)
			arrow.ImageTransparency = t * MAX_TRANSPARENCY
		end

		-- Screen direction.
		local camera       = workspace.CurrentCamera
		local viewportSize = camera.ViewportSize
		local screenPos, _ = camera:WorldToViewportPoint(thiefPos)

		local cx = viewportSize.X * 0.5
		local cy = viewportSize.Y * 0.5

		-- Detect off-screen: behind camera (z < 0) or outside viewport bounds.
		local uvX     = screenPos.X / viewportSize.X
		local uvY     = screenPos.Y / viewportSize.Y
		local offScreen = screenPos.Z < 0
			or uvX < 0 or uvX > 1
			or uvY < 0 or uvY > 1

		-- When behind camera, flip X so the arrow still points to the correct edge.
		local dx = if screenPos.Z < 0 then cx - screenPos.X else screenPos.X - cx
		local dy = screenPos.Y - cy
		local angle = math.deg(math.atan2(dy, dx))

		arrow.Rotation = angle
		arrow.Visible  = true

		-- Position: if off-screen, clamp arrow to viewport edge; else track screen pos.
		if offScreen then
			-- Arrow sits at the edge in the computed direction; keep position fixed.
			-- (Typically the arrow is anchored to a corner; Rotation alone is enough.)
		end
	end)
end

return ThreatController
