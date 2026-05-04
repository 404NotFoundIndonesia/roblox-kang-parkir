-- CosmeticController receives cosmetic state from the server and applies it locally.
--
-- CosmeticData(targetPlayer, { vestName, pitchIndex }):
--   • Stores local player's pitchIndex (used by WhistleController for SFX pitch).
--   • Applies vestName mesh to targetPlayer's character as a late-join backup
--     (server already applied it; this covers clients who joined mid-session).
--
-- DashTrailVFX(playerUserId, trailAssetName):
--   • Clones the trail template from ReplicatedStorage.Assets.Cosmetics.Trails
--     into the target player's HumanoidRootPart for the dash visual effect.
--
-- Exposes GetPitchIndex() for WhistleController to read the assigned pitch.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit    = require(ReplicatedStorage.Shared.Knit)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local CosmeticController = Knit.CreateController({ Name = "CosmeticController" })

local _localPitchIndex: number = 1

-- ── Asset helpers ─────────────────────────────────────────────────────────────

local function getTorso(character: Model): BasePart?
	return character:FindFirstChild("UpperTorso") :: BasePart?
		or character:FindFirstChild("Torso")      :: BasePart?
end

local function applyVestLocal(character: Model, vestName: string)
	local assets    = ReplicatedStorage:FindFirstChild("Assets")
	local cosmetics = assets and assets:FindFirstChild("Cosmetics")
	local vests     = cosmetics and cosmetics:FindFirstChild("Vests")
	if not vests then return end
	local template = vests:FindFirstChild(vestName)
	if not template then return end

	local torso = getTorso(character)
	if not torso then return end

	-- Already applied via server replication — skip.
	if character:FindFirstChild(vestName) then return end

	local vestPart = template:Clone()
	vestPart.Name  = vestName
	if vestPart:IsA("BasePart") then
		vestPart.CFrame = torso.CFrame
	end
	vestPart.Parent = character

	local weld  = Instance.new("WeldConstraint")
	weld.Part0  = vestPart :: BasePart
	weld.Part1  = torso
	weld.Parent = vestPart
end

-- ── KnitStart ─────────────────────────────────────────────────────────────────

function CosmeticController:KnitStart()
	local LocalPlayer = Players.LocalPlayer

	-- CosmeticData: fired on each character spawn for every player.
	Remotes.CosmeticData:Connect(function(targetPlayer: Player, data: {
		vestName:   string?,
		pitchIndex: number,
	})
		-- Store pitch index when it's the local player's data.
		if targetPlayer == LocalPlayer then
			_localPitchIndex = data.pitchIndex or 1
		end

		-- Apply vest locally (safety for late joiners; server replication usually handles this).
		local vestName = data.vestName
		if vestName then
			local char = targetPlayer.Character
			if char then
				applyVestLocal(char, vestName)
			else
				-- Character not yet spawned; apply when it does.
				local conn: RBXScriptConnection
				conn = targetPlayer.CharacterAdded:Connect(function(character)
					conn:Disconnect()
					applyVestLocal(character, vestName)
				end)
			end
		end
	end)

	-- DashTrailVFX: clone trail asset into target player's HumanoidRootPart.
	Remotes.DashTrailVFX:Connect(function(playerUserId: number, trailAssetName: string)
		local targetPlayer: Player? = nil
		for _, p in Players:GetPlayers() do
			if p.UserId == playerUserId then
				targetPlayer = p
				break
			end
		end
		if not targetPlayer then return end

		local char = targetPlayer.Character
		local hrp  = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then return end

		local assets    = ReplicatedStorage:FindFirstChild("Assets")
		local cosmetics = assets and assets:FindFirstChild("Cosmetics")
		local trails    = cosmetics and cosmetics:FindFirstChild("Trails")
		local template  = trails and trails:FindFirstChild(trailAssetName)
		if not template then return end

		-- Clone the trail container (should contain an Attachment and a Trail).
		local clone = template:Clone()
		clone.Parent = hrp
	end)
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Returns the local player's assigned whistle pitch index (1–8).
-- WhistleController uses this to compute PlaybackSpeed.
function CosmeticController:GetPitchIndex(): number
	return _localPitchIndex
end

return CosmeticController
