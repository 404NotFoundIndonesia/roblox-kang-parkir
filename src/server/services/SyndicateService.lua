-- SyndicateService manages player syndicates (groups that share an adjacency payout bonus).
--
-- DataStores:
--   SyndicateStore  — key: syndicateId → { name, members, weeklyEarnings }
--                     key: "__meta"    → { lastResetTimestamp, allSyndicateIds }
--   SyndicateIndex  — key: "p_<userId>" → syndicateId
--
-- In-memory cache mirrors DataStore; persisted on PlayerRemoving and every 5 minutes.
--
-- Adjacency bonus: EconomyService calls GetAdjacentBonus(player) → boolean.
--   Returns true if any online syndicate member's zone is within 0.5 studs of the player's zone.
--   If true, EconomyService multiplies the payout by 1.05 and calls RecordEarning.
--
-- Weekly reset: on first KnitStart after Monday 00:00 UTC, top-3 syndicates by weeklyEarnings
--   receive CosmeticService:GrantBannerReward per member; all earnings then reset to 0.

local DataStoreService  = game:GetService("DataStoreService")
local HttpService        = game:GetService("HttpService")
local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local Knit    = require(ReplicatedStorage.Shared.Knit)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local SyndicateService = Knit.CreateService({ Name = "SyndicateService" })

local MAX_MEMBERS        = 8
local ADJACENT_TOLERANCE = 0.5  -- studs
local SAVE_INTERVAL      = 300  -- seconds between background saves
local META_KEY           = "__meta"

local SyndicateStore = DataStoreService:GetDataStore("SyndicateStore")
local SyndicateIndex = DataStoreService:GetDataStore("SyndicateIndex")

type SyndicateData = {
	name:           string,
	members:        { number },
	weeklyEarnings: number,
}

type MetaData = {
	lastResetTimestamp: number,
	allSyndicateIds:    { string },
}

local _syndicates:   { [string]: SyndicateData } = {}
local _playerIndex:  { [number]: string? }       = {}
local _meta:         MetaData                    = { lastResetTimestamp = 0, allSyndicateIds = {} }

-- ── Math helpers ──────────────────────────────────────────────────────────────

-- Returns Monday 00:00 UTC timestamp for the current week.
local function getLastMondayTimestamp(): number
	local now = os.time()
	local t   = os.date("!*t", now) :: any  -- UTC table
	-- wday: 1=Sun, 2=Mon … 7=Sat
	local daysFromMonday   = (t.wday - 2 + 7) % 7
	local secondsFromMonday = daysFromMonday * 86400 + t.hour * 3600 + t.min * 60 + t.sec
	return now - secondsFromMonday
end

-- AABB gap between two axis-aligned zone parts. Returns studs of separation.
local function zoneGap(zA: BasePart, zB: BasePart): number
	local pA, hA = zA.Position, zA.Size * 0.5
	local pB, hB = zB.Position, zB.Size * 0.5
	local gx = math.max(0, math.abs(pA.X - pB.X) - (hA.X + hB.X))
	local gy = math.max(0, math.abs(pA.Y - pB.Y) - (hA.Y + hB.Y))
	local gz = math.max(0, math.abs(pA.Z - pB.Z) - (hA.Z + hB.Z))
	return math.sqrt(gx * gx + gy * gy + gz * gz)
end

-- ── DataStore helpers ─────────────────────────────────────────────────────────

local function dsGet(store, key: string): (boolean, any)
	return pcall(store.GetAsync, store, key)
end

local function dsSet(store, key: string, value: any): boolean
	local ok = pcall(store.SetAsync, store, key, value)
	return ok
end

local function dsRemove(store, key: string)
	pcall(store.RemoveAsync, store, key)
end

-- ── Broadcast helpers ─────────────────────────────────────────────────────────

local function buildPayload(syndicateId: string, data: SyndicateData): { [string]: any }
	return {
		syndicateId    = syndicateId,
		name           = data.name,
		members        = data.members,
		weeklyEarnings = data.weeklyEarnings,
	}
end

function SyndicateService:_FireToPlayer(player: Player)
	local syndicateId = _playerIndex[player.UserId]
	if not syndicateId then
		Remotes.SyndicateData:FireClient(player, nil)
		return
	end
	local data = _syndicates[syndicateId]
	if not data then
		Remotes.SyndicateData:FireClient(player, nil)
		return
	end
	Remotes.SyndicateData:FireClient(player, buildPayload(syndicateId, data))
end

function SyndicateService:_FireToAllMembers(syndicateId: string)
	local data = _syndicates[syndicateId]
	if not data then return end
	for _, memberId in ipairs(data.members) do
		local p = Players:GetPlayerByUserId(memberId)
		if p then
			Remotes.SyndicateData:FireClient(p, buildPayload(syndicateId, data))
		end
	end
end

-- ── Syndicate CRUD ────────────────────────────────────────────────────────────

function SyndicateService:_GetOrLoad(syndicateId: string): SyndicateData?
	if _syndicates[syndicateId] then return _syndicates[syndicateId] end
	local ok, data = dsGet(SyndicateStore, syndicateId)
	if ok and data then
		_syndicates[syndicateId] = data
		return data
	end
	return nil
end

function SyndicateService:CreateSyndicate(player: Player, name: string): string?
	local uid = player.UserId
	if _playerIndex[uid] then return nil end  -- already in a syndicate

	name = tostring(name):sub(1, 32)  -- cap name length
	if #name == 0 then return nil end

	local syndicateId = "S_" .. HttpService:GenerateGUID(false)
	local data: SyndicateData = {
		name           = name,
		members        = { uid },
		weeklyEarnings = 0,
	}

	if not dsSet(SyndicateStore, syndicateId, data) then return nil end
	dsSet(SyndicateIndex, "p_" .. uid, syndicateId)

	_syndicates[syndicateId]   = data
	_playerIndex[uid]          = syndicateId

	-- Track syndicateId in meta for weekly reset.
	table.insert(_meta.allSyndicateIds, syndicateId)
	dsSet(SyndicateStore, META_KEY, _meta)

	self:_FireToPlayer(player)
	return syndicateId
end

function SyndicateService:JoinSyndicate(player: Player, syndicateId: string): boolean
	local uid = player.UserId
	if _playerIndex[uid] then return false end  -- already in a syndicate

	local data = self:_GetOrLoad(syndicateId)
	if not data then return false end
	if #data.members >= MAX_MEMBERS then return false end

	table.insert(data.members, uid)
	dsSet(SyndicateStore, syndicateId, data)
	dsSet(SyndicateIndex, "p_" .. uid, syndicateId)
	_playerIndex[uid] = syndicateId

	self:_FireToAllMembers(syndicateId)
	return true
end

function SyndicateService:LeaveSyndicate(player: Player)
	local uid         = player.UserId
	local syndicateId = _playerIndex[uid]
	if not syndicateId then return end

	local data = _syndicates[syndicateId]
	if data then
		local idx = table.find(data.members, uid)
		if idx then table.remove(data.members, idx) end

		if #data.members == 0 then
			-- Last member left — delete the syndicate entirely.
			dsRemove(SyndicateStore, syndicateId)
			_syndicates[syndicateId] = nil

			local metaIdx = table.find(_meta.allSyndicateIds, syndicateId)
			if metaIdx then table.remove(_meta.allSyndicateIds, metaIdx) end
			dsSet(SyndicateStore, META_KEY, _meta)
		else
			dsSet(SyndicateStore, syndicateId, data)
			self:_FireToAllMembers(syndicateId)
		end
	end

	dsRemove(SyndicateIndex, "p_" .. uid)
	_playerIndex[uid] = nil

	Remotes.SyndicateData:FireClient(player, nil)
end

-- ── Public API (called by EconomyService) ─────────────────────────────────────

-- Returns true if any online syndicate member's zone is adjacent to the player's zone.
function SyndicateService:GetAdjacentBonus(player: Player): boolean
	local uid         = player.UserId
	local syndicateId = _playerIndex[uid]
	if not syndicateId then return false end

	local data = _syndicates[syndicateId]
	if not data then return false end

	local ok, ZoneService = pcall(Knit.GetService, Knit, "ZoneService")
	if not ok or not ZoneService then return false end

	local playerZone = ZoneService:GetPlayerZone(player)
	if not playerZone then return false end

	for _, memberId in ipairs(data.members) do
		if memberId == uid then continue end
		local memberPlayer = Players:GetPlayerByUserId(memberId)
		if not memberPlayer then continue end
		local memberZone = ZoneService:GetPlayerZone(memberPlayer)
		if not memberZone then continue end
		if zoneGap(playerZone :: BasePart, memberZone :: BasePart) <= ADJACENT_TOLERANCE then
			return true
		end
	end
	return false
end

-- Accumulates payout amount into the syndicate's weeklyEarnings counter.
function SyndicateService:RecordEarning(player: Player, amount: number)
	local syndicateId = _playerIndex[player.UserId]
	if not syndicateId then return end
	local data = _syndicates[syndicateId]
	if not data then return end
	data.weeklyEarnings += amount
end

-- ── Weekly reset ──────────────────────────────────────────────────────────────

function SyndicateService:_CheckWeeklyReset()
	local ok, meta = dsGet(SyndicateStore, META_KEY)
	if ok and meta then
		_meta = meta
	end

	local lastMondayTs = getLastMondayTimestamp()
	if (_meta.lastResetTimestamp or 0) >= lastMondayTs then return end

	-- Load all syndicates and sort by weeklyEarnings descending.
	local sorted: { { id: string, data: SyndicateData } } = {}
	for _, id in ipairs(_meta.allSyndicateIds or {}) do
		local okD, data = dsGet(SyndicateStore, id)
		if okD and data then
			table.insert(sorted, { id = id, data = data })
		end
	end
	table.sort(sorted, function(a, b)
		return a.data.weeklyEarnings > b.data.weeklyEarnings
	end)

	-- Grant banner rewards to top 3.
	local okC, CosmeticService = pcall(Knit.GetService, Knit, "CosmeticService")
	for rank = 1, math.min(3, #sorted) do
		local entry = sorted[rank]
		if okC and CosmeticService then
			for _, memberId in ipairs(entry.data.members) do
				CosmeticService:GrantBannerReward(memberId, entry.id)
			end
		end
	end

	-- Reset all weeklyEarnings.
	for _, entry in ipairs(sorted) do
		entry.data.weeklyEarnings = 0
		_syndicates[entry.id] = entry.data
		dsSet(SyndicateStore, entry.id, entry.data)
	end

	_meta.lastResetTimestamp = lastMondayTs
	dsSet(SyndicateStore, META_KEY, _meta)

	-- Notify all online players in syndicates.
	for _, player in Players:GetPlayers() do
		if _playerIndex[player.UserId] then
			self:_FireToPlayer(player)
		end
	end
end

-- ── Player lifecycle ──────────────────────────────────────────────────────────

function SyndicateService:_LoadPlayer(player: Player)
	local uid = player.UserId
	local ok, syndicateId = dsGet(SyndicateIndex, "p_" .. uid)
	if not ok or not syndicateId then
		_playerIndex[uid] = nil
		Remotes.SyndicateData:FireClient(player, nil)
		return
	end

	_playerIndex[uid] = syndicateId
	local data = self:_GetOrLoad(syndicateId)
	if data then
		Remotes.SyndicateData:FireClient(player, buildPayload(syndicateId, data))
	end
end

function SyndicateService:_SavePlayer(player: Player)
	local uid         = player.UserId
	local syndicateId = _playerIndex[uid]
	if not syndicateId then return end
	local data = _syndicates[syndicateId]
	if data then
		dsSet(SyndicateStore, syndicateId, data)
	end
end

-- ── Initialisation ────────────────────────────────────────────────────────────

function SyndicateService:KnitStart()
	-- Remote handlers.
	Remotes.SyndicateCreate:Connect(function(player: Player, name: string)
		task.spawn(function()
			self:CreateSyndicate(player, name)
		end)
	end)

	Remotes.SyndicateJoin:Connect(function(player: Player, syndicateId: string)
		task.spawn(function()
			self:JoinSyndicate(player, syndicateId)
		end)
	end)

	Remotes.SyndicateLeave:Connect(function(player: Player)
		task.spawn(function()
			self:LeaveSyndicate(player)
		end)
	end)

	-- Player lifecycle.
	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			self:_LoadPlayer(player)
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		task.spawn(function()
			self:_SavePlayer(player)
			_playerIndex[player.UserId] = nil
		end)
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:_LoadPlayer(player)
		end)
	end

	-- Weekly reset check on boot.
	task.spawn(function()
		self:_CheckWeeklyReset()
	end)

	-- Periodic background save.
	task.spawn(function()
		while true do
			task.wait(SAVE_INTERVAL)
			for syndicateId, data in _syndicates do
				dsSet(SyndicateStore, syndicateId, data)
			end
		end
	end)
end

return SyndicateService
