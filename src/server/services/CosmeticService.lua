-- CosmeticService applies owned cosmetics to player characters on each spawn.
--
-- On character spawn:
--   1. Read OwnedCosmetics from DataService profile.
--   2. Find equipped vest (first entry matching "Vest_*"). Clone from
--      ReplicatedStorage.Assets.Cosmetics.Vests, parent into character, WeldConstraint to torso.
--   3. Fire Remotes.CosmeticData:FireAllClients(player, { vestName, pitchIndex }) so all
--      clients (including late joiners) know the cosmetic state and unique whistle pitch.
--
-- Pitch indices 1–8 are assigned sequentially on join (cycling after 8 players).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Knit    = require(ReplicatedStorage.Shared.Knit)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local CosmeticService = Knit.CreateService({ Name = "CosmeticService" })

local PITCH_MAX = 8

local _pitchAssignments: { [number]: number } = {}
local _pitchCounter: number = 0

-- ── Asset helpers ─────────────────────────────────────────────────────────────

local function getVestsFolder(): Folder?
	local assets    = ReplicatedStorage:FindFirstChild("Assets")
	local cosmetics = assets and assets:FindFirstChild("Cosmetics")
	return cosmetics and cosmetics:FindFirstChild("Vests") :: Folder?
end

-- Returns the first vest ID in OwnedCosmetics, or nil if none.
local function getEquippedVest(profile): string?
	if not profile then return nil end
	for _, id in ipairs(profile.Data.OwnedCosmetics) do
		if string.match(id, "^Vest_") then
			return id
		end
	end
	return nil
end

-- Finds the torso part regardless of rig type (R15 UpperTorso / R6 Torso).
local function getTorso(character: Model): BasePart?
	return character:FindFirstChild("UpperTorso") :: BasePart?
		or character:FindFirstChild("Torso")      :: BasePart?
end

-- ── Vest application ──────────────────────────────────────────────────────────

local function applyVest(character: Model, vestName: string)
	local vestsFolder = getVestsFolder()
	if not vestsFolder then return end
	local template = vestsFolder:FindFirstChild(vestName)
	if not template then return end

	local torso = getTorso(character)
	if not torso then return end

	-- Idempotent: skip if already applied (re-spawn guard).
	if character:FindFirstChild(vestName) then return end

	local vestPart = template:Clone()
	vestPart.Name = vestName

	if vestPart:IsA("BasePart") then
		vestPart.CFrame = torso.CFrame
	end
	vestPart.Parent = character

	local weld   = Instance.new("WeldConstraint")
	weld.Part0   = vestPart :: BasePart
	weld.Part1   = torso
	weld.Parent  = vestPart
end

-- ── Per-character handler ─────────────────────────────────────────────────────

function CosmeticService:_OnCharacterAdded(player: Player, character: Model)
	-- Wait one frame so the character hierarchy is fully assembled.
	task.defer(function()
		if not character.Parent then return end

		local profile: any = nil
		local ok, DataService = pcall(Knit.GetService, Knit, "DataService")
		if ok and DataService then
			profile = DataService:GetProfile(player)
		end

		local vestName = getEquippedVest(profile)
		if vestName then
			applyVest(character, vestName)
		end

		local pitchIndex = _pitchAssignments[player.UserId] or 1
		Remotes.CosmeticData:FireAllClients(player, {
			vestName   = vestName,
			pitchIndex = pitchIndex,
		})
	end)
end

-- ── Initialisation ────────────────────────────────────────────────────────────

function CosmeticService:KnitStart()
	local function onPlayerAdded(player: Player)
		-- Assign a unique pitch index (1–8, cycling).
		if not _pitchAssignments[player.UserId] then
			_pitchCounter += 1
			_pitchAssignments[player.UserId] = ((_pitchCounter - 1) % PITCH_MAX) + 1
		end

		player.CharacterAdded:Connect(function(character)
			self:_OnCharacterAdded(player, character)
		end)

		-- Handle character that spawned before this service connected.
		if player.Character then
			self:_OnCharacterAdded(player, player.Character)
		end
	end

	Players.PlayerAdded:Connect(onPlayerAdded)

	Players.PlayerRemoving:Connect(function(player)
		_pitchAssignments[player.UserId] = nil
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Grants a cosmetic item. Persistence is handled by DataService (OwnedCosmetics list).
-- The vest will appear on next character spawn.
function CosmeticService:GrantBannerReward(_memberUserId: number, _syndicateId: string)
	-- Placeholder for SyndicateService (section 15) to call.
	-- Actual logic: DataService:GetProfile → push cosmetic ID → refresh on next spawn.
end

return CosmeticService
