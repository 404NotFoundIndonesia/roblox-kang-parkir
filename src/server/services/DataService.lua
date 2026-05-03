-- DataStore key format : "Player_[UserId]"   e.g. "Player_123456789"
-- ProfileStore scope   : "KangParkir_v1"
-- Schema change policy : bump scope to "KangParkir_v2" — existing data is NOT migrated.

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local DataStoreService    = game:GetService("DataStoreService")

local Knit           = require(ReplicatedStorage.Shared.Knit)
local Constants      = require(ReplicatedStorage.Shared.Constants)
local Remotes        = require(ReplicatedStorage.Shared.Remotes)
local ProfileService = require(ServerScriptService.ServerPackages.ProfileService)

-- Matches Types.PlayerData; all fields at their zero/empty defaults.
local DEFAULT_DATA = {
	BankedEarnings = 0,
	SkillTree = {
		WhistleLevel  = 0,
		StrengthLevel = 0,
		SpeedLevel    = 0,
		StaminaLevel  = 0,
	},
	OwnedCosmetics  = {},
	OwnedGamepasses = {},
	TotalSessions   = 0,
	Stats = {
		ThievesInterrupted = 0,
		RivalsRagdolled    = 0,
		TotalParked        = 0,
	},
	SchemaVersion = 1,
}

local DataService = Knit.CreateService({ Name = "DataService" })

local _profileStore: any       = nil
local _profiles: { [number]: any } = {}   -- [userId] -> Profile
local _leaderboardStore: any   = nil
local _leaderboardCache: { data: { { name: string, value: number } }, timestamp: number }? = nil

-- ── Initialisation ────────────────────────────────────────────────────────────

function DataService:KnitInit()
	if RunService:IsStudio() then
		-- Prevent test sessions from polluting the live DataStore.
		ProfileService.MockDataStoreEnabled = true
	end

	_profileStore     = ProfileService.GetProfileStore("KangParkir_v1", DEFAULT_DATA)
	_leaderboardStore = DataStoreService:GetOrderedDataStore("BankedEarnings_Leaderboard")
end

function DataService:KnitStart()
	Players.PlayerAdded:Connect(function(player)
		self:_LoadProfile(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		local profile = _profiles[player.UserId]
		if profile then
			profile:Release()
			_profiles[player.UserId] = nil
		end
	end)

	-- Handle players already in-game when the service boots (avoids a race window).
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:_LoadProfile(player)
		end)
	end

	-- Explicit auto-save loop (ProfileService also auto-saves internally;
	-- this ensures saves on the cadence specified in Constants).
	task.spawn(function()
		while true do
			task.wait(Constants.BankAutoSaveInterval)
			for _, profile in _profiles do
				if profile:IsActive() then
					profile:Save()
				end
			end
		end
	end)

	-- Pre-warm leaderboard cache so RemoteEvent handlers never yield on it.
	task.spawn(function()
		while true do
			self:GetLeaderboardTop10()
			task.wait(Constants.LeaderboardCacheInterval)
		end
	end)
end

-- ── Private ───────────────────────────────────────────────────────────────────

function DataService:_LoadProfile(player: Player)
	local profile = _profileStore:LoadProfileAsync("Player_" .. player.UserId)

	if profile == nil then
		-- ProfileService returns nil when it cannot acquire a session lock
		-- (e.g. DataStore outage or another server still holds the session).
		player:Kick("Data failed to load. Rejoin.")
		return
	end

	-- Player left during async load; release immediately so no session leaks.
	if not player:IsDescendantOf(game) then
		profile:Release()
		return
	end

	profile:AddUserId(player.UserId)
	profile:Reconcile() -- fills in any keys missing from DEFAULT_DATA

	-- Fires when ProfileService forcibly ends the session (e.g. duplicate login).
	profile:ListenToRelease(function()
		_profiles[player.UserId] = nil
		player:Kick("Your data session was released. Please rejoin.")
	end)

	_profiles[player.UserId] = profile
end

-- ── Public API (called by other server-side services) ─────────────────────────

-- Returns nil while the profile is still loading; callers must guard for nil.
function DataService:GetProfile(player: Player): any
	return _profiles[player.UserId]
end

-- Adds amount to BankedEarnings and notifies the client HUD.
-- Also writes to OrderedDataStore for the leaderboard (background, non-blocking).
function DataService:AddBankedEarnings(player: Player, amount: number)
	if amount <= 0 then return end
	local profile = _profiles[player.UserId]
	if not profile or not profile:IsActive() then return end

	profile.Data.BankedEarnings += amount

	-- Keep the leaderboard store in sync without blocking this call.
	task.spawn(function()
		pcall(
			_leaderboardStore.SetAsync,
			_leaderboardStore,
			"Player_" .. player.UserId,
			profile.Data.BankedEarnings
		)
	end)

	-- Notify client: arg is new BankedEarnings total so HUDController can
	-- update the banked label.
	Remotes.PayoutReceived:FireClient(player, profile.Data.BankedEarnings)
end

-- Deducts amount from BankedEarnings if sufficient funds exist.
-- Returns true on success, false if balance is insufficient (no deduction made).
function DataService:DeductBankedEarnings(player: Player, amount: number): boolean
	local profile = _profiles[player.UserId]
	if not profile or not profile:IsActive() then return false end

	if profile.Data.BankedEarnings >= amount then
		profile.Data.BankedEarnings -= amount
		return true
	end
	return false
end

-- Returns top-10 BankedEarnings from OrderedDataStore.
-- IMPORTANT: this function yields on the first call and after cache expiry.
-- Do NOT call it from inside a RemoteEvent handler — use the pre-warmed cache
-- by calling it only from background tasks (KnitStart does this automatically).
function DataService:GetLeaderboardTop10(): { { name: string, value: number } }
	local now = os.clock()

	if _leaderboardCache ~= nil
		and (now - _leaderboardCache.timestamp) < Constants.LeaderboardCacheInterval
	then
		return _leaderboardCache.data
	end

	local result: { { name: string, value: number } } = {}

	local ok, pages = pcall(function()
		return _leaderboardStore:GetSortedAsync(false, 10)
	end)

	if ok and pages then
		local ok2, pageData = pcall(function()
			return pages:GetCurrentPage()
		end)

		if ok2 then
			for _, entry in ipairs(pageData) do
				local displayName = "[unknown]"
				local uid = tonumber(tostring(entry.key):match("%d+"))
				if uid then
					pcall(function()
						displayName = Players:GetNameFromUserIdAsync(uid)
					end)
				end
				table.insert(result, { name = displayName, value = entry.value })
			end
		end
	end

	_leaderboardCache = { data = result, timestamp = now }
	return result
end

return DataService
